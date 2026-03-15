import 'package:http/http.dart' as http;
import 'package:linkup/utils/SrucClient.dart';
import 'package:linkup/utils/SrucEncrypt.dart';

class Sruclogin {
  SrucClient client = SrucClient();

  Future<void> srunLogin() async {
    try {
      final info = await client.getUserInfo();
      String username = '';
      String password = '';
      String acid = '1';
      String ip = info.onlineIp;

      final challenge = await client.getChallenge(username: username, ip: ip);
      String token = challenge.challenge;

      srucPortalLogin(username, password, acid, token, ip);
    } catch (e) {
      print('Error fetching user info: $e');
    }
  }

  void srucPortalLogin(
    String username,
    String password,
    String acid,
    String token,
    String ip,
  ) {
    String hmd5Password = SrucEnrypt.Hmd5(password, token);

    SrunInfo infoObj = SrunInfo(
      username: username,
      password: password,
      ip: ip,
      acid: acid,
    );

    Object info = SrucEnrypt.getInfo(infoObj.toJson(), token);

    String chkStr = SrucEnrypt.Chkstr(
      token,
      username,
      hmd5Password,
      acid,
      ip,
      client.n,
      client.enc,
      info.toString(),
    );

    String chkSum = SrucEnrypt.Sha1(chkStr);

    String currentTime = DateTime.now().millisecondsSinceEpoch.toString();

    final params = {
      'action': 'login',
      'callback': client.callback,
      'username': username,
      'password': '{MD5}$hmd5Password',
      'os': 'Windows 10',
      'name': 'Windows',
      'double_stack': '0',
      'chksum': chkSum,
      'info': info,
      'ac_id': acid,
      'ip': ip,
      'n': client.n,
      'type': client.type,
      '_': currentTime,
    };

    final uri = Uri(
      scheme: 'http',
      host: client.urlPortal.replaceFirst('http://', '').split('/')[0],
      queryParameters: params,
    );

    Future<void> doRequest() async {
      var response = await http.get(
        uri,
        headers: {'User-Agent': client.userAgent},
      );
      if (response.statusCode == 200) {
        print(response.body);
      } else {
        print('请求失败: ${response.statusCode}');
      }
    }
  }
}
