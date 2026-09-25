package com.mel0ny.linkup

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat

/**
 * 认证运行时的常驻通知。
 *
 * 通知只渲染 Dart 侧发布的状态文本，不读取用户信息或认证参数，因此不会出现
 * 账号、密码、Challenge、HMD5 或签名。
 */
object AuthRuntimeNotification {
    const val CHANNEL_ID = "linkup_auth_runtime"
    const val NOTIFICATION_ID = 1001

    private const val FALLBACK_TITLE = "LinkUp 校园网认证"
    private const val FALLBACK_TEXT = "后台认证运行中"

    /** 低重要性常驻渠道：可见但不发出提示音或震动。 */
    fun ensureChannel(context: Context) {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "校园网认证状态",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "显示后台校园网认证的当前状态"
            setShowBadge(false)
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    fun build(context: Context, state: Map<Any?, Any?>?): Notification {
        val content = state?.get("notification") as? Map<Any?, Any?>
        val title = content?.get("title") as? String ?: FALLBACK_TITLE
        val text = content?.get("text") as? String ?: FALLBACK_TEXT
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_auth_runtime_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(AuthRuntimeService.launchIntent(context))
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }
}
