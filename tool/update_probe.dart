import 'package:dio/dio.dart';

import '../lib/core/app_meta.dart';
import '../lib/services/app_update.dart';

Future<void> main() async {
  final r = await AppUpdate.check();
  print('configured : ${r.configured}');
  print('error      : ${r.error}');
  print('latestVer  : ${r.latestVersion}');
  print('latestName : ${r.latestName}');
  print('hasNewer   : ${r.hasNewer}');
  print('apkUrl     : ${r.apkUrl}');
  print('htmlUrl    : ${r.htmlUrl}');
  print('localVer   : ${AppMeta.version}');
  print('--- 结果判定 ---');
  if (!r.configured) {
    print('暂未配置更新源');
  } else if (r.error != null) {
    print('失败：${r.error}');
  } else if (r.hasNewer) {
    print('有新版本：可提示下载');
  } else {
    print('已是最新版本（链路跑通）');
  }
}