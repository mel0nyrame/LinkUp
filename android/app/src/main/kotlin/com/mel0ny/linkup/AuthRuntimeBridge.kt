package com.mel0ny.linkup

import android.content.Context
import android.content.res.AssetManager
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import org.json.JSONObject

/**
 * 后台认证运行时与 Dart 之间的窄桥。
 *
 * 命令通过 embedder 的 callback dispatcher 下发，状态通过 MethodChannel 上行。
 * 这里不包含认证协议、状态机或退避规则；Srun 协议和协调器只有一份 Dart 实现。
 */
object AuthRuntimeBridge {
    private const val TAG = "LinkUpAuthRuntime"

    /** 后台 Dart isolate 使用的通道名，必须与 Dart 侧保持一致。 */
    const val HOST_CHANNEL = "com.mel0ny.linkup/authRuntime"

    /** 启动监控。必须与 Dart 侧 `AuthRuntimeController.commandStart` 一致。 */
    const val COMMAND_START = "start"

    /** 停止监控并释放协议资源。必须与 Dart 侧 `AuthRuntimeController.commandStop` 一致。 */
    const val COMMAND_STOP = "stop"

    /**
     * Wi-Fi 可用性变化。必须与 Dart 侧 `AuthRuntimeController.commandNetworkChanged`
     * 一致，负载只有 `connected` 布尔值。
     */
    const val COMMAND_NETWORK_CHANGED = "networkChanged"

    /** 状态消费者，由前台服务注册，用于刷新常驻通知。 */
    var onState: ((Map<Any?, Any?>) -> Unit)? = null

    private var engine: FlutterEngine? = null
    private var assets: AssetManager? = null
    private var commandHandle: Long? = null
    private var nextRequestId = 0L
    private val queuedCommands = ArrayList<QueuedCommand>()
    private val pendingResults = HashMap<Long, MethodChannel.Result>()
    private val clients = LinkedHashSet<MethodChannel>()

    /** 最近一次由后台运行时发布的状态，供刚绑定的 UI 取回。 */
    @Volatile
    var latestState: Map<Any?, Any?>? = null
        private set

    private class QueuedCommand(
        val id: Long?,
        val name: String,
        val args: Map<String, Any?>?,
    )

    /** 绑定后台 FlutterEngine，并开始接收运行时发布的状态。 */
    fun attachEngine(context: Context, flutterEngine: FlutterEngine) {
        engine = flutterEngine
        assets = context.applicationContext.assets
        commandHandle = null
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HOST_CHANNEL)
            .setMethodCallHandler(::handleRuntimeCall)
    }

    /**
     * 释放后台 engine。运行时销毁后不再接受命令。
     *
     * [latestState] 保留最后一次发布的状态：服务重建时新绑定的 UI 应先看到它，
     * 而不是空白。关闭“保留后台运行”时 `stop` 已把状态发布为 `stopped`。
     */
    fun detachEngine() {
        engine = null
        assets = null
        commandHandle = null
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
     * 运行时尚未发布回调句柄时命令会被排队，句柄就绪后按顺序补发，因此
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
        val handle = commandHandle
        val target = engine
        if (handle == null || target == null) {
            queuedCommands.add(command)
            return
        }
        invokeDispatcher(target, handle, command)
    }

    private fun invokeDispatcher(target: FlutterEngine, handle: Long, command: QueuedCommand) {
        val information = FlutterCallbackInformation.lookupCallbackInformation(handle)
        if (information == null) {
            Log.w(TAG, "无法解析认证运行时回调句柄")
            complete(command.id, null)
            return
        }

        val assetManager = assets
        if (assetManager == null) {
            complete(command.id, null)
            return
        }

        val arguments = mutableListOf<String?>()
        arguments.add(command.name)
        val payload = encodeArguments(command)
        if (payload != null) arguments.add(payload)

        try {
            target.dartExecutor.executeDartCallback(
                DartExecutor.DartCallback(
                    assetManager,
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    information,
                )
            )
        } catch (error: Exception) {
            Log.w(TAG, "下发认证运行时命令失败: ${command.name}", error)
            complete(command.id, null)
        }
    }

    /**
     * 把命令参数编码成 JSON。
     *
     * 需要返回值的命令会附带请求标识，Dart 侧执行后用同一个标识回传结果。
     */
    private fun encodeArguments(command: QueuedCommand): String? {
        val payload = JSONObject()
        command.args?.forEach { (key, value) -> if (value != null) payload.put(key, value) }
        val id = command.id
        if (id != null) payload.put("id", id)
        return if (payload.length() == 0) null else payload.toString()
    }

    private fun handleRuntimeCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                val handle = (call.argument<Number>("commandHandle"))?.toLong()
                if (handle == null) {
                    result.error("invalid_handle", "认证运行时未提供回调句柄", null)
                    return
                }
                commandHandle = handle
                result.success(null)
                flushQueuedCommands()
            }

            "state" -> {
                val state = call.arguments as? Map<Any?, Any?>
                if (state == null) {
                    result.error("invalid_state", "认证运行时发布的状态无效", null)
                    return
                }
                publishState(state)
                result.success(null)
            }

            "commandResult" -> {
                val id = (call.argument<Number>("id"))?.toLong()
                if (id == null) {
                    result.error("invalid_request", "认证运行时返回了无效的请求标识", null)
                    return
                }
                complete(id, call.argument("value"))
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
            channel.invokeMethod("onState", state)
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

    private fun failPendingResults() {
        val pending = pendingResults.values.toList()
        pendingResults.clear()
        pending.forEach { it.error("runtime_gone", "认证运行时已释放", null) }
    }
}
