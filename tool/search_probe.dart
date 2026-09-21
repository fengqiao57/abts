import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

const home = 'https://www.bilibili.com';
const base = 'https://api.bilibili.com';
const ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

const tab = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
  33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61,
  26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36,
  20, 34, 44, 52,
];

final re = RegExp(r"[!'()*]");
String mixinKey(String o) {
  final s = StringBuffer();
  for (var i = 0; i < 32; i++) {
    s.write(o[tab[i]]);
  }
  return s.toString();
}
String keyOf(String u) => u.substring(u.lastIndexOf('/') + 1).split('.').first;

Map<String, dynamic> sign(Map<String, dynamic> p, String img, String sub) {
  final mixin = mixinKey(keyOf(img) + keyOf(sub));
  p['wts'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final keys = p.keys.toList()..sort();
  final b = StringBuffer();
  for (final k in keys) {
    final v = p[k];
    if (v == null) continue;
    b
      ..write(Uri.encodeQueryComponent(k))
      ..write('=')
      ..write(Uri.encodeQueryComponent(v.toString().replaceAll(re, '')))
      ..write('&');
  }
  final noTail = b.toString();
  p['w_rid'] = md5.convert(utf8.encode('${noTail.substring(0, noTail.length - 1)}$mixin')).toString();
  return p;
}

Future<void> main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 30),
  ));
  final cookies = <String, String>{};

  Future<Response> get(String url, {String? ref}) => dio.get(url,
      options: Options(
        responseType: url == home ? ResponseType.plain : ResponseType.json,
        headers: {
          'User-Agent': ua,
          if (ref != null) 'Referer': ref,
          'Cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        },
        validateStatus: (_) => true,
      ));

  void absorb(Response r) {
    final sc = r.headers['set-cookie'];
    if (sc == null) return;
    for (final line in sc.toList()) {
      final seg = line.split(';').first.trim();
      final idx = seg.indexOf('=');
      if (idx > 0) cookies[seg.substring(0, idx).trim()] = seg.substring(idx + 1).trim();
    }
  }

  Future<void> probe(String name, String url) async {
    final r = await get(url, ref: home);
    absorb(r);
    final d = r.data;
    final data = d is Map ? d['data'] : null;
    if (data is Map && data.containsKey('result')) {
      final list = data['result'] as List? ?? [];
      final n = data['numResults'];
      print('[$name] code=${d['code']} msg=${d['message']} num=$n items=${list.length}');
      for (final it in list.take(3)) {
        final m = it as Map;
        print('    -- ${m['bvid']} | ${(m['title'] as String).replaceAll('<em class="keyword">', '').replaceAll('</em>', '')} | v=${m['videos']} dur=${m['duration']}');
      }
    } else {
      print('[$name] code=${d is Map ? d['code'] : '?'} msg=${d is Map ? d['message'] : '?'} dataType=${d is Map ? d['data'].runtimeType : d?.runtimeType}');
    }
  }

  final warm = await get(home);
  absorb(warm);
  print('warm: cookies=${cookies.keys}');

  // hit one api to get buvid4
  final apiPing = await get('$base/x/web-interface/nav');
  absorb(apiPing);
  print('nav: code=${apiPing.data['code']} cookies=${cookies.keys}');

  String qs(Map<String, dynamic> p) =>
      p.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent('${e.value}')}').join('&');

  // search WITHOUT wbi
  await probe('plain-video-三体', '$base/x/web-interface/wbi/search/type?${qs({'search_type': 'video', 'keyword': '三体', 'page': 1, 'page_size': 20})}');
  final r = await get(
      '$base/x/web-interface/wbi/search/type?${qs({'search_type': 'video', 'keyword': '三体666', 'page': 1, 'page_size': 20})}',
      ref: home);
  absorb(r);
  final data = r.data is Map ? r.data['data'] : null;
  final dump = jsonEncode(data);
  print('RAW data: ${dump.length > 400 ? dump.substring(0, 400) : dump}');
  await probe('plain-video-有声小说', '$base/x/web-interface/wbi/search/type?${qs({'search_type': 'video', 'keyword': '有声小说', 'page': 1, 'page_size': 20})}');
  await probe('all-type有声书', '$base/x/web-interface/wbi/search/type?${qs({'search_type': 'all', 'keyword': '有声书', 'page': 1, 'page_size': 20})}');
  // search_types: media_bangumi
  await probe('media_bangumi有声小说', '$base/x/web-interface/wbi/search/type?${qs({'search_type': 'media_bangumi', 'keyword': '有声小说', 'page': 1, 'page_size': 20})}');
  print('final cookies: ${cookies.keys}');
}