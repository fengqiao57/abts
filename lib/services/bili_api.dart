import '../core/network/api_config.dart';
import '../core/network/bili_client.dart';
import '../models/audio_stream.dart';
import '../models/book.dart';
import '../models/chapter.dart';

/// B 站听书数据访问层
class BiliApi {
  BiliApi._();
  static final BiliApi instance = BiliApi._();

  final BiliClient _client = BiliClient.instance;

  /// 听书特征词：命中即视为有声内容
  static const _audioHints = <String>[
    '有声小说', '有声书', '有声剧', '有声读物', '有声', '听书', '评书', '相声',
    '广播剧', '演播', '朗读', '诵读', '长书', '连播', '说书', '单口', '播讲',
    '多人剧', '小说剧',
  ];

  /// 明显不是听书内容的特征词（漫推/解说/鬼畜等）
  static const _noiseHints = <String>[
    '一口气看完', '漫推', '漫画', '解说', '讲解', '解读', '动画', '鬼畜', '混剪',
    '沙雕', '速看', 'reaction', '预告', '游戏实况', '配音秀',
  ];

  static bool _hasAudioHint(String s) => _audioHints.any(s.contains);

  /// 题材词：搜索词本身是这些题材时，长内容按听书放行（如「评书 单田芳」）
  static const _genreHints = <String>[
    '评书', '相声', '广播剧', '听书', '演播', '朗读', '诵读', '长书', '连播',
    '说书', '单口', '播讲',
  ];

  /// B 站「动态漫.广播剧」分区（听书内容主分区）
  static const _audioTypeId = 195;

  /// 只保留有声小说/听书类内容。
  ///
  /// 判定优先级（命中噪音词一律剔除）：
  /// 1. 标题含听书特征词且 >= 5 分钟；
  /// 2. 听书主分区（195 动态漫.广播剧）且 >= 10 分钟；
  /// 3. 简介/标签含听书特征词且 >= 30 分钟（防止蹭标签的短视频）；
  /// 4. 搜索词本身是听书题材（评书/相声…）且 >= 30 分钟。
  static bool _isAudiobookItem(Map<String, dynamic> m, String keyword) {
    final title = '${m['title'] ?? ''}';
    final meta = '${m['description'] ?? ''} ${m['tag'] ?? ''}';
    if (_noiseHints.any('$title $meta'.contains)) return false;

    final seconds = Book.parseDurationSeconds(m['duration']);
    if (_hasAudioHint(title) && seconds >= 300) return true;

    final typeid = int.tryParse('${m['typeid'] ?? 0}') ?? 0;
    if (typeid == _audioTypeId && seconds >= 600) return true;

    if (_hasAudioHint(meta) && seconds >= 1800) return true;

    if (_genreHints.any(keyword.contains) && seconds >= 1800) return true;
    return false;
  }

  /// 原始搜索：不做关键词改写，但结果一律过滤为非听书内容
  Future<List<Book>> _searchRaw(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    String? order,
    Function(int total)? onFirstPage,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final res = await _client.get(
          BiliEndpoints.searchType,
          query: {
            'search_type': 'video',
            'keyword': keyword,
            'page': page,
            'page_size': pageSize,
            'platform': 'pc',
            'web_location': 1430654,
            if (order != null && order.isNotEmpty) 'order': order,
          },
          useWbi: true,
          headers: {
            'origin': BiliEndpoints.searchHome,
            'referer': '${BiliEndpoints.searchHome}/video'
                '?keyword=${Uri.encodeComponent(keyword)}',
          },
        );
        final data = res.data as Map;
        final result = data['data'] as Map? ?? {};
        // v_voucher：触发极验风控，等待后重试
        if (result['result'] == null && result['v_voucher'] != null) {
          if (attempt < 3) {
            await Future<void>.delayed(Duration(milliseconds: 1500 * attempt));
            continue;
          }
          throw BiliApiException(-412, '网络繁忙，请稍后再试');
        }
        final numResults = int.tryParse('${result['numResults'] ?? 0}') ?? 0;
        final list = result['result'] as List? ?? [];
        final books = <Book>[];
        for (final item in list) {
          if (item is! Map) continue;
          final m = item.cast<String, dynamic>();
          if (!_isAudiobookItem(m, keyword)) continue;
          final b = Book.fromSearch(m);
          if (b.bvid.isEmpty || b.aid == 0) continue;
          books.add(b);
        }
        onFirstPage?.call(page == 1 ? numResults : 0);
        return books;
      } on BiliApiException catch (e) {
        if (e.code == -412 && attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 1500 * attempt));
          continue;
        }
        rethrow;
      }
    }
  }

  /// 搜索（只返回有声小说）
  ///
  /// 先用原关键词搜（标题相关性最好），命中太少时再用
  /// 「关键词 有声小说」补搜一次并合并去重。
  Future<List<Book>> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    String? order,
    Function(int total)? onFirstPage,
  }) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];
    final primary = await _searchRaw(
      kw,
      page: page,
      pageSize: pageSize,
      order: order,
      onFirstPage: onFirstPage,
    );
    if (primary.length >= 6 || _hasAudioHint(kw)) return primary;

    try {
      final extra = await _searchRaw(
        '$kw 有声小说',
        page: page,
        pageSize: pageSize,
        order: order,
      );
      final seen = primary.map((b) => b.bvid).toSet();
      for (final b in extra) {
        if (seen.add(b.bvid)) primary.add(b);
      }
    } catch (_) {
      // 补搜失败不影响主结果
    }
    return primary;
  }

  /// 热门推荐（榜单）：有声小说按播放量排序，翻页凑量 + 按标题去重
  Future<List<Book>> rankHotNovel({int limit = 30}) async {
    final all = <Book>[];
    for (var page = 1; page <= 2; page++) {
      try {
        final list = await _searchRaw(
          '有声小说',
          page: page,
          pageSize: 20,
          order: 'click',
        );
        all.addAll(list);
        if (list.isEmpty) break;
      } catch (_) {
        break;
      }
    }
    final seen = <String>{};
    final out = <Book>[];
    for (final b in all) {
      if (!seen.add(b.cleanTitle)) continue;
      out.add(b);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 书籍详情（含分P章节）
  Future<Book> detail(String bvid) async {
    final res = await _client.get(
      BiliEndpoints.view,
      query: {'bvid': bvid},
    );
    final data = res.data as Map;
    if (data['data'] is! Map) {
      throw BiliApiException(-404, '视频不存在或已被删除');
    }
    return Book.fromView((data['data'] as Map).cast<String, dynamic>());
  }

  /// 纯分P列表
  Future<List<Chapter>> pageList(String bvid) async {
    final res = await _client.get(
      BiliEndpoints.pageList,
      query: {'bvid': bvid},
    );
    final data = res.data as Map;
    final list = data['data'] as List? ?? [];
    return list
        .map((e) => Chapter.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 取音频流
  Future<BookAudio> playUrl(String bvid, int cid) async {
    final res = await _client.get(
      BiliEndpoints.playUrl,
      query: {
        'bvid': bvid,
        'cid': cid,
        'qn': 80,
        'fnval': 4048,
        'fnver': 0,
        'fourk': 1,
        'try_look': 1,
        'gaia_source': 'prefer-ua',
      },
      useWbi: true,
    );
    final data = res.data as Map;
    return BookAudio.fromMap((data['data'] as Map).cast<String, dynamic>());
  }

  // ---------- 二维码登录（网页 passport 流程） ----------

  /// 获取二维码内容与 key
  Future<({String url, String qrKey})> qrGenerate() async {
    final res = await _client.get(
      BiliEndpoints.qrGenerate,
      query: {'source': 'main-fe-header'},
    );
    final data = (res.data as Map)['data'] as Map? ?? {};
    return (
      url: data['url'] as String? ?? '',
      qrKey: data['qrcode_key'] as String? ?? '',
    );
  }

  /// 轮询二维码状态：success / waiting / scanned / expired / fail
  ///
  /// 成功时 CookieJar 已自动合并 SESSDATA/bili_jct/DedeUserID 并持久化
  Future<String> qrPoll(String qrKey) async {
    final res = await _client.get(
      BiliEndpoints.qrPoll,
      query: {'qrcode_key': qrKey, 'source': 'main-fe-header'},
    );
    final body = res.data as Map;
    // 外层 code 恒为 0，真正状态在 data.code
    final data = body['data'] as Map? ?? {};
    final code = data['code'] as int? ?? -1;
    return switch (code) {
      0 => 'success',
      86038 => 'expired',
      86090 => 'scanned',
      86101 => 'waiting',
      _ => 'fail',
    };
  }

  /// 当前用户信息（nav，登录与否均可用）
  Future<({bool isLogin, String uname, String face})> currentUser() async {
    final res = await _client.get(BiliEndpoints.nav);
    final data = (res.data as Map)['data'] as Map? ?? {};
    return (
      isLogin: data['isLogin'] == true,
      uname: data['uname'] as String? ?? '',
      face: data['face'] as String? ?? '',
    );
  }
}