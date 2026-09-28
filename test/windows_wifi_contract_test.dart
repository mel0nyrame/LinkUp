import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/utils/WindowsWifi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows 原生事件、接口选择和 TCP 出口接线', () {
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final tunnel = File('windows/runner/wifi_tunnel.cpp').readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(window, contains(WindowsWifiChannel.channelName));
    expect(window, contains('"${WindowsWifiChannel.snapshotMethod}"'));
    expect(window, contains('"${WindowsWifiChannel.changedMethod}"'));
    expect(window, contains('"${WindowsWifiChannel.tunnelMethod}"'));
    expect(window, contains('WlanRegisterNotification'));
    expect(window, contains('NotifyUnicastIpAddressChange'));
    expect(window, contains('wlan_notification_acm_connection_complete'));
    expect(window, contains('wlan_notification_acm_disconnected'));
    expect(window, contains('++association_epoch_'));
    expect(window, contains('WlanEnumInterfaces'));
    expect(window, contains('ConvertInterfaceGuidToLuid'));
    expect(window, contains('adapter->IfIndex'));
    expect(window, contains('CancelMibChangeNotify2'));
    expect(window, contains('WlanCloseHandle'));
    expect(tunnel, contains('IP_UNICAST_IF'));
    expect(tunnel, contains('DnsQueryEx'));
    expect(tunnel, contains('request.InterfaceIndex = interface_index'));
    expect(tunnel, contains('DNS_QUERY_BYPASS_CACHE'));
    expect(tunnel, contains('htonl(record->Data.A.IpAddress)'));
    expect(tunnel, contains('bind(remote,'));
    expect(tunnel, contains('INADDR_LOOPBACK'));
    expect(tunnel, contains('SO_EXCLUSIVEADDRUSE'));
    expect(tunnel, contains('BCryptGenRandom'));
    expect(tunnel, contains('ReadToken(local, token)'));
    expect(cmake, contains('"wifi_tunnel.cpp"'));
    expect(cmake, contains('"wlanapi.lib"'));
    expect(cmake, contains('"iphlpapi.lib"'));
    expect(cmake, contains('"ws2_32.lib"'));
    expect(cmake, contains('"bcrypt.lib"'));
    expect(cmake, contains('"dnsapi.lib"'));
  });

  test('Windows Wi-Fi 通道读取快照并接收变化', () async {
    const channel = MethodChannel('testWindowsWifiSnapshot');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getSnapshot');
      return <String, Object?>{
        'connected': false,
        'address': '',
        'adapter': '',
        'revision': 1,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final events = WindowsWifiChannel(channel: channel);
    addTearDown(events.dispose);
    final received = <WindowsWifiSnapshot>[];

    final initial = await events.start(received.add);
    expect(initial.connected, isFalse);
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onChanged', <String, Object?>{
          'connected': true,
          'address': '192.0.2.10',
          'adapter': 'wifi-a',
          'revision': 2,
        }),
      ),
      (_) {},
    );

    expect(received, hasLength(1));
    expect(received.single.connected, isTrue);
    expect(received.single.address, '192.0.2.10');
    expect(received.single.revision, 2);
  });

  test('认证 HTTP 连接经平台隧道发出而不直接连接目标', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    const channel = MethodChannel('testWindowsWifiTunnel');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final targets = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openTunnel');
      targets.add(Map<Object?, Object?>.from(call.arguments as Map));
      return <String, Object?>{
        'port': server.port,
        'token': '0123456789abcdef0123456789abcdef',
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final listener = server.listen((socket) {
      final request = StringBuffer();
      socket.listen((bytes) {
        request.write(utf8.decode(bytes));
        if (request.toString().startsWith('0123456789abcdef0123456789abcdef') &&
            request.toString().contains('\r\n\r\n')) {
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n'
            'Connection: close\r\n\r\nok',
          );
          socket.close();
        }
      });
    });
    addTearDown(listener.cancel);
    final client = createWindowsWifiHttpClient(
      WindowsWifiChannel(channel: channel),
    );
    addTearDown(client.close);

    final response = await client.get(Uri.parse('http://192.0.2.1/check'));

    expect(response.statusCode, 200);
    expect(response.body, 'ok');
    expect(targets, <Map<Object?, Object?>>[
      <Object?, Object?>{'host': '192.0.2.1', 'port': 80},
    ]);
  });
}
