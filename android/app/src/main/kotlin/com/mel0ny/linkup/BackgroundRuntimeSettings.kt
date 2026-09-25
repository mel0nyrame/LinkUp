package com.mel0ny.linkup

import android.content.Context

/**
 * “保留后台运行”和“开机自启动”偏好的原生读取入口。
 *
 * `shared_preferences` 插件把所有 key 加上 `flutter.` 前缀并固定存储桶名
 * `FlutterSharedPreferences`，必须与 Dart 侧一致才能读到。
 */
object BackgroundRuntimeSettings {
    private const val PREFERENCES = "FlutterSharedPreferences"
    private const val KEY_KEEP_ALIVE = "flutter.keep_alive"
    private const val KEY_AUTO_START = "flutter.auto_start"

    fun isKeepAliveEnabled(context: Context): Boolean {
        return preference(context, KEY_KEEP_ALIVE, true)
    }

    fun isAutoStartEnabled(context: Context): Boolean {
        return preference(context, KEY_AUTO_START, false)
    }

    private fun preference(context: Context, key: String, fallback: Boolean): Boolean {
        return context
            .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(key, fallback)
    }
}
