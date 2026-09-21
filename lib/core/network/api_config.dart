/// B 站接口端点常量
class BiliEndpoints {
  BiliEndpoints._();

  static const String home = 'https://www.bilibili.com';
  static const String base = 'https://api.bilibili.com';
  static const String sSearch = 'https://s.search.bilibili.com';

  /// 网页搜索首页（搜索请求的合法来源 Referer/Origin）
  static const String searchHome = 'https://search.bilibili.com';

  /// 预热：拿 buvid 等基础 Cookie
  static const String warmup = '$home/';

  /// 获取 WBI img_key / sub_key 及登录态
  static const String nav = '$base/x/web-interface/nav';

  /// 通用搜索
  static const String searchType = '$base/x/web-interface/wbi/search/type';

  /// 视频基本信息（含分P列表）
  static const String view = '$base/x/web-interface/view';

  /// 分P列表
  static const String pageList = '$base/x/player/pagelist';

  /// 取流
  static const String playUrl = '$base/x/player/wbi/playurl';

  /// buvid 激活（gaia 风控闭环：ExClimbWuzhi）
  static const String activateBuvid = '$base/x/internal/gaia-gateway/ExClimbWuzhi';

  /// 二维码登录：获取生成参数（登录相关接口在 passport 域，api 域会 404）
  static const String qrGenerate =
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate';

  /// 二维码登录：轮询结果
  static const String qrPoll =
      'https://passport.bilibili.com/x/passport-login/web/qrcode/poll';

  /// 原作品网页链接
  static String video(String bvid) => '$home/video/$bvid';

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
}