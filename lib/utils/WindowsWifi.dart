import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';

class WindowsWifiSnapshot {
  const WindowsWifiSnapshot({
    required this.connected,
    required this.address,
    required this.adapter,
    required this.revision,
    this.name = '',
  });

  factory WindowsWifiSnapshot.fromMap(Map<Object?, Object?> value) {
    final address = value['address'];
    final adapter = value['adapter'];
    final revision = value['revision'];
    final name = value['name'];
    return WindowsWifiSnapshot(
      connected:
          value['connected'] == true && address is String && address.isNotEmpty,
      address: address is String ? address : '',
      adapter: adapter is String ? adapter : '',
      revision: revision is int ? revision : 0,
      name: name is String ? name : '',
    );
  }

  final bool connected;
  final String address;
  final String adapter;
  final int revision;
  final String name;
}

abstract class WindowsWifiEvents {
  Future<WindowsWifiSnapshot> start(
    void Function(WindowsWifiSnapshot snapshot) onChanged,
  );

  Future<void> dispose();
}

class WindowsWifiChannel implements WindowsWifiEvents {
  WindowsWifiChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.mel0ny.linkup/windowsWifi';
  static const snapshotMethod = 'getSnapshot';
  static const changedMethod = 'onChanged';
  static const tunnelMethod = 'openTunnel';
  final MethodChannel _channel;

  @override
  Future<WindowsWifiSnapshot> start(
    void Function(WindowsWifiSnapshot snapshot) onChanged,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == changedMethod && call.arguments is Map) {
        onChanged(
          WindowsWifiSnapshot.fromMap(
            Map<Object?, Object?>.from(call.arguments as Map),
          ),
        );
      }
    });
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      snapshotMethod,
    );
    return WindowsWifiSnapshot.fromMap(raw ?? const {});
  }

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
  }

  Future<ConnectionTask<Socket>> connect(Uri uri) async {
    final tunnel = await _channel.invokeMethod<Map<Object?, Object?>>(
      tunnelMethod,
      {'host': uri.host, 'port': uri.port},
    );
    final port = tunnel?['port'];
    final token = tunnel?['token'];
    if (port is! int || token is! String || token.length != 32) {
      throw const SocketException('Wi-Fi 连接不可用');
    }
    final connection = await Socket.startConnect(
      InternetAddress.loopbackIPv4,
      port,
    );
    return ConnectionTask.fromSocket(
      connection.socket.then((socket) {
        socket.add(utf8.encode(token));
        return socket;
      }),
      connection.cancel,
    );
  }
}

class WindowsWifiNetworkState implements AuthenticationNetworkState {
  int _generation = 0;
  int _revision = -1;
  bool _connected = false;
  String? _address;
  String? _name;

  String? get sourceAddress => _address;
  String? get name => _name;
  bool get connected => _connected;

  bool apply(WindowsWifiSnapshot snapshot) {
    if (snapshot.revision <= _revision) return false;
    _revision = snapshot.revision;
    _connected = snapshot.connected;
    _address = snapshot.connected ? snapshot.address : null;
    _name = snapshot.connected && snapshot.name.trim().isNotEmpty
        ? snapshot.name.trim()
        : null;
    return true;
  }

  @override
  String get generation => 'network-$_generation';

  @override
  Future<bool> isConnected() async => _connected;

  @override
  void invalidate() => _generation++;
}

http.Client createWindowsWifiHttpClient(WindowsWifiChannel channel) {
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) =>
      channel.connect(uri);
  return IOClient(client);
}
