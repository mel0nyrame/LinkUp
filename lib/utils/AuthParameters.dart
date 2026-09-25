/// 本轮认证使用的唯一不可变参数快照。
///
/// 密码不放入此对象，避免认证状态或诊断信息意外携带凭据。
class AuthParameters {
  const AuthParameters({
    required this.server,
    required this.username,
    required this.ip,
    required this.acid,
    String enc = supportedEnc,
    this.n = '200',
    this.type = '1',
    this.callback = 'jQueryCallback',
  }) : enc = enc == supportedEnc ? enc : supportedEnc;

  static const String supportedEnc = 'srun_bx1';

  final String server;
  final String username;
  final String ip;
  final String acid;
  final String enc;
  final String n;
  final String type;
  final String callback;

  String get authServer => server;

  String get protocolPrefix => '{SRBX1}';
}
