# Android 构建准备与检查

## 生成原生插件注册代码

首次检出或更新依赖后，先确保 `flutter pub get` 成功，再构建 APK：

```powershell
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64 --no-pub
```

Flutter 会生成被 Git 忽略的 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`。它负责把播放器、音频服务、JNI 和存储等插件注册到引擎。

不要在 `flutter pub get` 失败后直接调用 Gradle 绕过准备步骤。如果注册文件缺失，原生 Gradle 构建可能仍然成功，但 `media_kit` 的 Android helper 没有初始化，Dart 入口会同步等待 JavaVM 指针，导致首帧无法绘制和启动 ANR。

项目的应用 Gradle 脚本会检查注册文件及播放器注册，缺失时立即报错并提示运行 `flutter pub get`。`flutter build apk --config-only --no-pub` 不能代替成功的依赖准备。

在没有桌面软链接权限的 Windows 环境中，只构建 Android 时，可以仅在当前 PowerShell 进程禁用桌面平台：

```powershell
$env:FLUTTER_WINDOWS = 'false'
$env:FLUTTER_LINUX = 'false'
flutter pub get
```

这不修改系统设置或全局 Flutter 配置。使用桌面功能时，在新的终端继续正常构建即可。

## 友盟插件重复类

当前锁定的 `umeng_common_sdk 1.3.1` 同时包含同包同名的 Java 真实实现和 Kotlin `getPlatformVersion` 示例，可能触发 `Redeclaration`。根 Gradle 脚本仅排除重名 Kotlin 示例文件，保留 Java SDK 功能和其他源文件，不修改全局 Pub 缓存。

## 验证范围

- Android ARM64 release 构建通过，签名与 ZIP 对齐检查通过。
- APK DEX 中确认存在自动插件注册类。
- 临时移走注册文件后，Gradle 按预期拒绝构建；恢复文件后正常构建。
- 荣耀 Magic8 Pro、Android 17 真机三次冷启动及书架、“我的”、统计页交互正常，检查期间无新增 ANR。

构建和真机启动检查不能替代长时间后台播放、锁屏、离线以及跨日计时验证。
