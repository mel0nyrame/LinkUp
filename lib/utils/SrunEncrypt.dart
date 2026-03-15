import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';

class SrunEnrypt {
  static const String _customAlpha = 
      'LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA';
  
  static const String _standardAlpha = 
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  static String Hmd5(String message, String key) {
    final hmac = Hmac(md5, latin1.encode(key));
    final digest = hmac.convert(latin1.encode(message));
    return hex.encode(digest.bytes);
  }

  static String Sha1(String message) {
    final bytes = latin1.encode(message);
    final digest = sha1.convert(bytes);
    return hex.encode(digest.bytes);
  }

  static String Chkstr(
    String token,
    String username,
    String hmd5,
    String acId,
    String ip,
    String n,
    String type,
    String info,
  ) {
    return token +
        username +
        token +
        hmd5 +
        token +
        acId +
        token +
        ip +
        token +
        n +
        token +
        type +
        token +
        info;
  }

  static String getInfo(Map<String, dynamic> info, String token) {
    final jsonStr = jsonEncode(info);
    final encrypted = _xxteaEncrypt(jsonStr, token);
    final base64Str = _customBase64Encode(encrypted);
    return '{SRBX1}$base64Str';
  }

  static Uint8List _xxteaEncrypt(String plaintext, String key) {
    if (plaintext.isEmpty) return Uint8List(0);

    final v = _strToLongs(plaintext, true);
    final k = _strToLongs(key, false);
    
    final keyArr = List<int>.filled(4, 0);
    for (int i = 0; i < k.length && i < 4; i++) {
      keyArr[i] = k[i];
    }
    while (keyArr.length < 4) {
      keyArr.add(0);
    }

    final n = v.length - 1;
    if (n < 1) return Uint8List(0);

    const int delta = 0x9E3779B9;
    int z = v[n];
    int y = v[0];
    int q = (6 + 52 ~/ (n + 1)).floor();
    int d = 0;
    int e = 0;

    while (q-- > 0) {
      d = (d + delta) & 0xFFFFFFFF;
      e = (d >>> 2) & 3;
      
      for (int p = 0; p < n; p++) {
        y = v[p + 1];
        int m = ((z >>> 5) ^ (y << 2)) & 0xFFFFFFFF;
        m = (m + ((y >>> 3) ^ (z << 4) ^ (d ^ y))) & 0xFFFFFFFF;
        m = (m + (keyArr[(p & 3) ^ e] ^ z)) & 0xFFFFFFFF;
        v[p] = (v[p] + m) & 0xFFFFFFFF;
        z = v[p];
      }
      
      y = v[0];
      int m = ((z >>> 5) ^ (y << 2)) & 0xFFFFFFFF;
      m = (m + ((y >>> 3) ^ (z << 4) ^ (d ^ y))) & 0xFFFFFFFF;
      m = (m + (keyArr[(n & 3) ^ e] ^ z)) & 0xFFFFFFFF;
      v[n] = (v[n] + m) & 0xFFFFFFFF;
      z = v[n];
    }

    return _longsToBytes(v, false);
  }

  static List<int> _strToLongs(String s, bool includeLength) {
    final List<int> result = [];
    final bytes = latin1.encode(s);
    
    for (int i = 0; i < bytes.length; i += 4) {
      int val = 0;
      for (int j = 0; j < 4 && i + j < bytes.length; j++) {
        val |= (bytes[i + j] << (j * 8));
      }
      result.add(val);
    }
    
    if (includeLength) {
      result.add(bytes.length);
    }
    
    return result;
  }

  static Uint8List _longsToBytes(List<int> longs, bool includeLength) {
    final List<int> bytes = [];
    int length = longs.length;
    
    for (int i = 0; i < length; i++) {
      final val = longs[i];
      bytes.add(val & 0xFF);
      bytes.add((val >>> 8) & 0xFF);
      bytes.add((val >>> 16) & 0xFF);
      bytes.add((val >>> 24) & 0xFF);
    }
    
    if (includeLength && longs.isNotEmpty) {
      final realLen = longs.last;
      if (realLen < bytes.length) {
        return Uint8List.fromList(bytes.sublist(0, realLen));
      }
    }
    
    return Uint8List.fromList(bytes);
  }

  static String _customBase64Encode(Uint8List bytes) {
    final standard = base64.encode(bytes);
    
    final map = <String, String>{};
    for (int i = 0; i < _standardAlpha.length; i++) {
      map[_standardAlpha[i]] = _customAlpha[i];
    }
    
    return standard.split('').map((c) => map[c] ?? c).join();
  }
}

class SrunInfo {
  final String username;
  final String password;
  final String ip;
  final String acid;
  final String encVer;

  SrunInfo({
    required this.username,
    required this.password,
    required this.ip,
    required this.acid,
    this.encVer = 'srun_bx1',
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'password': password,
    'ip': ip,
    'acid': acid,
    'enc_ver': encVer,
  };
}
