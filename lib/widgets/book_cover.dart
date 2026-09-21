import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/network/api_config.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';

/// 圆角封面图（带占位/失败态）
class BookCover extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const BookCover({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  /// 归一化封面地址：强制 https（http 图源会被 Android 拦截，造成封面空白）
  static String normalize(String input) => Book.normalizePic(input);

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius;
    final src = normalize(url);
    return ClipRRect(
      borderRadius: radius,
      child: src.isEmpty
          ? _fallback()
          : CachedNetworkImage(
              imageUrl: src,
              width: width,
              height: height,
              fit: BoxFit.cover,
              httpHeaders: const {
                'User-Agent': BiliEndpoints.userAgent,
                'Referer': BiliEndpoints.home,
              },
              placeholder: (_, _) => Container(
                width: width,
                height: height,
                color: AppTheme.surfaceHigh,
                child:  Icon(
                  Icons.menu_book_outlined,
                  color: AppTheme.textHint,
                ),
              ),
              errorWidget: (_, _, _) => _fallback(),
            ),
    );
  }

  Widget _fallback() => Container(
        width: width,
        height: height,
        color: AppTheme.surfaceHigh,
        alignment: Alignment.center,
        child:  Icon(
          Icons.menu_book_outlined,
          color: AppTheme.textHint,
          size: 32,
        ),
      );
}