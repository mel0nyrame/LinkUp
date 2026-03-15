class ChallengeResponse {
  final String challenge;
  final String clientIp;
  final int ecode;
  final String error;
  final String errorMsg;
  final String expire;
  final String onlineIp;
  final String res;
  final String srunVer;
  final int st;

  ChallengeResponse({
    required this.challenge,
    required this.clientIp,
    required this.ecode,
    required this.error,
    required this.errorMsg,
    required this.expire,
    required this.onlineIp,
    required this.res,
    required this.srunVer,
    required this.st,
  });

  bool get isSuccess => error == 'ok' && ecode == 0;
  
  // Token 是否过期（根据 expire 时间判断）
  bool get isExpired => false; // 实际需结合本地时间计算

  factory ChallengeResponse.fromJson(Map<String, dynamic> json) {
    return ChallengeResponse(
      challenge: json['challenge'] as String? ?? '',
      clientIp: json['client_ip'] as String? ?? '',
      ecode: json['ecode'] as int? ?? -1,
      error: json['error'] as String? ?? '',
      errorMsg: json['error_msg'] as String? ?? '',
      expire: json['expire'] as String? ?? '60',
      onlineIp: json['online_ip'] as String? ?? '',
      res: json['res'] as String? ?? '',
      srunVer: json['srun_ver'] as String? ?? '',
      st: json['st'] as int? ?? 0,
    );
  }
}
