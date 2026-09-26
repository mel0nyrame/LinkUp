package com.mel0ny.linkup

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = AuthRuntimeBridge.SYSTEM_CHANNEL
    private val UI_CHANNEL = AuthRuntimeBridge.UI_CHANNEL

    private var uiChannel: MethodChannel? = null
    private var authRuntime: AuthRuntimeService.LocalBinder? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            if (binder !is AuthRuntimeService.LocalBinder) return
            authRuntime = binder
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            authRuntime = null
        }
    }

    override fun onStart() {
        super.onStart()
        bindService(
            Intent(this, AuthRuntimeService::class.java),
            connection,
            Context.BIND_AUTO_CREATE,
        )
    }

    override fun onStop() {
        // Activity 销毁后：开启“保留后台运行”的服务继续运行，关闭的随绑定结束。
        uiChannel?.let { AuthRuntimeBridge.unregisterClient(it) }
        unbindService(connection)
        authRuntime = null
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                AuthRuntimeBridge.SYSTEM_IS_AUTO_START_SUPPORTED -> {
                    result.success(true)
                }
                AuthRuntimeBridge.SYSTEM_CHECK_AUTO_START_PERMISSION -> {
                    result.success(checkAutoStartPermission())
                }
                AuthRuntimeBridge.SYSTEM_REQUEST_AUTO_START_PERMISSION -> {
                    requestAutoStartPermission()
                    result.success(null)
                }
                AuthRuntimeBridge.SYSTEM_OPEN_BATTERY_OPTIMIZATION_SETTINGS -> {
                    openBatteryOptimizationSettings()
                    result.success(null)
                }
                AuthRuntimeBridge.SYSTEM_START_AUTH_RUNTIME -> {
                    startAuthRuntime()
                    result.success(null)
                }
                AuthRuntimeBridge.SYSTEM_STOP_AUTH_RUNTIME -> {
                    stopAuthRuntime()
                    result.success(null)
                }
                AuthRuntimeBridge.SYSTEM_REQUEST_NOTIFICATION_PERMISSION -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val runtimeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UI_CHANNEL)
        runtimeChannel.setMethodCallHandler(::handleRuntimeCall)
        uiChannel = runtimeChannel
    }

    /**
     * Activity 侧只转发命令并接收状态，不复制认证规则。
     */
    private fun handleRuntimeCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            AuthRuntimeBridge.METHOD_ATTACH -> {
                uiChannel?.let { AuthRuntimeBridge.registerClient(it) }
                result.success(AuthRuntimeBridge.latestState)
            }

            AuthRuntimeBridge.METHOD_DETACH -> {
                uiChannel?.let { AuthRuntimeBridge.unregisterClient(it) }
                result.success(null)
            }

            AuthRuntimeBridge.METHOD_COMMAND, AuthRuntimeBridge.METHOD_FIRE_COMMAND -> {
                val name = call.argument<String>(AuthRuntimeBridge.KEY_NAME)
                if (name == null) {
                    result.error("invalid_command", "认证运行时命令缺少名称", null)
                    return
                }
                AuthRuntimeBridge.dispatch(
                    name,
                    call.argument<Map<String, Any?>>(AuthRuntimeBridge.KEY_ARGS),
                    if (call.method == AuthRuntimeBridge.METHOD_COMMAND) result else null,
                )
                if (call.method == AuthRuntimeBridge.METHOD_FIRE_COMMAND) result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * 开启“保留后台运行”。
     *
     * 必须走 `startForegroundService` 把服务提升为 started 状态：仅绑定的服务在
     * Activity 解绑后会被系统销毁，后台认证无法继续。已绑定的服务实例与新启动的
     * 是同一个，因此无需再经 binder 转发。
     */
    private fun startAuthRuntime() {
        AuthRuntimeService.start(this)
    }

    private fun stopAuthRuntime() {
        authRuntime?.service?.stopRuntime() ?: AuthRuntimeService.stop(this)
    }

    /**
     * Android 13+ 在用户主动开启后台运行时请求通知权限。
     *
     * 用户拒绝不会导致崩溃：前台服务照常运行，只是系统不再展示常驻通知。
     */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun checkAutoStartPermission(): Boolean {
        // 检查是否已启用开机自启
        val component = ComponentName(this, BootReceiver::class.java)
        val state = packageManager.getComponentEnabledSetting(component)
        return state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
               state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
    }

    private fun requestAutoStartPermission() {
        // 尝试打开不同厂商的自启动设置页面
        try {
            // 通用设置
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun openBatteryOptimizationSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val packageName = packageName
            val intent = Intent().apply {
                action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                data = Uri.parse("package:$packageName")
            }
            try {
                startActivity(intent)
            } catch (e: Exception) {
                // 如果特定操作失败，打开通用电池设置
                val fallbackIntent = Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                try {
                    startActivity(fallbackIntent)
                } catch (e2: Exception) {
                    e2.printStackTrace()
                }
            }
        }
    }

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 1002
    }
}
