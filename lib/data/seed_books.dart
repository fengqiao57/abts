import 'package:flutter/material.dart';

/// 发现页分类与精选主播（本地种子数据，确保无网络时也有内容可看）
class DiscoverCategory {
  final String label;
  final String keyword;
  final IconData icon;
  final List<AnchorPick> anchors;

  const DiscoverCategory({
    required this.label,
    required this.keyword,
    required this.icon,
    required this.anchors,
  });
}

/// 一位主播/剧社：点击后查看 TA 相关的有声小说
class AnchorPick {
  final String name;
  final String works;
  final String keyword;
  final Color color;

  const AnchorPick({
    required this.name,
    required this.works,
    required this.keyword,
    this.color = const Color(0xFFFB7299),
  });
}

class DiscoverSeeds {
  DiscoverSeeds._();

  static const List<DiscoverCategory> categories = [
    DiscoverCategory(
      label: '热门推荐',
      keyword: '有声小说',
      icon: Icons.local_fire_department_rounded,
      anchors: [
        AnchorPick(
          name: '周建龙',
          works: '鬼吹灯 · 盗墓笔记',
          keyword: '周建龙 有声小说',
          color: Color(0xFF4E5C7A),
        ),
        AnchorPick(
          name: '紫襟',
          works: '十宗罪 · 心理罪',
          keyword: '紫襟 有声小说',
          color: Color(0xFF6B2E2E),
        ),
        AnchorPick(
          name: '王明军',
          works: '三体 · 白鹿原',
          keyword: '王明军 有声小说',
          color: Color(0xFF2E5C8F),
        ),
        AnchorPick(
          name: '艾宝良',
          works: '午夜恐怖故事',
          keyword: '艾宝良 有声小说',
          color: Color(0xFF3B3B6B),
        ),
        AnchorPick(
          name: '李野默',
          works: '平凡的世界',
          keyword: '李野默 有声小说',
          color: Color(0xFF2E6B4E),
        ),
        AnchorPick(
          name: '青雪',
          works: '悬疑 · 盗墓',
          keyword: '青雪 有声小说',
          color: Color(0xFF5C4E8F),
        ),
      ],
    ),
    DiscoverCategory(
      label: '广播剧',
      keyword: '广播剧 全集',
      icon: Icons.headset_rounded,
      anchors: [
        AnchorPick(
          name: '光合积木',
          works: '默读 · 破云',
          keyword: '光合积木 广播剧',
          color: Color(0xFF3B6BB2),
        ),
        AnchorPick(
          name: '音熊联萌',
          works: '魔道祖师',
          keyword: '音熊联萌 广播剧',
          color: Color(0xFFB23B8F),
        ),
        AnchorPick(
          name: '729声工场',
          works: '杀破狼 · 全职高手',
          keyword: '729声工场 广播剧',
          color: Color(0xFF4E8F5C),
        ),
        AnchorPick(
          name: '边江工作室',
          works: '盗墓笔记',
          keyword: '边江工作室 广播剧',
          color: Color(0xFFB24E3B),
        ),
        AnchorPick(
          name: '北斗企鹅',
          works: '一人之下 · 全职高手',
          keyword: '北斗企鹅 广播剧',
          color: Color(0xFF6B4E8F),
        ),
        AnchorPick(
          name: '冠声文化',
          works: '天官赐福 · 撒野',
          keyword: '冠声文化 广播剧',
          color: Color(0xFF2E8F8F),
        ),
      ],
    ),
    DiscoverCategory(
      label: '评书',
      keyword: '评书 单田芳',
      icon: Icons.record_voice_over_rounded,
      anchors: [
        AnchorPick(
          name: '单田芳',
          works: '隋唐演义 · 白眉大侠',
          keyword: '单田芳 评书',
          color: Color(0xFF8F5C2E),
        ),
        AnchorPick(
          name: '刘兰芳',
          works: '岳飞传 · 杨家将',
          keyword: '刘兰芳 评书',
          color: Color(0xFF8F2E2E),
        ),
        AnchorPick(
          name: '袁阔成',
          works: '三国演义',
          keyword: '袁阔成 评书',
          color: Color(0xFF2E5C8F),
        ),
        AnchorPick(
          name: '田连元',
          works: '水浒传 · 小八义',
          keyword: '田连元 评书',
          color: Color(0xFF2E8F5C),
        ),
        AnchorPick(
          name: '王玥波',
          works: '聊斋 · 大隋唐',
          keyword: '王玥波 评书',
          color: Color(0xFF6B5C2E),
        ),
        AnchorPick(
          name: '连丽如',
          works: '东汉演义 · 三国',
          keyword: '连丽如 评书',
          color: Color(0xFF8F4E6B),
        ),
      ],
    ),
    DiscoverCategory(
      label: '相声',
      keyword: '相声 德云社',
      icon: Icons.theater_comedy_rounded,
      anchors: [
        AnchorPick(
          name: '郭德纲',
          works: '德云社 · 单口相声',
          keyword: '郭德纲 相声',
          color: Color(0xFF8F6B6B),
        ),
        AnchorPick(
          name: '于谦',
          works: '德云社 · 捧哏',
          keyword: '郭德纲于谦 相声',
          color: Color(0xFF6B4E8F),
        ),
        AnchorPick(
          name: '岳云鹏',
          works: '德云社 · 五环之歌',
          keyword: '岳云鹏 相声',
          color: Color(0xFF4E8F8F),
        ),
        AnchorPick(
          name: '马三立',
          works: '传统相声',
          keyword: '马三立 相声',
          color: Color(0xFF8F8F4E),
        ),
        AnchorPick(
          name: '侯宝林',
          works: '相声大师',
          keyword: '侯宝林 相声',
          color: Color(0xFF5C6B8F),
        ),
        AnchorPick(
          name: '高峰',
          works: '德云社 · 传统活',
          keyword: '高峰 相声',
          color: Color(0xFF8F5C4E),
        ),
      ],
    ),
    DiscoverCategory(
      label: '悬疑',
      keyword: '悬疑有声小说',
      icon: Icons.psychology_rounded,
      anchors: [
        AnchorPick(
          name: '紫襟',
          works: '十宗罪 · 心理罪',
          keyword: '紫襟 悬疑 有声小说',
          color: Color(0xFF6B2E2E),
        ),
        AnchorPick(
          name: '周建龙',
          works: '鬼吹灯 · 谜踪之国',
          keyword: '周建龙 悬疑 有声小说',
          color: Color(0xFF3B6B4E),
        ),
        AnchorPick(
          name: '青雪',
          works: '悬疑 · 盗墓',
          keyword: '青雪 有声小说',
          color: Color(0xFF3B3B6B),
        ),
        AnchorPick(
          name: '艾宝良',
          works: '午夜讲鬼故事',
          keyword: '艾宝良 有声小说',
          color: Color(0xFF5C4E8F),
        ),
        AnchorPick(
          name: '张震',
          works: '张震讲故事',
          keyword: '张震讲故事 有声小说',
          color: Color(0xFF2E4E6B),
        ),
        AnchorPick(
          name: '刘琮',
          works: '悬疑 · 科幻',
          keyword: '刘琮 有声小说',
          color: Color(0xFF6B3B4E),
        ),
      ],
    ),
    DiscoverCategory(
      label: '玄幻仙侠',
      keyword: '玄幻小说听书',
      icon: Icons.auto_fix_high_rounded,
      anchors: [
        AnchorPick(
          name: '大斌',
          works: '遮天 · 完美世界',
          keyword: '大斌 有声小说',
          color: Color(0xFF4E6B8F),
        ),
        AnchorPick(
          name: '桑梓',
          works: '斗破苍穹',
          keyword: '桑梓 有声小说',
          color: Color(0xFFB24E3B),
        ),
        AnchorPick(
          name: '头陀渊',
          works: '凡人修仙传',
          keyword: '头陀渊 有声小说',
          color: Color(0xFF3B8F6B),
        ),
        AnchorPick(
          name: '牛大宝',
          works: '都市 · 玄幻',
          keyword: '牛大宝 有声小说',
          color: Color(0xFF8F6B2E),
        ),
        AnchorPick(
          name: '周建龙',
          works: '鬼吹灯',
          keyword: '周建龙 有声小说',
          color: Color(0xFF4E8FB2),
        ),
        AnchorPick(
          name: '紫襟',
          works: '玄幻 · 都市',
          keyword: '紫襟 玄幻 有声小说',
          color: Color(0xFF6B2E5C),
        ),
      ],
    ),
    DiscoverCategory(
      label: '名著悦读',
      keyword: '世界名著朗读',
      icon: Icons.auto_stories_rounded,
      anchors: [
        AnchorPick(
          name: '李野默',
          works: '平凡的世界',
          keyword: '李野默 朗读',
          color: Color(0xFFB26B8F),
        ),
        AnchorPick(
          name: '王明军',
          works: '三体 · 白鹿原',
          keyword: '王明军 朗读',
          color: Color(0xFFB28F4E),
        ),
        AnchorPick(
          name: '徐涛',
          works: '世界名著',
          keyword: '徐涛 朗读',
          color: Color(0xFF6B8F4E),
        ),
        AnchorPick(
          name: '李立宏',
          works: '舌尖上的中国',
          keyword: '李立宏 朗读',
          color: Color(0xFF8F4E8F),
        ),
        AnchorPick(
          name: '艾宝良',
          works: '经典文学',
          keyword: '艾宝良 朗读',
          color: Color(0xFF4E8F6B),
        ),
        AnchorPick(
          name: '方明',
          works: '经典散文',
          keyword: '方明 朗读',
          color: Color(0xFF5C6B4E),
        ),
      ],
    ),
  ];

  static const List<String> hotKeys = [
    '三体',
    '盗墓笔记',
    '鬼吹灯',
    '单田芳评书',
    '郭德纲相声',
    '有声小说',
  ];
}

/// 主播头像底色（按序取色）
Color seedColorRole(int i, List<Color> palette) => palette[i % palette.length];
