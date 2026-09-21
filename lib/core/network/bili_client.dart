import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'cookie_jar.dart';
import 'wbi_signer.dart';

class BiliApiException implements Exception {
  final int? code;
  final String message;
  BiliApiException(this.code, this.message);

  @override
  String toString() => message;
}

/// B 站客户端：Cookie 预热 + buvid 激活 + WBI 签名 + 统一请求头 + 风控兜底
class BiliClient {
  BiliClient._();
  static final BiliClient instance = BiliClient._();

  static const _prefCookie = 'bili_cookie';
  static const _prefWbi = 'bili_wbi_keys';

  late Dio _dio;
  final CookieJar _jar = CookieJar.instance;

  String? _imgUrl;
  String? _subUrl;
  int _wbiFetchedAt = 0;

  bool _buvidActivated = false;
  int _lastReqAt = 0;

  static const _minGapMillis = 300;

  void _setupIo() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
      ),
    );
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) {
          final cookie = _jar.buildHeader();
          if (cookie.isNotEmpty) {
            options.headers['Cookie'] = cookie;
          }
          options.headers['User-Agent'] ??= BiliEndpoints.userAgent;
          handler.next(options);
        },
      ),
    );
  }

  /// 应用启动时持久化兜底
  Future<void> init() async {
    _setupIo();
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString(_prefCookie);
    if (cookie != null && cookie.isNotEmpty) {
      final map = <String, String>{};
      for (final seg in cookie.split(';')) {
        final eq = seg.indexOf('=');
        if (eq > 0) map[seg.substring(0, eq).trim()] = seg.substring(eq + 1).trim();
      }
      _jar.mergeFromMap(map);
    }
    final wbi = prefs.getString(_prefWbi);
    if (wbi != null) {
      final parts = wbi.split('|');
      if (parts.length == 3) {
        _imgUrl = parts[0];
        _subUrl = parts[1];
        _wbiFetchedAt = int.tryParse(parts[2]) ?? 0;
      }
    }

    if (!_jar.ready || _needFreshWbiKeys()) {
      await warmup();
    }
    // buvid 激活独立于 warmup（已登录重启时也会走）
    await _ensureBuvidActivated();
  }

  bool _needFreshWbiKeys() {
    if (_imgUrl == null || _subUrl == null) return true;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return _wbiFetchedAt < day.millisecondsSinceEpoch;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = _jar.buildHeader();
    if (cookie.isNotEmpty) {
      await prefs.setString(_prefCookie, cookie);
    } else {
      await prefs.remove(_prefCookie);
    }
    if (_imgUrl != null && _subUrl != null) {
      await prefs.setString(_prefWbi, '$_imgUrl|$_subUrl|$_wbiFetchedAt');
    }
  }

  /// 预热：访问首页种入 buvid，激活 buvid，并从 nav 拉取 WBI 密钥
  Future<void> warmup() async {
    try {
      final res = await _fetchRaw(BiliEndpoints.warmup);
      if (res.headers['set-cookie'] != null) {
        _jar.mergeFromHeaders(res.headers['set-cookie']);
      }
      _jar.markSuccess();
      debugPrint('[BiliClient] warmup cookie ok: ${_jar.buildHeader()}');
      await _ensureBuvidActivated();
      await _refreshWbiKeys();
      await _persist();
    } catch (e) {
      debugPrint('[BiliClient] warmup failed: $e');
    }
  }

  /// gaia 风控闭环：激活 buvid3，把匿名游客伪装成"活跃设备"，显著降低 v_voucher 概率
  Future<void> _ensureBuvidActivated() async {
    if (_buvidActivated) return;
    _buvidActivated = true;
    try {
      final rnd = Random();
      final png = base64.encode([
        for (var i = 0; i < 32; i++) rnd.nextInt(256),
        0, 0, 0, 0, 73, 69, 78, 68,
        for (var i = 0; i < 4; i++) rnd.nextInt(256),
      ]);
      final payload = jsonEncode({
        '3064': 1,
        '39c8': '333.1387.fp.risk',
        '3c43': {
          'adca': 'Linux',
          'bfe9': png.substring(png.length - 50),
        },
      });
      await post(BiliEndpoints.activateBuvid, data: {'payload': payload});
      debugPrint('[BiliClient] buvid activated');
    } catch (e) {
      debugPrint('[BiliClient] buvid activate failed: $e');
    }
  }

  Future<Response<dynamic>> _fetchRaw(
    String url, {
    Map<String, String>? headers,
    ResponseType? responseType,
  }) {
    return _dio.get<dynamic>(
      url,
      options: Options(
        headers: {
          'Referer': url.startsWith(BiliEndpoints.base) ? BiliEndpoints.home : url,
          ...?headers,
        },
        responseType: responseType ??
            (url == BiliEndpoints.warmup
                ? ResponseType.plain
                : ResponseType.json),
        validateStatus: (_) => true,
      ),
    );
  }

  /// 请求最小间隔，避免快速连续请求触发风控
  Future<void> _throttle() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final wait = _minGapMillis - (now - _lastReqAt);
    if (wait > 0) {
      await Future<void>.delayed(Duration(milliseconds: wait));
    }
    _lastReqAt = DateTime.now().millisecondsSinceEpoch;
  }

  /// 部分接口（如 passport 扫码）content-type 非 JSON，dio 会保留原始字符串，
  /// 这里统一尝试解码，保证上层拿到 Map。
  static Response<dynamic> _normalize(Response<dynamic> res) {
    final d = res.data;
    if (d is String && d.isNotEmpty) {
      final t = d.trimLeft();
      if (t.startsWith('{') || t.startsWith('[')) {
        try {
          return Response<dynamic>(
            data: jsonDecode(d),
            statusCode: res.statusCode,
            statusMessage: res.statusMessage,
            headers: res.headers,
            isRedirect: res.isRedirect,
            redirects: res.redirects,
            requestOptions: res.requestOptions,
            extra: res.extra,
          );
        } catch (_) {
          // 非 JSON，保持原样
        }
      }
    }
    return res;
  }

  Future<Response<dynamic>> _exec(
    String url, {
    required Map<String, String> headers,
  }) async {
    Response<dynamic> res;
    try {
      res = await _fetchRaw(url, headers: headers);
    } catch (e) {
      // 网络层透传错误：稍等后重试一次
      await Future<void>.delayed(const Duration(milliseconds: 800));
      res = await _fetchRaw(url, headers: headers);
    }
    if (res.headers['set-cookie'] != null) {
      _jar.mergeFromHeaders(res.headers['set-cookie']);
      await _persist();
    }
    return _normalize(res);
  }

  static bool _riskCode(int c) => c == -412 || c == -352;

  Future<void> _refreshWbiKeys() async {
    try {
      final res = await _fetchRaw(BiliEndpoints.nav);
      if (res.headers['set-cookie'] != null) {
        _jar.mergeFromHeaders(res.headers['set-cookie']);
      }
      final data = res.data;
      if (data is Map && data['data'] is Map && data['data']['wbi_img'] is Map) {
        final wbi = data['data']['wbi_img'] as Map;
        final img = wbi['img_url'] as String?;
        final sub = wbi['sub_url'] as String?;
        if (img != null && sub != null) {
          _imgUrl = img;
          _subUrl = sub;
          _wbiFetchedAt = DateTime.now().millisecondsSinceEpoch;
          debugPrint('[BiliClient] wbi keys refreshed');
        }
      }
      if (data is Map && data['code'] == 0) {
        _jar.markSuccess();
      }
      await _persist();
    } catch (e) {
      debugPrint('[BiliClient] refresh wbi keys failed: $e');
    }
  }

  /// 通用 GET：带 Cookie，可 WBI 签名，风控码自动稍等重试一次
  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? query,
    bool useWbi = false,
    Map<String, String>? headers,
  }) async {
    await _throttle();
    var q = {...?query};
    if (useWbi) {
      if (_imgUrl == null || _subUrl == null || _needFreshWbiKeys()) {
        await _refreshWbiKeys();
      }
      if (_imgUrl == null || _subUrl == null) {
        throw BiliApiException(-401, '初始化失败，请检查网络后重试');
      }
      q = WbiSigner.sign(q, imgUrl: _imgUrl!, subUrl: _subUrl!);
    }
    final fullUrl = q.isEmpty
        ? url
        : Uri.parse(url).replace(
            queryParameters: Map<String, String>.fromEntries(
              q.entries.map((e) => MapEntry(e.key, '${e.value}')),
            ),
          ).toString();

    try {
      var res = await _exec(
        fullUrl,
        headers: {'Referer': BiliEndpoints.home, ...?headers},
      );
      final body = res.data;
      if (body is Map) {
        final code = body['code'];
        if (code != null && code != 0 && _riskCode(code)) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          res = await _exec(
            fullUrl,
            headers: {'Referer': BiliEndpoints.home, ...?headers},
          );
        }
      }
      final last = res.data;
      final sc = res.statusCode;
      if (last is! Map && sc != null && sc >= 400) {
        throw BiliApiException(sc, 'HTTP $sc');
      }
      if (last is Map) {
        final code = last['code'];
        final message = last['message'] ?? last['msg'] ?? '';
        if (code != null && code != 0) {
          throw BiliApiException(
            _riskCode(code) ? -412 : code,
            _riskCode(code) ? '网络繁忙，请稍后再试' : '$code：$message',
          );
        }
      }
      return res;
    } on DioException catch (e) {
      throw BiliApiException(-1, '网络请求失败：${e.message}');
    }
  }

  /// 通用 POST：带 Cookie，JSON 表单，网络失败与风控码自动重试一次
  Future<Response<dynamic>> post(
    String url, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
    bool jsonBody = true,
  }) async {
    await _throttle();
    Response<dynamic>? res;
    Object? lastErr;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        res = await _dio.post<dynamic>(
          url,
          data: jsonBody ? jsonEncode(data ?? const {}) : data,
          options: Options(
            headers: {'Referer': BiliEndpoints.home, ...?headers},
            contentType: jsonBody ? Headers.jsonContentType : null,
            validateStatus: (_) => true,
          ),
        );
        break;
      } catch (e) {
        lastErr = e;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
    }
    if (res == null) {
      throw BiliApiException(-1, '网络请求失败：$lastErr');
    }
    res = _normalize(res);
    if (res.headers['set-cookie'] != null) {
      _jar.mergeFromHeaders(res.headers['set-cookie']);
      await _persist();
    }
    final body = res.data;
    if (body is Map) {
      final code = body['code'];
      final message = body['message'] ?? body['msg'] ?? '';
      if (code != null && code != 0) {
        throw BiliApiException(
          _riskCode(code) ? -412 : code,
          _riskCode(code) ? '网络繁忙，请稍后再试' : '$code：$message',
        );
      }
    }
    return res;
  }

  /// 是否已登录（有有效 SESSDATA）
  bool get isLoggedIn {
    final s = _jar.get('SESSDATA');
    return s != null && s.isNotEmpty;
  }

  /// 退出登录：清空并持久化
  Future<void> logout() async {
    _jar.clear();
    await _persist();
  }

  /// 生成本地 buvid3（UUID 大写 + 5 位随机 + infoc）
  static String genBuvid3() {
    final rnd = Random();
    String hex(int n) {
      final sb = StringBuffer();
      for (var i = 0; i < n; i++) {
        sb.write(rnd.nextInt(16).toRadixString(16));
      }
      return sb.toString();
    }

    final uuid = '${hex(8)}-${hex(4)}-4${hex(3)}-'
        '${(8 + rnd.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
    final suffix = rnd.nextInt(100000).toString().padLeft(5, '0');
    return '${uuid.toUpperCase()}$suffix' 'infoc';
  }

  CookieJar get jar => _jar;
}