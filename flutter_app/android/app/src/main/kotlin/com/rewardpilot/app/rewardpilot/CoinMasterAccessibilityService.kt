package com.rewardpilot.app.rewardpilot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.util.DisplayMetrics
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.atomic.AtomicBoolean

class CoinMasterAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "CoinMasterAccService"
        const val COIN_MASTER_PACKAGE = "com.moonactive.coinmaster"

        @Volatile
        var instance: CoinMasterAccessibilityService? = null
            private set

        val isServiceActive: Boolean
            get() = instance != null

        val isForceStopped = AtomicBoolean(false)
    }

    private val textRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    // Cached recognized texts and bounds from local on-device ML Kit OCR
    @Volatile
    private var lastOcrTexts = listOf<String>()
    @Volatile
    private var lastOcrNodes = listOf<Map<String, Any?>>()
    @Volatile
    private var lastOcrTimestamp: Long = 0

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        isForceStopped.set(false)
        Log.i(TAG, "CoinMasterAccessibilityService connected and ready.")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (isForceStopped.get()) {
            return
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "CoinMasterAccessibilityService interrupted.")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance == this) {
            instance = null
        }
        try {
            textRecognizer.close()
        } catch (_: Exception) {}
        Log.i(TAG, "CoinMasterAccessibilityService destroyed.")
    }

    /**
     * Emergency Force Stop: drops any pending actions immediately.
     */
    fun forceStop() {
        isForceStopped.set(true)
        Log.w(TAG, "EMERGENCY FORCE STOP triggered in native service.")
    }

    fun resetForceStop() {
        isForceStopped.set(false)
        Log.i(TAG, "Force stop flag reset in native service.")
    }

    /**
     * Inspects the current active window and returns structured node data.
     * Uses accessibility node tree, with on-device local OCR fallback for Unity SurfaceViews.
     */
    fun inspectCurrentScreen(): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        if (isForceStopped.get()) {
            result["error"] = "Service is force stopped"
            result["isForceStopped"] = true
            return result
        }

        val rootNode = rootInActiveWindow
        if (rootNode == null) {
            result["packageName"] = ""
            result["allVisibleTexts"] = emptyList<String>()
            result["nodes"] = emptyList<Map<String, Any?>>()
            result["isEmpty"] = true
            return result
        }

        try {
            val packageName = rootNode.packageName?.toString() ?: ""
            val allTexts = mutableListOf<String>()
            val nodeList = mutableListOf<Map<String, Any?>>()

            traverseNode(rootNode, allTexts, nodeList)

            // If inside Coin Master and standard node text is empty (Unity SurfaceView),
            // trigger / merge on-device OCR fallback!
            if (packageName == COIN_MASTER_PACKAGE) {
                requestScreenOcrCapture()

                val now = System.currentTimeMillis()
                if (allTexts.isEmpty() && lastOcrTexts.isNotEmpty() && (now - lastOcrTimestamp) < 6000) {
                    allTexts.addAll(lastOcrTexts)
                    nodeList.addAll(lastOcrNodes)
                    Log.d(TAG, "Merged ${lastOcrTexts.size} OCR detected strings into screen data.")
                }
            }

            val displayMetrics = resources.displayMetrics
            result["packageName"] = packageName
            result["allVisibleTexts"] = allTexts
            result["nodes"] = nodeList
            result["timestamp"] = System.currentTimeMillis()
            result["isCoinMaster"] = (packageName == COIN_MASTER_PACKAGE)
            result["screenWidth"] = displayMetrics.widthPixels
            result["screenHeight"] = displayMetrics.heightPixels
            return result
        } finally {
            rootNode.recycle()
        }
    }

    private fun requestScreenOcrCapture() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !isForceStopped.get()) {
            try {
                takeScreenshot(
                    Display.DEFAULT_DISPLAY,
                    mainExecutor,
                    object : TakeScreenshotCallback {
                        override fun onSuccess(screenshotResult: ScreenshotResult) {
                            try {
                                val hardwareBuffer = screenshotResult.hardwareBuffer
                                val colorSpace = screenshotResult.colorSpace
                                val bitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace)
                                hardwareBuffer.close()

                                if (bitmap != null) {
                                    val copy = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                                    if (copy != null) {
                                        val image = InputImage.fromBitmap(copy, 0)
                                        textRecognizer.process(image)
                                            .addOnSuccessListener { visionText ->
                                                val texts = mutableListOf<String>()
                                                val nodes = mutableListOf<Map<String, Any?>>()
                                                for (block in visionText.textBlocks) {
                                                    for (line in block.lines) {
                                                        val t = line.text.trim()
                                                        if (t.isNotEmpty()) {
                                                            texts.add(t)
                                                            val box = line.boundingBox
                                                            if (box != null) {
                                                                nodes.add(mapOf(
                                                                    "text" to t,
                                                                    "contentDescription" to "",
                                                                    "viewId" to "",
                                                                    "className" to "android.widget.TextView",
                                                                    "isClickable" to true,
                                                                    "isEnabled" to true,
                                                                    "bounds" to mapOf(
                                                                        "left" to box.left,
                                                                        "top" to box.top,
                                                                        "right" to box.right,
                                                                        "bottom" to box.bottom,
                                                                        "width" to box.width(),
                                                                        "height" to box.height()
                                                                    )
                                                                ))
                                                            }
                                                        }
                                                    }
                                                }
                                                lastOcrTexts = texts
                                                lastOcrNodes = nodes
                                                lastOcrTimestamp = System.currentTimeMillis()
                                                Log.d(TAG, "OCR capture completed with ${texts.size} items: ${texts.take(5)}")
                                            }
                                            .addOnFailureListener { e ->
                                                Log.w(TAG, "OCR recognition failed: ${e.message}")
                                            }
                                    }
                                }
                            } catch (e: Exception) {
                                Log.w(TAG, "Screenshot extraction error: ${e.message}")
                            }
                        }

                        override fun onFailure(errorCode: Int) {
                            Log.w(TAG, "Accessibility takeScreenshot failed with code: $errorCode")
                        }
                    }
                )
            } catch (e: Exception) {
                Log.w(TAG, "Error invoking takeScreenshot: ${e.message}")
            }
        }
    }

    private fun traverseNode(
        node: AccessibilityNodeInfo,
        allTexts: MutableList<String>,
        nodeList: MutableList<Map<String, Any?>>
    ) {
        val text = node.text?.toString()?.trim()
        val contentDesc = node.contentDescription?.toString()?.trim()
        val viewId = node.viewIdResourceName
        val className = node.className?.toString() ?: ""
        val bounds = Rect()
        node.getBoundsInScreen(bounds)

        if (!text.isNullOrEmpty()) {
            allTexts.add(text)
        } else if (!contentDesc.isNullOrEmpty()) {
            allTexts.add(contentDesc)
        }

        val nodeMap = mutableMapOf<String, Any?>(
            "text" to (text ?: ""),
            "contentDescription" to (contentDesc ?: ""),
            "viewId" to (viewId ?: ""),
            "className" to className,
            "isClickable" to node.isClickable,
            "isEnabled" to node.isEnabled,
            "bounds" to mapOf(
                "left" to bounds.left,
                "top" to bounds.top,
                "right" to bounds.right,
                "bottom" to bounds.bottom,
                "width" to bounds.width(),
                "height" to bounds.height()
            )
        )
        nodeList.add(nodeMap)

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            traverseNode(child, allTexts, nodeList)
            child.recycle()
        }
    }

    /**
     * Finds and activates a control matching target keywords.
     * Specifically handles:
     * - "Collect" / "CLAIM" buttons on valid rewards
     * - "OK" / "Close" / "Continue" buttons on expired or already-claimed dialogs
     * - "OK" dismissal on "Please check your internet connection" popups
     */
    fun performAction(targetText: String?, viewId: String?, x: Int?, y: Int?): Map<String, Any> {
        val response = mutableMapOf<String, Any>()
        if (isForceStopped.get()) {
            response["success"] = false
            response["reason"] = "Action rejected: Emergency Force Stop is active."
            return response
        }

        val displayMetrics = resources.displayMetrics
        val screenW = displayMetrics.widthPixels
        val screenH = displayMetrics.heightPixels

        // Priority 1: Exact coordinates provided
        if (x != null && y != null && x > 0 && y > 0) {
            val dispatched = dispatchClickGesture(x.toFloat(), y.toFloat())
            response["success"] = dispatched
            response["method"] = "gesture_coordinate_dispatch"
            response["coordinates"] = "x=$x, y=$y"
            return response
        }

        val root = rootInActiveWindow
        try {
            // Priority 2: Match by text / content description in accessibility nodes
            if (root != null && !targetText.isNullOrEmpty()) {
                val matchedNode = findMatchingNode(root, targetText)
                if (matchedNode != null) {
                    val clicked = executeClickOnNode(matchedNode)
                    matchedNode.recycle()
                    response["success"] = clicked
                    response["method"] = if (clicked) "accessibility_node_click" else "click_failed"
                    response["targetText"] = targetText
                    return response
                }
            }

            // Priority 3: Match by viewId
            if (root != null && !viewId.isNullOrEmpty()) {
                val nodesById = root.findAccessibilityNodeInfosByViewId(viewId)
                if (nodesById.isNotEmpty()) {
                    val targetNode = nodesById[0]
                    val clicked = executeClickOnNode(targetNode)
                    for (n in nodesById) n.recycle()
                    response["success"] = clicked
                    response["method"] = if (clicked) "view_id_click" else "click_failed"
                    response["viewId"] = viewId
                    return response
                }
            }

            // Priority 4: Search recent OCR recognized nodes
            if (!targetText.isNullOrEmpty() && lastOcrNodes.isNotEmpty()) {
                val lowerTarget = targetText.lowercase().trim()
                for (ocrNode in lastOcrNodes) {
                    val text = (ocrNode["text"] as? String)?.lowercase()?.trim() ?: ""
                    if (text == lowerTarget || text.contains(lowerTarget)) {
                        val bounds = ocrNode["bounds"] as? Map<*, *>
                        if (bounds != null) {
                            val left = (bounds["left"] as? Number)?.toFloat() ?: 0f
                            val right = (bounds["right"] as? Number)?.toFloat() ?: 0f
                            val top = (bounds["top"] as? Number)?.toFloat() ?: 0f
                            val bottom = (bounds["bottom"] as? Number)?.toFloat() ?: 0f
                            val centerX = (left + right) / 2f
                            val centerY = (top + bottom) / 2f
                            if (centerX > 0 && centerY > 0) {
                                val dispatched = dispatchClickGesture(centerX, centerY)
                                response["success"] = dispatched
                                response["method"] = "ocr_bounding_box_click"
                                response["coordinates"] = "x=$centerX, y=$centerY"
                                response["targetText"] = text
                                return response
                            }
                        }
                    }
                }
            }

            // Priority 5: Resolution-Adaptive Fallback for Coin Master Dialogs
            // (Unity SurfaceView does not expose UI widgets to Android Accessibility tree)
            val lowerTarget = targetText?.lowercase()?.trim() ?: ""
            if (lowerTarget == "ok" || lowerTarget == "close" || lowerTarget == "dismiss" || lowerTarget == "cancel" || lowerTarget == "try again") {
                // Coin Master modal OK button location: centered horizontally, ~58% down screen
                val okX = (screenW * 0.5f)
                val okY = (screenH * 0.575f)
                Log.i(TAG, "Dispatching adaptive OK dismiss gesture at ($okX, $okY)")
                val dispatched = dispatchClickGesture(okX, okY)
                response["success"] = dispatched
                response["method"] = "adaptive_modal_ok_dismiss"
                response["coordinates"] = "x=$okX, y=$okY"
                return response
            } else if (lowerTarget == "collect" || lowerTarget == "claim" || lowerTarget == "collect now") {
                // Coin Master reward dialog Collect button location: centered horizontally, ~61.5% down screen
                val collectX = (screenW * 0.5f)
                val collectY = (screenH * 0.615f)
                Log.i(TAG, "Dispatching adaptive Collect gesture at ($collectX, $collectY)")
                val dispatched = dispatchClickGesture(collectX, collectY)
                response["success"] = dispatched
                response["method"] = "adaptive_reward_collect"
                response["coordinates"] = "x=$collectX, y=$collectY"
                return response
            }

            response["success"] = false
            response["reason"] = "No matching element found for '$targetText'"
            return response
        } finally {
            root?.recycle()
        }
    }

    private fun findMatchingNode(root: AccessibilityNodeInfo, target: String): AccessibilityNodeInfo? {
        val lowerTarget = target.lowercase().trim()
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)

        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            val text = node.text?.toString()?.lowercase()?.trim() ?: ""
            val desc = node.contentDescription?.toString()?.lowercase()?.trim() ?: ""

            if (text == lowerTarget || desc == lowerTarget || text.contains(lowerTarget) || desc.contains(lowerTarget)) {
                return node
            }

            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                if (child != null) {
                    queue.add(child)
                }
            }
        }
        return null
    }

    private fun executeClickOnNode(node: AccessibilityNodeInfo): Boolean {
        if (node.isClickable && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            Log.d(TAG, "Direct node ACTION_CLICK succeeded")
            return true
        }

        var parent = node.parent
        while (parent != null) {
            if (parent.isClickable && parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                Log.d(TAG, "Parent node ACTION_CLICK succeeded")
                parent.recycle()
                return true
            }
            val nextParent = parent.parent
            parent.recycle()
            parent = nextParent
        }

        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        if (bounds.width() > 0 && bounds.height() > 0) {
            val centerX = bounds.centerX().toFloat()
            val centerY = bounds.centerY().toFloat()
            Log.d(TAG, "Falling back to gesture dispatch at center ($centerX, $centerY)")
            return dispatchClickGesture(centerX, centerY)
        }

        return false
    }

    private fun dispatchClickGesture(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "Gesture dispatch requires Android N (API 24)+")
            return false
        }
        if (isForceStopped.get()) {
            Log.w(TAG, "Gesture canceled: Force stop is active")
            return false
        }

        val clickPath = Path()
        clickPath.moveTo(x, y)

        val stroke = GestureDescription.StrokeDescription(clickPath, 0, 80)
        val builder = GestureDescription.Builder()
        builder.addStroke(stroke)
        val gesture = builder.build()

        return dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                super.onCompleted(gestureDescription)
                Log.d(TAG, "Gesture click completed at ($x, $y)")
            }

            override fun onCancelled(gestureDescription: GestureDescription?) {
                super.onCancelled(gestureDescription)
                Log.w(TAG, "Gesture click cancelled at ($x, $y)")
            }
        }, null)
    }
}
