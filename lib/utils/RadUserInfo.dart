import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';

part 'RadUserInfo.g.dart';

@JsonSerializable()
class RadUserInfo {
  @JsonKey(name: 'ServerFlag', defaultValue: 0)
  final int? serverFlag;

  @JsonKey(name: 'add_time', defaultValue: 0)
  final int? addTime;

  @JsonKey(name: 'all_bytes', defaultValue: 0)
  final int? allBytes;

  @JsonKey(name: 'billing_name', defaultValue: '')
  final String? billingName;

  @JsonKey(name: 'bytes_in', defaultValue: 0)
  final int? bytesIn;

  @JsonKey(name: 'bytes_out', defaultValue: 0)
  final int? bytesOut;

  @JsonKey(name: 'checkout_date', defaultValue: 0)
  final int? checkoutDate;

  @JsonKey(name: 'domain', defaultValue: '')
  final String? domain;

  @JsonKey(name: 'error', defaultValue: '')
  final String? error;

  @JsonKey(name: 'group_id', defaultValue: '')
  final String? groupId;

  @JsonKey(name: 'keepalive_time', defaultValue: 0)
  final int? keepaliveTime;

  @JsonKey(name: 'online_device_detail', defaultValue: '')
  final String? onlineDeviceDetailRaw;

  @JsonKey(name: 'online_device_total', defaultValue: '0')
  final String? onlineDeviceTotal;

  @JsonKey(name: 'online_ip', defaultValue: '')
  final String? onlineIp;

  @JsonKey(name: 'online_ip6', defaultValue: '')
  final String? onlineIp6;

  @JsonKey(name: 'package_id', defaultValue: '')
  final String? packageId;

  @JsonKey(name: 'pppoe_dial', defaultValue: '0')
  final String? pppoeDial;

  @JsonKey(name: 'products_id', defaultValue: '')
  final String? productsId;

  @JsonKey(name: 'products_name', defaultValue: '')
  final String? productsName;

  @JsonKey(name: 'real_name', defaultValue: '')
  final String? realName;

  @JsonKey(name: 'remain_bytes', defaultValue: 0)
  final int? remainBytes;

  @JsonKey(name: 'remain_seconds', defaultValue: 0)
  final int? remainSeconds;

  @JsonKey(name: 'sum_bytes', defaultValue: 0)
  final int? sumBytes;

  @JsonKey(name: 'sum_seconds', defaultValue: 0)
  final int? sumSeconds;

  @JsonKey(name: 'sysver', defaultValue: '')
  final String? sysver;

  @JsonKey(name: 'user_balance', defaultValue: 0)
  final int? userBalance;

  @JsonKey(name: 'user_charge', defaultValue: 0)
  final int? userCharge;

  @JsonKey(name: 'user_mac', defaultValue: '')
  final String? userMac;

  @JsonKey(name: 'user_name', defaultValue: '')
  final String? userName;

  @JsonKey(name: 'wallet_balance', defaultValue: 0)
  final int? walletBalance;

  RadUserInfo({
    this.serverFlag,
    this.addTime,
    this.allBytes,
    this.billingName,
    this.bytesIn,
    this.bytesOut,
    this.checkoutDate,
    this.domain,
    this.error,
    this.groupId,
    this.keepaliveTime,
    this.onlineDeviceDetailRaw,
    this.onlineDeviceTotal,
    this.onlineIp,
    this.onlineIp6,
    this.packageId,
    this.pppoeDial,
    this.productsId,
    this.productsName,
    this.realName,
    this.remainBytes,
    this.remainSeconds,
    this.sumBytes,
    this.sumSeconds,
    this.sysver,
    this.userBalance,
    this.userCharge,
    this.userMac,
    this.userName,
    this.walletBalance,
  });

  // Getters with null safety
  int get getServerFlag => serverFlag ?? 0;
  int get getAddTime => addTime ?? 0;
  int get getAllBytes => allBytes ?? 0;
  String get getBillingName => billingName ?? '';
  int get getBytesIn => bytesIn ?? 0;
  int get getBytesOut => bytesOut ?? 0;
  int get getCheckoutDate => checkoutDate ?? 0;
  String get getDomain => domain ?? '';
  String get getError => error ?? '';
  String get getGroupId => groupId ?? '';
  int get getKeepaliveTime => keepaliveTime ?? 0;
  String get getOnlineDeviceDetailRaw => onlineDeviceDetailRaw ?? '';
  String get getOnlineDeviceTotal => onlineDeviceTotal ?? '0';
  String get getOnlineIp => onlineIp ?? '';
  String get getOnlineIp6 => onlineIp6 ?? '';
  String get getPackageId => packageId ?? '';
  String get getPppoeDial => pppoeDial ?? '0';
  String get getProductsId => productsId ?? '';
  String get getProductsName => productsName ?? '';
  String get getRealName => realName ?? '';
  int get getRemainBytes => remainBytes ?? 0;
  int get getRemainSeconds => remainSeconds ?? 0;
  int get getSumBytes => sumBytes ?? 0;
  int get getSumSeconds => sumSeconds ?? 0;
  String get getSysver => sysver ?? '';
  int get getUserBalance => userBalance ?? 0;
  int get getUserCharge => userCharge ?? 0;
  String get getUserMac => userMac ?? '';
  String get getUserName => userName ?? '';
  int get getWalletBalance => walletBalance ?? 0;

  Map<String, OnlineDevice>? get onlineDeviceDetail {
    if (onlineDeviceDetailRaw == null || onlineDeviceDetailRaw!.isEmpty) return null;
    try {
      final Map<String, dynamic> json = jsonDecode(onlineDeviceDetailRaw!);
      return json.map((key, value) => 
        MapEntry(key, OnlineDevice.fromJson(value)));
    } catch (e) {
      return null;
    }
  }

  bool get isOnline => error == 'ok';
  double get remainBytesGB => (remainBytes ?? 0) / (1024 * 1024 * 1024);
  double get sumBytesGB => (sumBytes ?? 0) / (1024 * 1024 * 1024);

  factory RadUserInfo.fromJson(Map<String, dynamic> json) => 
      _$RadUserInfoFromJson(json);

  Map<String, dynamic> toJson() => _$RadUserInfoToJson(this);
}

@JsonSerializable()
class OnlineDevice {
  @JsonKey(name: 'class_name', defaultValue: '')
  final String? className;

  @JsonKey(name: 'ip', defaultValue: '')
  final String? ip;

  @JsonKey(name: 'ip6', defaultValue: '')
  final String? ip6;

  @JsonKey(name: 'os_name', defaultValue: '')
  final String? osName;

  @JsonKey(name: 'rad_online_id', defaultValue: '')
  final String? radOnlineId;

  OnlineDevice({
    this.className,
    this.ip,
    this.ip6,
    this.osName,
    this.radOnlineId,
  });

  String get getClassName => className ?? '';
  String get getIp => ip ?? '';
  String get getIp6 => ip6 ?? '';
  String get getOsName => osName ?? '';
  String get getRadOnlineId => radOnlineId ?? '';

  factory OnlineDevice.fromJson(Map<String, dynamic> json) => 
      _$OnlineDeviceFromJson(json);

  Map<String, dynamic> toJson() => _$OnlineDeviceToJson(this);
}
