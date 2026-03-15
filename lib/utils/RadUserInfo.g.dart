// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'RadUserInfo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RadUserInfo _$RadUserInfoFromJson(Map<String, dynamic> json) => RadUserInfo(
  serverFlag: (json['ServerFlag'] as num).toInt(),
  addTime: (json['add_time'] as num).toInt(),
  allBytes: (json['all_bytes'] as num).toInt(),
  billingName: json['billing_name'] as String,
  bytesIn: (json['bytes_in'] as num).toInt(),
  bytesOut: (json['bytes_out'] as num).toInt(),
  checkoutDate: (json['checkout_date'] as num).toInt(),
  domain: json['domain'] as String,
  error: json['error'] as String,
  groupId: json['group_id'] as String,
  keepaliveTime: (json['keepalive_time'] as num).toInt(),
  onlineDeviceDetailRaw: json['online_device_detail'] as String,
  onlineDeviceTotal: json['online_device_total'] as String,
  onlineIp: json['online_ip'] as String,
  onlineIp6: json['online_ip6'] as String,
  packageId: json['package_id'] as String,
  pppoeDial: json['pppoe_dial'] as String,
  productsId: json['products_id'] as String,
  productsName: json['products_name'] as String,
  realName: json['real_name'] as String,
  remainBytes: (json['remain_bytes'] as num).toInt(),
  remainSeconds: (json['remain_seconds'] as num).toInt(),
  sumBytes: (json['sum_bytes'] as num).toInt(),
  sumSeconds: (json['sum_seconds'] as num).toInt(),
  sysver: json['sysver'] as String,
  userBalance: (json['user_balance'] as num).toInt(),
  userCharge: (json['user_charge'] as num).toInt(),
  userMac: json['user_mac'] as String,
  userName: json['user_name'] as String,
  walletBalance: (json['wallet_balance'] as num).toInt(),
);

Map<String, dynamic> _$RadUserInfoToJson(RadUserInfo instance) =>
    <String, dynamic>{
      'ServerFlag': instance.serverFlag,
      'add_time': instance.addTime,
      'all_bytes': instance.allBytes,
      'billing_name': instance.billingName,
      'bytes_in': instance.bytesIn,
      'bytes_out': instance.bytesOut,
      'checkout_date': instance.checkoutDate,
      'domain': instance.domain,
      'error': instance.error,
      'group_id': instance.groupId,
      'keepalive_time': instance.keepaliveTime,
      'online_device_detail': instance.onlineDeviceDetailRaw,
      'online_device_total': instance.onlineDeviceTotal,
      'online_ip': instance.onlineIp,
      'online_ip6': instance.onlineIp6,
      'package_id': instance.packageId,
      'pppoe_dial': instance.pppoeDial,
      'products_id': instance.productsId,
      'products_name': instance.productsName,
      'real_name': instance.realName,
      'remain_bytes': instance.remainBytes,
      'remain_seconds': instance.remainSeconds,
      'sum_bytes': instance.sumBytes,
      'sum_seconds': instance.sumSeconds,
      'sysver': instance.sysver,
      'user_balance': instance.userBalance,
      'user_charge': instance.userCharge,
      'user_mac': instance.userMac,
      'user_name': instance.userName,
      'wallet_balance': instance.walletBalance,
    };

OnlineDevice _$OnlineDeviceFromJson(Map<String, dynamic> json) => OnlineDevice(
  className: json['class_name'] as String,
  ip: json['ip'] as String,
  ip6: json['ip6'] as String,
  osName: json['os_name'] as String,
  radOnlineId: json['rad_online_id'] as String,
);

Map<String, dynamic> _$OnlineDeviceToJson(OnlineDevice instance) =>
    <String, dynamic>{
      'class_name': instance.className,
      'ip': instance.ip,
      'ip6': instance.ip6,
      'os_name': instance.osName,
      'rad_online_id': instance.radOnlineId,
    };
