import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/cache_store.dart';
import '../core/theme/app_theme.dart';
import '../services/auth_store.dart';
import '../services/device_service.dart';
import '../widgets/tv_page_scaffold.dart';
import 'login_page.dart';

/// 设置（独立页面）：账号信息 + 播放与后台。未登录也可进入
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  bool _ignoring = false;

  /// 缓存位置展示信息
  bool _cacheExternal = false;
  String _cachePath = '';
  String _cacheFree = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshCacheInfo();
  }

  Future<void> _refresh() async {
    final v = await DeviceService.instance.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _ignoring = v;
      _loading = false;
    });
  }

  Future<void> _refreshCacheInfo() async {
    final cache = CacheStore.instance;
    String path = '';
    String free = '';
    try {
      path = await cache.dirPath();
    } catch (_) {}
    try {
      final bytes = await cache.freeSpace();
      if (bytes > 0) free = '可用 ${_fmtBytes(bytes)}';
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _cacheExternal = cache.location == 'external';
      _cachePath = path;
      _cacheFree = free;
    });
  }

  static String _fmtBytes(int bytes) {
    final gb = bytes / 1024 / 1024 / 1024;
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
  }

  /// 选择缓存位置（内部存储 / 外部存储·SD 卡）
  Future<void> _pickCacheLocation() async {
    final cache = CacheStore.instance;
    final choose = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(
                children: [
                  Text(
                    '缓存位置',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                ],
              ),
            ),
            RadioGroup<String>(
              groupValue: cache.location,
              onChanged: (v) => Navigator.of(ctx).pop(v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'internal',
                    activeColor: AppTheme.accent,
                    title: const Text('内部存储',
                        style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      '应用私有目录，最稳定，卸载应用时一并删除',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'external',
                    activeColor: AppTheme.accent,
                    title: const Text('外部存储 / SD 卡',
                        style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      '省内部空间；拔卡或未挂载时离线缓存暂时听不了',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choose == null || choose == cache.location) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('切换缓存位置',
            style: TextStyle(color: AppTheme.textMain, fontSize: 17)),
        content: Text(
          '已缓存的音频会迁移到${choose == 'external' ? '外部存储' : '内部存储'}，'
          '迁移期间请不要退出应用。',
          style: TextStyle(color: AppTheme.textSub, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('开始迁移', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在迁移缓存，请稍候…'),
        duration: Duration(seconds: 2),
      ),
    );
    final err = await cache.setLocation(choose);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? '已切换缓存位置'),
        duration: const Duration(seconds: 3),
      ),
    );
    _refreshCacheInfo();
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      await DeviceService.instance.requestIgnoreBatteryOptimization();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_ignoring
              ? '已开启后台留存保护'
              : '请在系统弹窗中允许「不受限制」'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('如需关闭，请在系统电池设置中恢复限制')),
      );
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('退出登录',
            style: TextStyle(color: AppTheme.textMain, fontSize: 17)),
        content: Text(
          '退出后需要重新扫码登录，书架与收听进度仍保留在本机。',
          style: TextStyle(color: AppTheme.textSub, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('退出', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LoginStore.instance.markLoggedOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<LoginStore>();
    return TvPageScaffold(
      title: const Text('系统设置'),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          _buildAccountCard(auth),
          const SizedBox(height: 12),
          _sectionTitle('播放与后台'),
          SwitchListTile(
            value: _ignoring,
            onChanged: _loading ? null : _toggle,
            activeThumbColor: AppTheme.accent,
            secondary:
                Icon(Icons.battery_saver_rounded, color: AppTheme.accent),
            title: Text(
              '后台留存保护',
              style: TextStyle(fontSize: 14, color: AppTheme.textMain),
            ),
            subtitle: Text(
              _loading
                  ? '检测中…'
                  : _ignoring
                      ? '已豁免电池优化，退到后台更不易被系统清理'
                      : '未开启，长时间后台播放可能被系统中断',
              style: TextStyle(fontSize: 12, color: AppTheme.textSub),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Text(
                '播放时应用会以前台服务常驻（通知栏可见），熄屏/锁屏也能继续听。'
                '开启「后台留存保护」可进一步降低被清理的概率。\n\n'
                '若仍被中断，建议在系统设置中为本应用打开「自启动」并设置「无限制」后台策略。',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSub, height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle('存储与缓存'),
          ListTile(
            leading:
                Icon(Icons.sd_storage_outlined, color: AppTheme.accent),
            title: Text(
              '缓存位置',
              style: TextStyle(fontSize: 14, color: AppTheme.textMain),
            ),
            subtitle: Text(
              _cachePath.isEmpty
                  ? '检测中…'
                  : '${_cacheExternal ? '外部存储 / SD 卡' : '内部存储'}'
                      '${_cacheFree.isEmpty ? '' : ' · $_cacheFree'}\n$_cachePath',
              style: TextStyle(fontSize: 12, color: AppTheme.textSub),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppTheme.textHint),
            onTap: _pickCacheLocation,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppTheme.textMain,
        ),
      ),
    );
  }

  /// 账号信息：未登录显示登录入口，已登录显示昵称头像与退出登录
  Widget _buildAccountCard(LoginStore auth) {
    final logged = auth.isLogin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      // 用 Material 承载卡片底色：卡内按钮的聚焦高亮/水波才能画在
      // 卡片之上（普通 Container 白底会盖住 ink 层）
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
          ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surfaceHigh,
                border: Border.all(color: AppTheme.divider),
                image: logged && auth.userFace.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(auth.userFace),
                        fit: BoxFit.cover,
                        onError: (_, _) {},
                      )
                    : null,
              ),
              child: !logged || auth.userFace.isEmpty
                  ? Icon(Icons.person_rounded, size: 28, color: AppTheme.accent)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    logged
                        ? (auth.userName.isEmpty ? 'B 站用户' : auth.userName)
                        : '未登录',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    logged ? '已登录' : '登录后可同步昵称与头像',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (logged)
              OutlinedButton(
                onPressed: _logout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSub,
                  side: BorderSide(color: AppTheme.divider),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 34),
                ),
                child: const Text('退出登录', style: TextStyle(fontSize: 13)),
              )
            else
              FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 34),
                ),
                child: const Text('登录', style: TextStyle(fontSize: 13)),
              ),
          ],
          ),
        ),
      ),
    );
  }
}
