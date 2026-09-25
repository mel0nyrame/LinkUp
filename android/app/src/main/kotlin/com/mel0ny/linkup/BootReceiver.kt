package com.mel0ny.linkup

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机后恢复后台认证服务。
 *
 * 开机自启是“保留后台运行”的下游开关：三个条件同时满足才启动前台服务，任何一个
 * 不满足都不启动。这里只启动 [AuthRuntimeService]，绝不拉起 Activity——后台认证
 * 由服务自己持有的运行时承担，不需要界面。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val keepAlive = BackgroundRuntimeSettings.isKeepAliveEnabled(context)
        val autoStart = BackgroundRuntimeSettings.isAutoStartEnabled(context)
        val configured = BackgroundRuntimeSettings.isAccountConfigured(context)
        // 留 logcat 痕迹：若 shared_preferences 插件升级改了桶名或 key 前缀
        // （pre-2.0 历史上确有过此类变更），开机启动会静默失效，至少这里能定位。
        Log.i(TAG, "BootReceiver keepAlive=$keepAlive autoStart=$autoStart configured=$configured")

        if (!keepAlive || !autoStart || !configured) return
        AuthRuntimeService.start(context)
    }

    private companion object {
        const val TAG = "LinkUpBoot"
    }
}
