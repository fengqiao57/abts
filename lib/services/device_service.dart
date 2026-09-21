import 'dart:io';

import 'package:flutter/services.dart';

/// 设备系统能力（走 MainActivity 原生通道）：
/// 电池优化忽略（后台留存保护）
class DeviceService {
  DeviceService._();
  static final DeviceService instance = DeviceService._();

  static const _channel = MethodChannel('abts/battery');

  bool get _isAndroid => Platform.isAndroid;

  /// 是否已豁免电池优化
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoring') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳转系统设置请求豁免
  Future<void> requestIgnoreBatteryOptimization() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestIgnore');
    } catch (_) {}
  }
}