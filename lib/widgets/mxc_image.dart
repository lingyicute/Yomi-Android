import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:yomi/config/themes.dart';
import 'package:yomi/utils/client_download_content_extension.dart';
import 'package:yomi/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:yomi/widgets/matrix.dart';

/// 用于管理MXC图像内存缓存的工具类
class MxcImageCacheManager {
  static final Map<String, Uint8List> _imageDataCache = {};
  
  /// 清除特定缓存键的内存缓存
  static void clearCache(String? cacheKey) {
    if (cacheKey != null) {
      _imageDataCache.remove(cacheKey);
    }
  }
  
  /// 清除包含特定URI的所有内存缓存
  static void clearCacheByUri(Uri? uri) {
    if (uri != null) {
      final keysToRemove = _imageDataCache.keys
          .where((key) => key.contains(uri.toString()))
          .toList();
      for (final key in keysToRemove) {
        _imageDataCache.remove(key);
      }
    }
  }
  
  /// 获取缓存的图片数据
  static Uint8List? getData(String? cacheKey) {
    if (cacheKey == null) return null;
    return _imageDataCache[cacheKey];
  }
  
  /// 存储图片数据到缓存
  static void setData(String? cacheKey, Uint8List data) {
    if (cacheKey == null) return;
    _imageDataCache[cacheKey] = data;
  }
}

class MxcImage extends StatefulWidget {
  final Uri? uri;
  final Event? event;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final bool isThumbnail;
  final bool animated;
  final Duration retryDuration;
  final Duration animationDuration;
  final Curve animationCurve;
  final ThumbnailMethod thumbnailMethod;
  final Widget Function(BuildContext context)? placeholder;
  final String? cacheKey;
  final Client? client;

  const MxcImage({
    this.uri,
    this.event,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.isThumbnail = true,
    this.animated = false,
    this.animationDuration = LyiThemes.animationDuration,
    this.retryDuration = const Duration(seconds: 2),
    this.animationCurve = LyiThemes.animationCurve,
    this.thumbnailMethod = ThumbnailMethod.scale,
    this.cacheKey,
    this.client,
    super.key,
  });

  @override
  State<MxcImage> createState() => _MxcImageState();
}

class _MxcImageState extends State<MxcImage> {
  Uint8List? _imageDataNoCache;

  Uint8List? get _imageData => widget.cacheKey == null
      ? _imageDataNoCache
      : MxcImageCacheManager.getData(widget.cacheKey);

  set _imageData(Uint8List? data) {
    if (data == null) return;
    final cacheKey = widget.cacheKey;
    cacheKey == null
        ? _imageDataNoCache = data
        : MxcImageCacheManager.setData(cacheKey, data);
  }

  Future<void> _load() async {
    final client =
        widget.client ?? widget.event?.room.client ?? Matrix.of(context).client;
    final uri = widget.uri;
    final event = widget.event;

    if (uri != null) {
      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final width = widget.width;
      final realWidth = width == null ? null : width * devicePixelRatio;
      final height = widget.height;
      final realHeight = height == null ? null : height * devicePixelRatio;

      final remoteData = await client.downloadMxcCached(
        uri,
        width: realWidth,
        height: realHeight,
        thumbnailMethod: widget.thumbnailMethod,
        isThumbnail: widget.isThumbnail,
        animated: widget.animated,
      );
      if (!mounted) return;
      setState(() {
        _imageData = remoteData;
      });
    }

    if (event != null) {
      final data = await event.downloadAndDecryptAttachment(
        getThumbnail: widget.isThumbnail,
      );
      if (data.detectFileType is MatrixImageFile || widget.isThumbnail) {
        if (!mounted) return;
        setState(() {
          _imageData = data.bytes;
        });
        return;
      }
    }
  }

  void _tryLoad(_) async {
    if (_imageData != null) {
      return;
    }
    try {
      await _load();
    } on IOException catch (_) {
      if (!mounted) return;
      await Future.delayed(widget.retryDuration);
      _tryLoad(_);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_tryLoad);
  }
  
  @override
  void didUpdateWidget(MxcImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 当URI变化或key变化时，重新加载图片
    final uriChanged = oldWidget.uri?.toString() != widget.uri?.toString();
    final keyChanged = oldWidget.key != widget.key;
    
    if (uriChanged || keyChanged) {
      // 清除非缓存数据
      _imageDataNoCache = null;
      
      // 重新加载图片
      WidgetsBinding.instance.addPostFrameCallback(_tryLoad);
    }
  }

  Widget placeholder(BuildContext context) =>
      widget.placeholder?.call(context) ??
      Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
      );

  @override
  Widget build(BuildContext context) {
    final data = _imageData;
    final hasData = data != null && data.isNotEmpty;

    return AnimatedCrossFade(
      crossFadeState:
          hasData ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 100),
      firstChild: placeholder(context),
      secondChild: hasData
          ? Image.memory(
              data,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              filterQuality:
                  widget.isThumbnail ? FilterQuality.low : FilterQuality.medium,
              errorBuilder: (context, e, s) {
                Logs().d('Unable to render mxc image', e, s);
                return SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: min(widget.height ?? 64, 64),
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                );
              },
            )
          : SizedBox(
              width: widget.width,
              height: widget.height,
            ),
    );
  }
}
