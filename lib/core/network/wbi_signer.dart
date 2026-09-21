import 'dart:convert';

import 'package:crypto/crypto.dart';

/// B 站 Web 端 WBI 签名算法
/// 参考 bili-music / bbplayer / biu / PiliPlus 四份同源实现
class WbiSigner {
  WbiSigner._();

  static const List<int> _mixinKeyEncTab = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
    33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61,
    26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36,
    20, 34, 44, 52,
  ];

  static final RegExp _chrFilter = RegExp(r"[!'()*]");

  static String _getMixinKey(String orig) {
    final sb = StringBuffer();
    for (var i = 0; i < 32; i++) {
      sb.write(orig[_mixinKeyEncTab[i]]);
    }
    return sb.toString();
  }

  static String _extractKey(String url) {
    final name = url.substring(url.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 对参数集合进行 WBI 签名，返回带 w_rid / wts 的新参数集合（原地修改）
  static Map<String, dynamic> sign(
    Map<String, dynamic> params, {
    required String imgUrl,
    required String subUrl,
  }) {
    final imgKey = _extractKey(imgUrl);
    final subKey = _extractKey(subUrl);
    final mixinKey = _getMixinKey(imgKey + subKey);

    params['wts'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final sortedKeys = params.keys.toList()..sort();
    final buf = StringBuffer();
    for (final key in sortedKeys) {
      final value = params[key];
      if (value == null) continue;
      buf
        ..write(Uri.encodeQueryComponent(key))
        ..write('=')
        ..write(Uri.encodeQueryComponent(
          value.toString().replaceAll(_chrFilter, ''),
        ))
        ..write('&');
    }
    final query = buf.toString();
    final noTail = query.endsWith('&')
        ? query.substring(0, query.length - 1)
        : query;
    final wRid = md5.convert(utf8.encode('$noTail$mixinKey')).toString();
    params['w_rid'] = wRid;
    return params;
  }
}