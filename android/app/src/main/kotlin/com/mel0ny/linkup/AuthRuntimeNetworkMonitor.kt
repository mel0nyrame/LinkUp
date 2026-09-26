package com.mel0ny.linkup

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * 把 Android 的 Wi-Fi 连接事件转成认证运行时的网络变化命令。
 *
 * 平台回调绑定 Wi-Fi 路由并上报可用性，不解析 Portal、不构造认证参数：
 * Reality、候选解析和登录仍然只有协调器一份实现。
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
    private val mainHandler = Handler(Looper.getMainLooper())
    private val networks = mutableSetOf<Network>()
    private var selectedNetwork: Network? = null
    private var reported: Boolean? = null
    private var reportedNetwork: Network? = null
    private var registered = false

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            mainHandler.post {
                if (!registered) return@post
                if (!networks.add(network)) return@post
                selectedNetwork = network
                bind(network)
                report(true)
            }
        }

        override fun onLost(network: Network) {
            mainHandler.post {
                if (!registered) return@post
                if (!networks.remove(network)) return@post
                if (selectedNetwork == network) {
                    selectedNetwork = networks.firstOrNull()
                    bind(selectedNetwork)
                }
                report(networks.isNotEmpty())
            }
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
            // 注册失败后不会收到恢复事件，用户重新打开应用时仍可主动检查。
            Log.w(TAG, "注册 Wi-Fi 网络回调失败，无法自动感知网络恢复", error)
        }
    }

    fun stop() {
        if (!registered) return
        registered = false
        mainHandler.removeCallbacksAndMessages(null)
        bind(null)
        networks.clear()
        selectedNetwork = null
        reported = null
        reportedNetwork = null
        try {
            connectivityManager?.unregisterNetworkCallback(callback)
        } catch (error: IllegalArgumentException) {
            Log.w(TAG, "取消 Wi-Fi 网络回调失败", error)
        }
    }

    /** 校园网未认证时可能不是默认网络，认证请求必须走实际连接的 Wi-Fi。 */
    private fun bind(network: Network?) {
        val manager = connectivityManager ?: return
        try {
            if (manager.bindProcessToNetwork(network)) {
                Log.i(
                    TAG,
                    if (network == null) "认证流量恢复系统默认网络" else "认证流量已绑定 Wi-Fi 网络",
                )
            } else {
                Log.w(TAG, "绑定 Wi-Fi 网络失败，网络可能已经断开")
            }
        } catch (error: SecurityException) {
            Log.w(TAG, "绑定 Wi-Fi 网络失败，缺少网络权限", error)
        }
    }

    /** 可用性或所选 Wi-Fi 变化时下发事件，使协调器关闭旧网络的连接。 */
    private fun report(connected: Boolean) {
        if (reported == connected && reportedNetwork == selectedNetwork) return
        val networkChanged = reportedNetwork != selectedNetwork
        reported = connected
        reportedNetwork = selectedNetwork
        Log.i(TAG, "Wi-Fi 可用性: $connected，所选网络变化: $networkChanged")
        onChanged(connected)
    }

    private companion object {
        const val TAG = "LinkUpAuthRuntime"
    }
}
