package com.rewardpilot.app.rewardpilot

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AutomationChannelHandler(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.rewardpilot/automation"
        private const val TAG = "AutomationChannel"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAccessibilityEnabled" -> {
                val isEnabled = isAccessibilityServiceEnabled()
                result.success(isEnabled)
            }
            "openAccessibilitySettings" -> {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                result.success(true)
            }
            "isCoinMasterInstalled" -> {
                val isInstalled = isPackageInstalled(CoinMasterAccessibilityService.COIN_MASTER_PACKAGE)
                result.success(isInstalled)
            }
            "launchRewardIntent" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.error("INVALID_URL", "Reward URL cannot be null or empty", null)
                    return
                }
                val launched = launchUrlIntent(url)
                result.success(launched)
            }
            "inspectCurrentScreen" -> {
                val service = CoinMasterAccessibilityService.instance
                if (service == null) {
                    result.success(mapOf(
                        "available" to false,
                        "error" to "Accessibility service is not running or not enabled in Settings",
                        "packageName" to "",
                        "allVisibleTexts" to emptyList<String>(),
                        "nodes" to emptyList<Map<String, Any?>>()
                    ))
                    return
                }
                val screenData = service.inspectCurrentScreen()
                result.success(screenData)
            }
            "performClickAction" -> {
                val service = CoinMasterAccessibilityService.instance
                if (service == null) {
                    result.error("SERVICE_UNAVAILABLE", "Accessibility service not running", null)
                    return
                }
                val targetText = call.argument<String>("targetText")
                val viewId = call.argument<String>("viewId")
                val x = call.argument<Int>("x")
                val y = call.argument<Int>("y")

                val clickResult = service.performAction(targetText, viewId, x, y)
                result.success(clickResult)
            }
            "forceStop" -> {
                CoinMasterAccessibilityService.instance?.forceStop()
                CoinMasterAccessibilityService.isForceStopped.set(true)
                Log.w(TAG, "Force stop command received from Flutter!")
                result.success(true)
            }
            "resetEmergencyStop" -> {
                CoinMasterAccessibilityService.instance?.resetForceStop()
                CoinMasterAccessibilityService.isForceStopped.set(false)
                Log.i(TAG, "Emergency stop reset from Flutter.")
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedService = "${context.packageName}/${CoinMasterAccessibilityService::class.java.canonicalName}"
        val enabledServices = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServices)
        while (colonSplitter.hasNext()) {
            val componentName = colonSplitter.next()
            if (componentName.equals(expectedService, ignoreCase = true) ||
                componentName.contains(CoinMasterAccessibilityService::class.java.simpleName, ignoreCase = true)) {
                return true
            }
        }
        return CoinMasterAccessibilityService.isServiceActive
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            context.packageManager.getPackageInfo(packageName, PackageManager.GET_ACTIVITIES)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun launchUrlIntent(url: String): Boolean {
        return try {
            val uri = Uri.parse(url)
            val isCoinMasterInstalled = isPackageInstalled(CoinMasterAccessibilityService.COIN_MASTER_PACKAGE)

            // Direct intent routing:
            // If Coin Master is installed and the link contains a promo parameter (?c=...),
            // construct the direct "coinmaster://promotions?c=..." URI.
            // This routes directly to Coin Master's GameActivity and eliminates any browser 403 S3 XML errors!
            val intent: Intent = if (url.startsWith("coinmaster://")) {
                Intent(Intent.ACTION_VIEW, uri).apply {
                    setPackage(CoinMasterAccessibilityService.COIN_MASTER_PACKAGE)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            } else if (isCoinMasterInstalled) {
                val campaignCode = uri.getQueryParameter("c")
                if (!campaignCode.isNullOrEmpty()) {
                    val deepLink = Uri.parse("coinmaster://promotions?c=$campaignCode")
                    Intent(Intent.ACTION_VIEW, deepLink).apply {
                        setPackage(CoinMasterAccessibilityService.COIN_MASTER_PACKAGE)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                } else {
                    val fixedUrl = fixRewardUrl(url)
                    Intent(Intent.ACTION_VIEW, Uri.parse(fixedUrl)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                }
            } else {
                val fixedUrl = fixRewardUrl(url)
                Intent(Intent.ACTION_VIEW, Uri.parse(fixedUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            }

            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error launching reward intent: ${e.message}", e)
            try {
                // Fallback launch directly into Coin Master game if installed
                if (isPackageInstalled(CoinMasterAccessibilityService.COIN_MASTER_PACKAGE)) {
                    val launchIntent = context.packageManager.getLaunchIntentForPackage(CoinMasterAccessibilityService.COIN_MASTER_PACKAGE)
                    if (launchIntent != null) {
                        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(launchIntent)
                        return true
                    }
                }
                false
            } catch (fallbackError: Exception) {
                Log.e(TAG, "Fallback launch failed: ${fallbackError.message}")
                false
            }
        }
    }

    private fun fixRewardUrl(url: String): String {
        return if (url.contains("static.moonactive.net") && !url.contains("reward2.html")) {
            val uri = Uri.parse(url)
            val c = uri.getQueryParameter("c") ?: ""
            "https://static.moonactive.net/static/coinmaster/reward/reward2.html?c=$c"
        } else {
            url
        }
    }
}
