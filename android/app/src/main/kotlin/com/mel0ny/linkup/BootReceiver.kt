package com.mel0ny.linkup

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // 检查是否开启了开机自启
            // 注意：shared_preferences 插件把所有 key 加上 "flutter." 前缀，
            // 存储桶名固定为 "FlutterSharedPreferences"，必须与 Dart 侧一致才能读到。
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val autoStart = prefs.getBoolean("flutter.auto_start", false)
            // 留 logcat 痕迹：未来若 shared_preferences 插件升级改了 bucket/前缀
            // （pre-2.0 历史上确有过此类变更），自启会静默失效，至少这里能定位
            Log.i("LinkUpBoot", "BootReceiver autoStart=$autoStart")

            if (autoStart) {
                // 启动主Activity
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                launchIntent?.let {
                    it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(it)
                }
            }
        }
    }
}
