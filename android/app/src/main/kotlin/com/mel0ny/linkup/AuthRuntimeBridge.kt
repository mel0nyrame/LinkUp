package com.mel0ny.linkup

import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 后台认证运行时与 Dart 之间的窄桥。
 *
 * 命令和状态通过后台 engine 的 MethodChannel 双向传递。
 * 这里不包含认证协议、状态机或退避规则；Srun 协议和协调器只有一份 Dart 实现。
 */
object AuthRuntimeBridge {
    private const val TAG = "LinkUpAuthRuntime"

    // BEGIN runtime contract: tool/generate_runtime_contract.dart 派生 Dart 常量。
    const val HOST_CHANNEL = "com.mel0ny.linkup/authRuntime"
    const val UI_CHANNEL = "com.mel0ny.linkup/authUi"
    const val SYSTEM_CHANNEL = "com.mel0ny.linkup/system"

    const val COMMAND_START = "start"
    const val COMMAND_STOP = "stop"
    const val COMMAND_MANUAL_CHECK = "manualCheck"
    const val COMMAND_LOGOUT = "logout"
    const val COMMAND_KICK_DEVICE = "kickDevice"
    const val COMMAND_CONFIGURATION_CHANGED = "configurationChanged"
    const val COMMAND_NETWORK_CHANGED = "networkChanged"

    const val METHOD_READY = "ready"
    const val METHOD_STATE = "state"
    const val METHOD_COMMAND = "command"
    const val METHOD_FIRE_COMMAND = "fireCommand"
    const val METHOD_ATTACH = "attach"
    const val METHOD_DETACH = "detach"
    const val METHOD_ON_STATE = "onState"

    const val KEY_NAME = "name"
    const val KEY_ARGS = "args"
    const val KEY_STATUS = "status"
    const val KEY_IS_ONLINE = "isOnline"
    const val KEY_MESSAGE = "message"
    const val KEY_REASON = "reason"
    const val KEY_ACID = "acid"
    const val KEY_RETRY_AFTER_SECONDS = "retryAfterSeconds"
    const val KEY_USER_INFO = "userInfo"
    const val KEY_NOTIFICATION = "notification"
    const val KEY_TITLE = "title"
    const val KEY_TEXT = "text"
    const val KEY_CONNECTED = "connected"
    const val KEY_IP = "ip"

    const val PREFERENCES_NAME = "FlutterSharedPreferences"
    const val PREFERENCE_PREFIX = "flutter."
    const val PREFERENCE_KEEP_ALIVE = "keep_alive"
    const val PREFERENCE_AUTO_START = "auto_start"
    const val PREFERENCE_ACCOUNT_CONFIGURED = "account_configured"
    const val DEFAULT_KEEP_ALIVE = true
    const val DEFAULT_AUTO_START = false
    const val DEFAULT_ACCOUNT_CONFIGURED = false

    const val SYSTEM_START_AUTH_RUNTIME = "startAuthRuntime"
    const val SYSTEM_STOP_AUTH_RUNTIME = "stopAuthRuntime"
    const val SYSTEM_REQUEST_NOTIFICATION_PERMISSION = "requestNotificationPermission"
    const val SYSTEM_IS_AUTO_START_SUPPORTED = "isAutoStartSupported"
    const val SYSTEM_CHECK_AUTO_START_PERMISSION = "checkAutoStartPermission"
    const val SYSTEM_REQUEST_AUTO_START_PERMISSION = "requestAutoStartPermission"
    const val SYSTEM_OPEN_BATTERY_OPTIMIZATION_SETTINGS = "openBatteryOptimizationSettings"
    // END runtime contract

    /** 状态消费者，由前台服务注册，用于刷新常驻通知。 */
    var onState: ((Map<Any?, Any?>) -> Unit)? = null

    private var runtimeChannel: MethodChannel? = null
    private var runtimeReady = false
    private var nextRequestId = 0L
    private val queuedCommands = ArrayList<QueuedCommand>()
    private val pendingResults = HashMap<Long, MethodChannel.Result>()
    private val clients = LinkedHashSet<MethodChannel>()

    /** Dart 认证快照的最近一次投影缓存，供刚绑定的 UI 取回；这里不判定认证状态。 */
    @Volatile
    var latestState: Map<Any?, Any?>? = null
        private set

    private class QueuedCommand(
        val id: Long?,
        val name: String,
        val args: Map<String, Any?>?,
    )

    /** 绑定后台 FlutterEngine，并开始接收运行时发布的状态。 */
    fun attachEngine(flutterEngine: FlutterEngine) {
        runtimeReady = false
        runtimeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HOST_CHANNEL)
            .also { it.setMethodCallHandler(::handleRuntimeCall) }
    }

    /**
     * 释放后台 engine。运行时销毁后不再接受命令。
     *
     * [latestState] 保留最后一次发布的状态：服务重建时新绑定的 UI 应先看到它，
     * 而不是空白。关闭“保留后台运行”时 `stop` 已把状态发布为 `stopped`。
     */
    fun detachEngine() {
        runtimeChannel = null
        runtimeReady = false
        queuedCommands.clear()
        failPendingResults()
    }

    /** 注册一个可见 UI 的通道，并立即补发最新状态。 */
    fun registerClient(channel: MethodChannel) {
        clients.add(channel)
        latestState?.let { pushToClient(channel, it) }
    }

    fun unregisterClient(channel: MethodChannel) {
        clients.remove(channel)
    }

    /**
     * 下发一条运行时命令。
     *
     * 运行时尚未注册命令处理器时命令会被排队，就绪后按顺序补发，因此
     * 启动时机不需要和 Dart 入口的启动时序竞争。
     */
    fun dispatch(name: String, args: Map<String, Any?>? = null, result: MethodChannel.Result? = null) {
        val requestId: Long? = if (result == null) null else nextRequestId++
        if (requestId != null && result != null) {
            pendingResults[requestId] = result
        }
        send(QueuedCommand(requestId, name, args))
    }

    private fun send(command: QueuedCommand) {
        val channel = runtimeChannel
        if (!runtimeReady || channel == null) {
            queuedCommands.add(command)
            return
        }
        channel.invokeMethod(METHOD_COMMAND, mapOf(KEY_NAME to command.name, KEY_ARGS to command.args),
            object : MethodChannel.Result {
                override fun success(value: Any?) {
                    complete(command.id, value)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    Log.w(TAG, "下发认证运行时命令失败: ${command.name}: $code $message")
                    fail(command.id, code, message)
                }

                override fun notImplemented() {
                    Log.w(TAG, "后台运行时未实现命令通道")
                    fail(command.id, "not_implemented", "后台运行时未实现命令通道")
                }
            })
    }

    private fun handleRuntimeCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_READY -> {
                runtimeReady = true
                result.success(null)
                flushQueuedCommands()
            }

            METHOD_STATE -> {
                val state = call.arguments as? Map<Any?, Any?>
                if (state == null) {
                    result.error("invalid_state", "认证运行时发布的状态无效", null)
                    return
                }
                publishState(state)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun publishState(state: Map<Any?, Any?>) {
        latestState = state
        onState?.invoke(state)
        clients.toList().forEach { pushToClient(it, state) }
    }

    private fun pushToClient(channel: MethodChannel, state: Map<Any?, Any?>) {
        try {
            channel.invokeMethod(METHOD_ON_STATE, state)
        } catch (error: Exception) {
            Log.w(TAG, "转发认证状态失败", error)
        }
    }

    private fun flushQueuedCommands() {
        if (queuedCommands.isEmpty()) return
        val pending = queuedCommands.toList()
        queuedCommands.clear()
        pending.forEach { send(it) }
    }

    private fun complete(id: Long?, value: Any?) {
        if (id == null) return
        pendingResults.remove(id)?.success(value)
    }

    private fun fail(id: Long?, code: String, message: String?) {
        if (id == null) return
        pendingResults.remove(id)?.error(code, message, null)
    }

    private fun failPendingResults() {
        val pending = pendingResults.values.toList()
        pendingResults.clear()
        pending.forEach { it.error("runtime_gone", "认证运行时已释放", null) }
    }
}
