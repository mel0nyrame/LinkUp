package com.mel0ny.linkup

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log

/**
 * 把 Android 的 Wi-Fi 连接事件转成认证运行时的网络变化命令。
 *
 * 这里只上报“Wi-Fi 是否可用”，不解析 Portal、不构造认证参数：Reality、候选解析
 * 和登录仍然只有协调器一份实现，平台回调只负责叫醒它的单飞入口。
 *
 * 用传输类型的网络请求而不是默认网络回调：校园网未认证时不会成为系统默认网络，
 * 而“已关联但尚未认证”正是需要立即发起检查的时刻。
 */
class AuthRuntimeNetworkMonitor(
    context: Context,
    private val onChanged: (connected: Boolean) -> Unit,
) {
    private val connectivityManager =
        context.applicationContext.getSystemService(ConnectivityManager::class.java)
    private val networks = mutableSetOf<Network>()
    private var reported: Boolean? = null
    private var registered = false

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            networks.add(network)
            report(true)
        }

        override fun onLost(network: Network) {
            networks.remove(network)
            report(networks.isNotEmpty())
        }
    }

    fun start() {
        if (registered) return
        val manager = connectivityManager ?: return
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        try {
            manager.registerNetworkCallback(request, callback)
            registered = true
        } catch (error: SecurityException) {
            // 注册不上时不让服务崩溃：只跟踪 Wi-Fi 的网络事件会缺失，认证退回
            // 开机后那一次检查，之后依赖用户重新打开应用。
            Log.w(TAG, "注册 Wi-Fi 网络回调失败，认证只会退回周期检查", error)
        }
    }

    fun stop() {
        if (!registered) return
        registered = false
        networks.clear()
        reported = null
        try {
            connectivityManager?.unregisterNetworkCallback(callback)
        } catch (error: IllegalArgumentException) {
            Log.w(TAG, "取消 Wi-Fi 网络回调失败", error)
        }
    }

    /** 重复事件只在可用性发生变化时下发，避免反复叫醒协调器。 */
    private fun report(connected: Boolean) {
        if (reported == connected) return
        reported = connected
        onChanged(connected)
    }

    private companion object {
        const val TAG = "LinkUpAuthRuntime"
    }
}
