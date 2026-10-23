package com.rewardpilot.app.rewardpilot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AutomationChannelHandler.CHANNEL_NAME
        )
        channel.setMethodCallHandler(AutomationChannelHandler(this))
    }
}
