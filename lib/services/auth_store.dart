import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/bili_client.dart';
import 'bili_api.dart';

/// 登录态 + 用户信息（本地持久化，供 UI 展示）
class LoginStore extends ChangeNotifier {
  LoginStore._();
  static final LoginStore instance = LoginStore._();

  static const _key = 'bili_login_user';

  bool _isLogin = false;
  String _userName = '';
  String _userFace = '';

  bool get isLogin => _isLogin;
  String get userName => _userName;
  String get userFace => _userFace;

  BiliClient get _client => BiliClient.instance;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map;
        _isLogin = m['login'] == true;
        _userName = m['name'] as String? ?? '';
        _userFace = m['face'] as String? ?? '';
      } catch (_) {}
    } else {
      _isLogin = _client.isLoggedIn;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      jsonEncode({
        'login': _isLogin,
        'name': _userName,
        'face': _userFace,
      }),
    );
  }

  /// 从 nav 接口刷新登录态与用户名/头像
  Future<void> refreshFromNav() async {
    try {
      final u = await BiliApi.instance.currentUser();
      _isLogin = u.isLogin || _client.isLoggedIn;
      _userName = u.uname;
      _userFace = u.face;
      await _persist();
      notifyListeners();
    } catch (e) {
      debugPrint('[LoginStore] refresh nav failed: $e');
    }
  }

  Future<void> markLoggedOut() async {
    await _client.logout();
    _isLogin = false;
    _userName = '';
    _userFace = '';
    await _persist();
    notifyListeners();
  }
}