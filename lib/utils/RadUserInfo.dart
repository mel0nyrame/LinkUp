import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';

part 'RadUserInfo.g.dart';

@JsonSerializable()
class RadUserInfo {
  @JsonKey(name: 'ServerFlag')
  final int serverFlag;

  @JsonKey(name: 'add_time')
  final int addTime;

  @JsonKey(name: 'all_bytes')
  final int allBytes;

  @JsonKey(name: 'billing_name')
  final String billingName;

  @JsonKey(name: 'bytes_in')
  final int bytesIn;

  @JsonKey(name: 'bytes_out')
  final int bytesOut;

  @JsonKey(name: 'checkout_date')
  final int checkoutDate;

  @JsonKey(name: 'domain')
  final String domain;

  @JsonKey(name: 'error')
  final String error;

  @JsonKey(name: 'group_id')
  final String groupId;

  @JsonKey(name: 'keepalive_time')
  final int keepaliveTime;

  @JsonKey(name: 'online_device_detail')
  final String onlineDeviceDetailRaw;

  @JsonKey(name: 'online_device_total')
  final String onlineDeviceTotal;

  @JsonKey(name: 'online_ip')
  final String onlineIp;

  @JsonKey(name: 'online_ip6')
  final String onlineIp6;

  @JsonKey(name: 'package_id')
  final String packageId;

  @JsonKey(name: 'pppoe_dial')
  final String pppoeDial;

  @JsonKey(name: 'products_id')
  final String productsId;

  @JsonKey(name: 'products_name')
  final String productsName;

  @JsonKey(name: 'real_name')
  final String realName;

  @JsonKey(name: 'remain_bytes')
  final int remainBytes;

  @JsonKey(name: 'remain_seconds')
  final int remainSeconds;

  @JsonKey(name: 'sum_bytes')
  final int sumBytes;

  @JsonKey(name: 'sum_seconds')
  final int sumSeconds;

  @JsonKey(name: 'sysver')
  final String sysver;

  @JsonKey(name: 'user_balance')
  final int userBalance;

  @JsonKey(name: 'user_charge')
  final int userCharge;

  @JsonKey(name: 'user_mac')
  final String userMac;

  @JsonKey(name: 'user_name')
  final String userName;

  @JsonKey(name: 'wallet_balance')
  final int walletBalance;

  RadUserInfo({
    required this.serverFlag,
    required this.addTime,
    required this.allBytes,
    required this.billingName,
    required this.bytesIn,
    required this.bytesOut,
    required this.checkoutDate,
    required this.domain,
    required this.error,
    required this.groupId,
    required this.keepaliveTime,
    required this.onlineDeviceDetailRaw,
    required this.onlineDeviceTotal,
    required this.onlineIp,
    required this.onlineIp6,
    required this.packageId,
    required this.pppoeDial,
    required this.productsId,
    required this.productsName,
    required this.realName,
    required this.remainBytes,
    required this.remainSeconds,
    required this.sumBytes,
    required this.sumSeconds,
    required this.sysver,
    required this.userBalance,
    required this.userCharge,
    required this.userMac,
    required this.userName,
    required this.walletBalance,
  });

  // Getters
  int get getServerFlag => serverFlag;
  int get getAddTime => addTime;
  int get getAllBytes => allBytes;
  String get getBillingName => billingName;
  int get getBytesIn => bytesIn;
  int get getBytesOut => bytesOut;
  int get getCheckoutDate => checkoutDate;
  String get getDomain => domain;
  String get getError => error;
  String get getGroupId => groupId;
  int get getKeepaliveTime => keepaliveTime;
  String get getOnlineDeviceDetailRaw => onlineDeviceDetailRaw;
  String get getOnlineDeviceTotal => onlineDeviceTotal;
  String get getOnlineIp => onlineIp;
  String get getOnlineIp6 => onlineIp6;
  String get getPackageId => packageId;
  String get getPppoeDial => pppoeDial;
  String get getProductsId => productsId;
  String get getProductsName => productsName;
  String get getRealName => realName;
  int get getRemainBytes => remainBytes;
  int get getRemainSeconds => remainSeconds;
  int get getSumBytes => sumBytes;
  int get getSumSeconds => sumSeconds;
  String get getSysver => sysver;
  int get getUserBalance => userBalance;
  int get getUserCharge => userCharge;
  String get getUserMac => userMac;
  String get getUserName => userName;
  int get getWalletBalance => walletBalance;

  Map<String, OnlineDevice>? get onlineDeviceDetail {
    if (onlineDeviceDetailRaw.isEmpty) return null;
    try {
      final Map<String, dynamic> json = jsonDecode(onlineDeviceDetailRaw);
      return json.map((key, value) => 
        MapEntry(key, OnlineDevice.fromJson(value)));
    } catch (e) {
      return null;
    }
  }

  bool get isOnline => error == 'ok';
  double get remainBytesGB => remainBytes / (1024 * 1024 * 1024);
  double get sumBytesGB => sumBytes / (1024 * 1024 * 1024);

  factory RadUserInfo.fromJson(Map<String, dynamic> json) => 
      _$RadUserInfoFromJson(json);

  Map<String, dynamic> toJson() => _$RadUserInfoToJson(this);
}

@JsonSerializable()
class OnlineDevice {
  @JsonKey(name: 'class_name')
  final String className;

  @JsonKey(name: 'ip')
  final String ip;

  @JsonKey(name: 'ip6')
  final String ip6;

  @JsonKey(name: 'os_name')
  final String osName;

  @JsonKey(name: 'rad_online_id')
  final String radOnlineId;

  OnlineDevice({
    required this.className,
    required this.ip,
    required this.ip6,
    required this.osName,
    required this.radOnlineId,
  });

  String get getClassName => className;
  String get getIp => ip;
  String get getIp6 => ip6;
  String get getOsName => osName;
  String get getRadOnlineId => radOnlineId;

  factory OnlineDevice.fromJson(Map<String, dynamic> json) => 
      _$OnlineDeviceFromJson(json);

  Map<String, dynamic> toJson() => _$OnlineDeviceToJson(this);
}