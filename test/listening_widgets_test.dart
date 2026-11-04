import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:abts/core/storage/listening_store.dart';
import 'package:abts/core/theme/app_theme.dart';
import 'package:abts/pages/listening_stats_page.dart';
import 'package:abts/widgets/book_introduction.dart';

void main() {
  testWidgets(
    'statistics period navigation, empty state and responsive layouts',
    (tester) async {
      final store = ListeningStore();
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (font.existsSync()) {
        final loader = FontLoader('PreviewChinese')
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await loader.load();
      }
      final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
      final icons = File(
        '${artifacts.path}/material_fonts/materialicons-regular.otf',
      );
      if (icons.existsSync()) {
        final loader = FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
        await loader.load();
      }
      AppTheme.mode = ThemeMode.light;
      addTearDown(() => AppTheme.mode = ThemeMode.dark);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final boundaryKey = GlobalKey();
      Widget app() => ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light().copyWith(
            appBarTheme: AppTheme.light().appBarTheme.copyWith(
              titleTextStyle: AppTheme.light().appBarTheme.titleTextStyle
                  ?.copyWith(fontFamily: 'PreviewChinese'),
            ),
            textTheme: AppTheme.light().textTheme.apply(
              fontFamily: 'PreviewChinese',
            ),
          ),
          darkTheme: AppTheme.dark().copyWith(
            textTheme: AppTheme.dark().textTheme.apply(
              fontFamily: 'PreviewChinese',
            ),
          ),
          themeMode: AppTheme.mode,
          home: RepaintBoundary(
            key: boundaryKey,
            child: const ListeningStatsPage(),
          ),
        ),
      );
      tester.view.physicalSize = const Size(412, 915);
      await tester.pumpWidget(app());
      expect(find.textContaining('这段时间还没有听书记录'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNull,
      );
      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        store.record(
          start: DateTime(now.year, now.month, now.day - i, 10),
          duration: Duration(minutes: 15 + i * 8),
          bvid: 'BV$i',
          title: '测试书籍 $i · 有声小说',
          pic: '',
        );
      }
      await tester.pump();
      await tester.tap(find.text('月'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/previews')
          ..createSync(recursive: true);
        File(
          '${directory.path}/listening-stats-phone.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byTooltip('上一周期'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('回到本月'));
      await tester.pump();
      for (final size in [const Size(360, 800), const Size(1100, 650)]) {
        tester.view.physicalSize = size;
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      AppTheme.mode = ThemeMode.dark;
      await tester.pumpWidget(app());
      await tester.pump();
      expect(tester.takeException(), isNull);
      store.dispose();
    },
  );

  testWidgets(
    'long introduction can expand, select and collapse; empty has fallback',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: BookIntroduction(
                  description: List.filled(10, '这是完整的书籍介绍，包含人物与故事背景。\n').join(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('展开全部'), findsOneWidget);
      await tester.tap(find.text('展开全部'));
      await tester.pump();
      expect(find.byType(SelectableText), findsOneWidget);
      await tester.ensureVisible(find.text('收起介绍'));
      await tester.tap(find.text('收起介绍'));
      await tester.pump();
      expect(find.byType(SelectableText), findsNothing);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BookIntroduction(description: '  ')),
        ),
      );
      expect(find.text('暂无介绍'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
