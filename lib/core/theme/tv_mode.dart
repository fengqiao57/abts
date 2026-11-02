import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 电视端（Android TV / 电视盒子）判定与显示补偿。
///
/// 判定优先走原生探测（leanback 特性 + 无触摸屏，见 MainActivity 的
/// `abts/device` 通道），失败时回退到「方向键导航 + 大屏」启发式。
/// 电视常见 1920x1080 逻辑分辨率，UI 会显得偏小，因此统一加一次温和的
/// 字号放大；手机与平板不受影响。
class TvMode {
  TvMode._();

  static const _channel = MethodChannel('abts/device');

  static bool? _native;

  /// 原生探测是否电视端；启动引导时调用一次，异常静默回退启发式。
  static Future<void> detect() async {
    if (!Platform.isAndroid) {
      _native = false;
      return;
    }
    try {
      final r = await _channel
          .invokeMethod<bool>('isTv')
          .timeout(const Duration(seconds: 2));
      _native = r ?? false;
    } catch (_) {
      _native = false;
    }
  }

  /// 是否按电视端对待（遥控器操作 / 大屏布局）。
  static bool isTv(BuildContext context) {
    final native = _native;
    if (native != null) return native;
    // 原生结果未就绪时的兜底：Android 上报方向键导航且达到 TV 基准尺寸
    if (!Platform.isAndroid) return false;
    final mq = MediaQuery.of(context);
    return mq.navigationMode == NavigationMode.directional &&
        mq.size.shortestSide >= 540;
  }

  /// 是否采用「宽屏形态」：电视/平板（短边 ≥ 600dp），或手机横屏
  /// （宽 ≥ 640dp 且横向）。主框架据此把底部导航换成左侧栏，播放页/详情页
  /// 据此切左右分栏；与方向键导航模式共用同一口径（见 main.dart）。
  static bool useWideLayout(BuildContext context) {
    if (isTv(context)) return true;
    final size = MediaQuery.sizeOf(context);
    if (size.shortestSide >= 600) return true;
    return size.width > size.height && size.width >= 640;
  }

  /// 电视端字号补偿（非电视返回 null，不做任何干预）。
  static TextScaler? textScalerFor(BuildContext context) {
    if (!isTv(context)) return null;
    final mq = MediaQuery.of(context);
    final base = mq.textScaler.scale(1.0);
    final factor = mq.devicePixelRatio < 1.4 ? 1.3 : 1.15;
    return TextScaler.linear((base * factor).clamp(1.0, 2.0));
  }
}
