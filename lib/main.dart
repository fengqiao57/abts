import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'core/network/bili_client.dart';
import 'core/storage/search_history_store.dart';
import 'core/storage/shelf_store.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'pages/home_shell.dart';
import 'pages/splash_screen.dart';
import 'player/bili_audio_handler.dart';
import 'player/book_player.dart';
import 'services/auth_store.dart';
import 'services/umeng_analytics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

  // 立即渲染启动页（LOGO + 加载动画），初始化在启动页展示期间执行，避免白屏
  runApp(const AbTingShuApp());
}

/// 第一阶段：启动关键初始化。
///
/// 全部为本地操作（SharedPreferences / 播放器 / 媒体服务），不做任何网络
/// 请求；整体 6 秒超时兜底，任何一项异常都不会把用户卡在启动页。
Future<void> _bootstrap() async {
  try {
    await Future.wait([
      BiliClient.instance.initLocal(),
      ShelfStore.instance.load(),
      ThemeController.instance.load(),
      SearchHistoryStore.instance.load(),
      LoginStore.instance.load(),
    ]).timeout(const Duration(seconds: 6));
  } catch (e) {
    debugPrint('[main] local init failed: $e');
  }

  // 播放器初始化 + 系统媒体会话绑定（失败也进主界面，播放时自动降级）
  final player = BookPlayer.instance;
  player.setup();
  try {
    final handler = await AudioService.init(
      builder: () => BiliAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.pages.abts.channel.audio',
        androidNotificationChannelName: '阿B听书',
        androidNotificationChannelDescription: '播放有声小说',
        androidNotificationIcon: 'mipmap/ic_launcher',
        // 暂停（含来电打断）时保留前台服务与通知，避免打断后通知栏直接消失。
        // 注意：audio_service 要求此时 androidNotificationOngoing 必须为 false。
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationClickStartsActivity: true,
      ),
    ).timeout(const Duration(seconds: 6));
    player.attachHandler(handler);
  } catch (e) {
    debugPrint('[main] audio service init failed: $e');
  }
}

/// 第二阶段：非关键请求（统计 / 网络预热 / 登录态刷新）。
///
/// 全部在进入主界面之后后台执行，即使全部失败或长时间无响应，
/// 也只影响对应功能的可用性，绝不阻塞用户进入页面。
/// （通知权限改为首次播放时按需申请，见 BookPlayer）
void _bootstrapBackground() {
  unawaited(AppAnalytics.init());
  unawaited(BiliClient.instance.warmupIfNeeded());
  if (BiliClient.instance.isLoggedIn) {
    unawaited(LoginStore.instance.refreshFromNav());
  }
}

class AbTingShuApp extends StatefulWidget {
  const AbTingShuApp({super.key});

  @override
  State<AbTingShuApp> createState() => _AbTingShuAppState();
}

class _AbTingShuAppState extends State<AbTingShuApp>
    with WidgetsBindingObserver {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap().whenComplete(() {
      if (!mounted) return;
      setState(() => _ready = true);
      _bootstrapBackground();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 退到后台/被系统回收前落库进度，保证下次续播精确到秒
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      BookPlayer.instance.flushProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = ThemeController.instance;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ShelfStore.instance),
        ChangeNotifierProvider.value(value: BookPlayer.instance),
        ChangeNotifierProvider.value(value: LoginStore.instance),
        ChangeNotifierProvider.value(value: SearchHistoryStore.instance),
      ],
      child: AnimatedBuilder(
        animation: tc,
        builder: (context, _) {
          AppTheme.mode = tc.mode;
          return MaterialApp(
            title: '阿B听书',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: tc.mode,
            home: _ready
                ? KeyedSubtree(
                    key: ValueKey('theme-${tc.mode.name}'),
                    child: const HomeShell(),
                  )
                : const SplashScreen(),
          );
        },
      ),
    );
  }
}