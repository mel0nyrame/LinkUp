package com.mel0ny.linkup

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * 承载后台认证运行时的前台服务。
 *
 * 服务创建独立 FlutterEngine，通过 callback dispatcher 驱动 Dart 认证入口。
 * Srun 协议和协调器逻辑不在 Kotlin 中复制，仍然只有一份 Dart 实现。
 */
class AuthRuntimeService : Service() {
    private val binder = LocalBinder()
    private var engine: FlutterEngine? = null
    private var foreground = false

    inner class LocalBinder : Binder() {
        val service: AuthRuntimeService get() = this@AuthRuntimeService
    }

    override fun onCreate() {
        super.onCreate()
        AuthRuntimeNotification.ensureChannel(this)
        AuthRuntimeBridge.onState = { state -> publishState(state) }
        createAuthRuntime()
    }

    override fun onBind(intent: Intent?): IBinder {
        // Activity 可见时只绑定这一个运行时，不创建第二个协调器。
        AuthRuntimeBridge.dispatch(AuthRuntimeBridge.COMMAND_START)
        return binder
    }

    override fun onRebind(intent: Intent?) {
        AuthRuntimeBridge.dispatch(AuthRuntimeBridge.COMMAND_START)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        if (BackgroundRuntimeSettings.isKeepAliveEnabled(this)) return true
        // 未开启“保留后台运行”时，服务随绑定结束而释放运行时。
        stopSelf()
        return false
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android 要求通过 startForegroundService 启动的服务尽快进入前台。
        enterForeground()
        if (!BackgroundRuntimeSettings.isKeepAliveEnabled(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        AuthRuntimeBridge.dispatch(AuthRuntimeBridge.COMMAND_START)
        // START_STICKY 让系统在允许的回收后重建服务并恢复运行时。用户主动
        // force-stop 属于系统不会恢复的边界，文档不承诺该场景。
        return START_STICKY
    }

    override fun onDestroy() {
        AuthRuntimeBridge.onState = null
        AuthRuntimeBridge.detachEngine()
        // 销毁 engine 即终止后台 isolate，HTTP client、Portal 缓存和调度随之释放。
        engine?.destroy()
        engine = null
        if (foreground) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            foreground = false
        }
        super.onDestroy()
    }

    /** 开启“保留后台运行”时进入前台并恢复监控。 */
    fun startForegroundRuntime() {
        enterForeground()
        AuthRuntimeBridge.dispatch(AuthRuntimeBridge.COMMAND_START)
    }

    /**
     * 关闭“保留后台运行”时停止前台服务并释放认证运行时资源。
     *
     * 运行时先停止调度并释放 HTTP client 与 Portal 缓存；仍被 Activity 绑定时
     * 服务不立即销毁，绑定结束后才释放 FlutterEngine。
     */
    fun stopRuntime() {
        AuthRuntimeBridge.dispatch(AuthRuntimeBridge.COMMAND_STOP)
        if (foreground) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            foreground = false
        }
        stopSelf()
    }

    private fun enterForeground() {
        if (foreground) return
        val notification = AuthRuntimeNotification.build(this, AuthRuntimeBridge.latestState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                AuthRuntimeNotification.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(AuthRuntimeNotification.NOTIFICATION_ID, notification)
        }
        foreground = true
    }

    private fun publishState(state: Map<Any?, Any?>) {
        if (!foreground) return
        val manager = getSystemService(android.app.NotificationManager::class.java)
        manager.notify(
            AuthRuntimeNotification.NOTIFICATION_ID,
            AuthRuntimeNotification.build(this, state),
        )
    }

    private fun createAuthRuntime() {
        if (engine != null) return
        val options = FlutterEngineGroup.Options(this)
            .setDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "package:LinkUp/authRuntimeMain.dart",
                    "linkupAuthRuntimeDispatcher",
                )
            )
        val created = FlutterEngineGroup(this).createAndRunEngine(options)
        // 必需插件必须显式注册到后台 engine，Keystore 秘密存储才能在其中使用。
        // 注册与下面的通道注册都在 Dart isolate 真正运行之前完成。
        GeneratedPluginRegistrant.registerWith(created)
        AuthRuntimeBridge.attachEngine(this, created)
        engine = created
    }

    companion object {
        fun launchIntent(context: Context): PendingIntent {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        fun start(context: Context) {
            val intent = Intent(context, AuthRuntimeService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AuthRuntimeService::class.java))
        }
    }
}
