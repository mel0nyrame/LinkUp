import 'package:flutter_test/flutter_test.dart';

import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/ChallengeResponse.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunLogin.dart';

final _config = AuthConfig(
  username: '2021000100000',
  password: 'p',
  acid: 'a',
  autoAcid: true,
  authServer: '10.0.0.1',
  userType: '',
);

/// 构造一份在线设备表。
///
/// 键是 `rad_online_id`，刻意编成和 IP 无关的形式，这样用键去比对目标地址的实现
/// 会当场失败，而不是因为夹具刚好吻合而通过。
String _deviceList(List<String> ips) {
  final entries = <String, String>{};
  for (var i = 0; i < ips.length; i++) {
    entries['online$i'] =
        '{"class_name":"","ip":"${ips[i]}","ip6":"","os_name":"","rad_online_id":"online$i"}';
  }
  return '{${entries.entries.map((e) => '"${e.key}":${e.value}').join(',')}}';
}

/// 可编排的协议替身：DM 结果与每次复查返回的在线设备表都由测试决定。
class _ScriptedProtocol implements AuthenticationProtocol {
  _ScriptedProtocol({
    required this.dmAccepted,
    required this.deviceLists,
    this.dmErrorMessage,
  });

  /// `rad_user_dm` 是否被受理。
  bool dmAccepted;

  /// DM 被拒时服务器给出的原因，透传给 UI。
  final String? dmErrorMessage;

  /// 依次返回的在线设备表；用完则重复最后一份。
  final List<String> deviceLists;

  final List<String> loggedOutIps = <String>[];
  int userInfoCalls = 0;

  @override
  Future<DmResult> logout({
    required String server,
    required String username,
    required String ip,
  }) async {
    loggedOutIps.add(ip);
    return DmResult(accepted: dmAccepted, errorMessage: dmErrorMessage);
  }

  @override
  Future<RadUserInfo> getUserInfo(String server) async {
    final index = userInfoCalls < deviceLists.length
        ? userInfoCalls
        : deviceLists.length - 1;
    userInfoCalls++;
    return RadUserInfo(
      clientIp: '10.0.0.8',
      onlineIp: '10.0.0.8',
      error: 'ok',
      onlineDeviceTotal: '2',
      onlineDeviceDetailRaw: deviceLists[index],
    );
  }

  @override
  Future<RealityProbeResult> reality(
    String server, {
    bool getAcid = true,
  }) async => const RealityProbeResult(acid: '143');

  @override
  Future<ChallengeResponse> getChallenge({
    required String server,
    required String username,
    required String ip,
  }) async => throw UnimplementedError();

  @override
  Future<LoginResult> login({
    required String server,
    required AuthParameters parameters,
    required String password,
    required String challenge,
  }) async => throw UnimplementedError();

  @override
  Future<String?> detectAcid(String server) async => null;

  @override
  void reset() {}

  @override
  void dispose() {}
}

SrunAuthenticationAttempt _attempt(_ScriptedProtocol protocol) =>
    SrunAuthenticationAttempt(
      protocol: protocol,
      confirmInterval: Duration.zero,
    );

void main() {
  test('目标从在线设备表消失后确认已踢掉', () async {
    final protocol = _ScriptedProtocol(
      dmAccepted: true,
      deviceLists: [
        _deviceList(<String>['10.0.0.8', '10.0.0.9']),
        _deviceList(<String>['10.0.0.8']),
      ],
    );

    final result = await _attempt(protocol).kickDevice(_config, '10.0.0.9');

    expect(result.outcome, DmOutcome.kicked);
    expect(protocol.loggedOutIps, <String>['10.0.0.9']);
    // 第一次复查仍看到目标，所以要重试到第二次才给出确认。
    expect(protocol.userInfoCalls, 2);
  });

  test('目标仍留在在线设备表时报已受理但未确认', () async {
    final protocol = _ScriptedProtocol(
      dmAccepted: true,
      deviceLists: [
        _deviceList(<String>['10.0.0.8', '10.0.0.9']),
      ],
    );

    final result = await _attempt(protocol).kickDevice(_config, '10.0.0.9');

    expect(result.outcome, DmOutcome.accepted);
    // 重试用尽后仍无判据，不该无限复查。
    expect(protocol.userInfoCalls, 3);
  });

  test('服务器拒绝下线请求时报被拒绝且不发起复查', () async {
    final protocol = _ScriptedProtocol(
      dmAccepted: false,
      deviceLists: [
        _deviceList(<String>['10.0.0.8']),
      ],
    );

    final result = await _attempt(protocol).kickDevice(_config, '10.0.0.9');

    expect(result.outcome, DmOutcome.rejected);
    expect(protocol.userInfoCalls, 0);
  });

  test('被拒绝时把服务器给出的原因带到结果里', () async {
    final protocol = _ScriptedProtocol(
      dmAccepted: false,
      deviceLists: [
        _deviceList(<String>['10.0.0.8']),
      ],
      dmErrorMessage: 'E6502: 该 IP 不在在线设备表中',
    );

    final result = await _attempt(protocol).kickDevice(_config, '10.0.0.9');

    expect(result.outcome, DmOutcome.rejected);
    expect(result.reason, 'E6502: 该 IP 不在在线设备表中');
  });

  test('目标 IP 为空白时报被拒绝且不发出请求', () async {
    final protocol = _ScriptedProtocol(
      dmAccepted: true,
      deviceLists: [
        _deviceList(<String>['10.0.0.8']),
      ],
    );

    final result = await _attempt(protocol).kickDevice(_config, '   ');

    expect(result.outcome, DmOutcome.rejected);
    expect(protocol.loggedOutIps, isEmpty);
  });

  test('复查拿不到在线设备表时报已受理但未确认', () async {
    final protocol = _ScriptedProtocol(dmAccepted: true, deviceLists: ['']);

    final result = await _attempt(protocol).kickDevice(_config, '10.0.0.9');

    expect(result.outcome, DmOutcome.accepted);
  });

  test('目标只出现在记录的 ip6 字段时同样算仍在线', () async {
    final protocol = _ScriptedProtocol(
      dmAccepted: true,
      deviceLists: [
        // IPv6-only 的设备：ip 为空、ip6 命中目标，仍应判定为未确认。
        '{"online0":{"class_name":"","ip":"","ip6":"2001:db8::9",'
            '"os_name":"","rad_online_id":"online0"}}',
      ],
    );

    final result = await _attempt(protocol).kickDevice(_config, '2001:db8::9');

    expect(result.outcome, DmOutcome.accepted);
  });
}
