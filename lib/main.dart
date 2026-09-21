import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'core/network/bili_client.dart';
import 'core/storage/search_history_store.dart';
import 'core/storage/shelf_store.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'pages/home_shell.dart';
import 'player/bili_audio_handler.dart';
import 'player/book_player.dart';
import 'services/auth_store.dart';
import 'services/umeng_analytics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

  // 友盟统计初始化（runApp 前完成，保证首启日活采集）
  await AppAnalytics.init();

  // 通知权限（Android 13+ 锁屏媒体控制需要）
  if (Platform.isAndroid) {
    await Permission.notification.request();
  }

  // 网络预热 + 书架加载 + 登录态
  final client = BiliClient.instance;
  final shelf = ShelfStore.instance;
  await Future.wait([
    client.init(),
    shelf.load(),
    ThemeController.instance.load(),
    SearchHistoryStore.instance.load(),
    LoginStore.instance.load(),
  ]);
  if (client.isLoggedIn) {
    LoginStore.instance.refreshFromNav();
  }

  // 播放器初始化 + 系统媒体会话绑定
  final player = BookPlayer.instance;
  player.setup();
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
  );
  player.attachHandler(handler);

  runApp(const AbTingShuApp());
}

class AbTingShuApp extends StatefulWidget {
  const AbTingShuApp({super.key});

  @override
  State<AbTingShuApp> createState() => _AbTingShuAppState();
}

class _AbTingShuAppState extends State<AbTingShuApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
            home: KeyedSubtree(
              key: ValueKey('theme-${tc.mode.name}'),
              child: const HomeShell(),
            ),
          );
        },
      ),
    );
  }
}