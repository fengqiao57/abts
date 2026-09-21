import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// 验证「只搜有声小说」新版逻辑（原词搜索 + 过滤 + 补搜 + 榜单翻页去重），
/// 结果写入 tool/audiobook_probe_out.txt（UTF-8），便于人工核对。
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
  p['w_rid'] = md5
      .convert(utf8.encode('${noTail.substring(0, noTail.length - 1)}$mixin'))
      .toString();
  return p;
}

// ---------- 与 lib/services/bili_api.dart 一致的规则 ----------
const audioHints = <String>[
  '有声小说', '有声书', '有声剧', '有声读物', '有声', '听书', '评书', '相声',
  '广播剧', '演播', '朗读', '诵读', '长书', '连播', '说书', '单口', '播讲',
  '多人剧', '小说剧',
];
const noiseHints = <String>[
  '一口气看完', '漫推', '漫画', '解说', '讲解', '解读', '动画', '鬼畜', '混剪',
  '沙雕', '速看', 'reaction', '预告', '游戏实况', '配音秀',
];

bool hasAudioHint(String s) => audioHints.any(s.contains);

const audioTypeId = 195;

class Item {
  final String bvid;
  final String title;
  final String tag;
  final String desc;
  final int typeid;
  final int duration;
  Item(this.bvid, this.title, this.tag, this.desc, this.typeid, this.duration);
}

int parseDurationSeconds(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = '$v'.trim();
  if (s.isEmpty) return 0;
  final parts = s.split(':');
  if (parts.length >= 2) {
    var total = 0;
    for (final p in parts) {
      total = total * 60 + (int.tryParse(p.trim()) ?? 0);
    }
    return total;
  }
  return int.tryParse(s) ?? 0;
}

const genreHints = <String>[
  '评书', '相声', '广播剧', '听书', '演播', '朗读', '诵读', '长书', '连播',
  '说书', '单口', '播讲',
];

bool isAudiobook(Item b, String keyword) {
  final meta = '${b.desc} ${b.tag}';
  if (noiseHints.any('${b.title} $meta'.contains)) return false;
  if (hasAudioHint(b.title) && b.duration >= 300) return true;
  if (b.typeid == audioTypeId && b.duration >= 600) return true;
  if (hasAudioHint(meta) && b.duration >= 1800) return true;
  if (genreHints.any(keyword.contains) && b.duration >= 1800) return true;
  return false;
}

final out = StringBuffer();
void log(String s) {
  out.writeln(s);
  print(s);
}

Future<void> main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.json,
    validateStatus: (_) => true,
  ));
  final cookies = <String, String>{};

  Future<Response> get(String url, {String? ref, String? origin}) => dio.get(url,
      options: Options(
        headers: {
          'User-Agent': ua,
          if (ref != null) 'Referer': ref,
          if (origin != null) 'Origin': origin,
          'Cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        },
      ));

  void absorb(Response r) {
    final sc = r.headers['set-cookie'];
    if (sc == null) return;
    for (final line in sc.toList()) {
      final seg = line.split(';').first.trim();
      final idx = seg.indexOf('=');
      if (idx > 0) {
        cookies[seg.substring(0, idx).trim()] = seg.substring(idx + 1).trim();
      }
    }
  }

  absorb(await get(home));
  final nav = await get('$base/x/web-interface/nav', ref: home);
  absorb(nav);
  final wbi = ((nav.data as Map)['data'] as Map?)?['wbi_img'] as Map?;
  final img = wbi?['img_url'] as String?;
  final sub = wbi?['sub_url'] as String?;
  log('WBI ok=${img != null && sub != null}');

  Future<List<Item>> raw(String kw, {int page = 1, String? order}) async {
    final p = sign(
      {
        'search_type': 'video',
        'keyword': kw,
        'page': page,
        'page_size': 20,
        'platform': 'pc',
        'web_location': 1430654,
        if (order != null) 'order': order,
      },
      img!,
      sub!,
    );
    final qs = p.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent('${e.value}')}')
        .join('&');
    Response r;
    for (var attempt = 1;; attempt++) {
      r = await get(
        '$base/x/web-interface/wbi/search/type?$qs',
        ref: '$home/video?keyword=${Uri.encodeComponent(kw)}',
        origin: 'https://search.bilibili.com',
      );
      absorb(r);
      final d = r.data;
      final data = d is Map ? d['data'] as Map? : null;
      if (data != null && data['result'] == null && data['v_voucher'] != null) {
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 1500 * attempt));
          continue;
        }
      }
      break;
    }
    final d = r.data;
    final data = d is Map ? d['data'] as Map? : null;
    final list = (data?['result'] as List?)?.cast<Map>() ?? [];
    final items = <Item>[];
    for (final m in list) {
      final t = (m['title'] as String)
          .replaceAll('<em class="keyword">', '')
          .replaceAll('</em>', '');
      items.add(Item(
        '${m['bvid']}',
        t,
        '${m['tag'] ?? ''}',
        '${m['description'] ?? ''}',
        int.tryParse('${m['typeid'] ?? 0}') ?? 0,
        parseDurationSeconds(m['duration']),
      ));
    }
    return items;
  }

  /// 复刻 BiliApi.search：原词 + 过滤，命中太少时补搜「kw 有声小说」
  Future<List<Item>> searchAudiobooks(String keyword) async {
    final kw = keyword.trim();
    final rawList = await raw(kw);
    final primary = rawList.where((b) => isAudiobook(b, keyword)).toList();
    if (primary.length >= 6 || hasAudioHint(kw)) return primary;
    try {
      final extra = (await raw('$kw 有声小说'))
          .where((b) => isAudiobook(b, kw))
          .toList();
      final seen = primary.map((b) => b.bvid).toSet();
      for (final b in extra) {
        if (seen.add(b.bvid)) primary.add(b);
      }
    } catch (_) {}
    return primary;
  }

  Future<void> show(String keyword) async {
    log('');
    log('==================== 「$keyword」 ====================');
    final rawList = await raw(keyword);
    final kept = rawList.where((b) => isAudiobook(b, keyword)).toList();
    final dropped = rawList.where((b) => !isAudiobook(b, keyword)).toList();
    log('原词共 ${rawList.length} 条：保留 ${kept.length}，剔除 ${dropped.length}');
    log('-- 保留 --');
    for (final b in kept) {
      log('  ✅ [tid=${b.typeid} ${b.duration}s] ${b.title}');
    }
    log('-- 剔除 --');
    for (final b in dropped) {
      log('  ❌ [tid=${b.typeid} ${b.duration}s] ${b.title}');
    }
    if (kept.length < 6 && !hasAudioHint(keyword)) {
      final merged = await searchAudiobooks(keyword);
      log('-- 补搜合并后共 ${merged.length} 条 --');
      for (final b in merged) {
        log('  ➕ [tid=${b.typeid} ${b.duration}s] ${b.title}');
      }
    }
  }

  // 榜单（热门推荐）
  log('');
  log('==================== 榜单：有声小说 order=click ====================');
  final all = <Item>[];
  for (var page = 1; page <= 2; page++) {
    final list = await raw('有声小说', page: page, order: 'click');
    final kept = list.where((b) => isAudiobook(b, '有声小说')).toList();
    log('第 $page 页：${list.length} 条 → 保留 ${kept.length}');
    all.addAll(kept);
  }
  final seen = <String>{};
  final ranked = <Item>[];
  for (final b in all) {
    if (seen.add(b.title)) ranked.add(b);
  }
  log('榜单去重后 ${ranked.length} 条：');
  for (final b in ranked) {
    log('  🔥 [tid=${b.typeid} ${b.duration}s] ${b.title}');
  }

  await show('三体');
  await show('盗墓笔记');
  await show('悬疑有声小说');
  await show('评书 单田芳');
  await show('相声 德云社');

  final f = File('tool/audiobook_probe_out.txt');
  await f.writeAsString(out.toString(), encoding: utf8);
  print('written: ${f.absolute.path}');
}
