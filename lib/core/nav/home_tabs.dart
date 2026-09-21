import 'package:flutter/foundation.dart';

/// 全局底部 Tab 切换（供空态"去发现"等跨页面跳转使用）
class HomeTabs {
  HomeTabs._();
  static final ValueNotifier<int> index = ValueNotifier<int>(0);

  static void switchTo(int i) => index.value = i;
}