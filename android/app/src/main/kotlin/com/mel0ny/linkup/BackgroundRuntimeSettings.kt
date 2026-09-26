package com.mel0ny.linkup

import android.content.Context

/**
 * 后台运行相关偏好的原生读取入口。
 *
 * `shared_preferences` 插件把所有 key 加上 `flutter.` 前缀并固定存储桶名
 * `FlutterSharedPreferences`，必须与 Dart 侧一致才能读到。
 */
object BackgroundRuntimeSettings {
    private const val PREFERENCES = AuthRuntimeBridge.PREFERENCES_NAME
    private const val KEY_KEEP_ALIVE = AuthRuntimeBridge.PREFERENCE_PREFIX + AuthRuntimeBridge.PREFERENCE_KEEP_ALIVE
    private const val KEY_AUTO_START = AuthRuntimeBridge.PREFERENCE_PREFIX + AuthRuntimeBridge.PREFERENCE_AUTO_START
    private const val KEY_ACCOUNT_CONFIGURED = AuthRuntimeBridge.PREFERENCE_PREFIX + AuthRuntimeBridge.PREFERENCE_ACCOUNT_CONFIGURED

    /** 与 [com.mel0ny.linkup.utils.SystemSettingsUtil.getKeepAlive] 的默认值一致。 */
    fun isKeepAliveEnabled(context: Context): Boolean {
        return context
            .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(KEY_KEEP_ALIVE, AuthRuntimeBridge.DEFAULT_KEEP_ALIVE)
    }

    /** 与 [com.mel0ny.linkup.utils.SystemSettingsUtil.getAutoStart] 的默认值一致。 */
    fun isAutoStartEnabled(context: Context): Boolean {
        return context
            .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(KEY_AUTO_START, AuthRuntimeBridge.DEFAULT_AUTO_START)
    }

    /**
     * 是否已有可用的账号配置。
     *
     * 配置文件在 Dart isolate 管理的文档目录里，开机时读不到；Dart 侧在保存、删除
     * 和每次启动检查时同步这个派生标记，因此以它为准。缺失时按“无配置”处理：
     * 开机不启动服务是安全方向，总比启动后必然认证失败更好。
     */
    fun isAccountConfigured(context: Context): Boolean {
        return context
            .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(KEY_ACCOUNT_CONFIGURED, AuthRuntimeBridge.DEFAULT_ACCOUNT_CONFIGURED)
    }
}
