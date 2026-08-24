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
///
/// 使用带容量上限的 LRU 缓存。原实现是无界 Map，会话期间解码后的图片
/// 字节只进不出，导致内存无限增长、GC 停顿与 OOM。
class MxcImageCacheManager {
  /// 缓存总字节数上限（64 MB）。超过后按最近最少使用逐出。
  static const int maxCacheBytes = 64 * 1024 * 1024;

  /// 缓存条目数上限，防止大量小图撑爆entry数量
  static const int maxCacheEntries = 400;

  /// LinkedHashMap 按插入/访问顺序迭代，用于实现 LRU。
  static final Map<String, Uint8List> _imageDataCache = {};

  static int _currentBytes = 0;

  static int get cacheBytes => _currentBytes;

  /// 清除特定缓存键的内存缓存
  static void clearCache(String? cacheKey) {
    if (cacheKey != null) {
      final removed = _imageDataCache.remove(cacheKey);
      if (removed != null) _currentBytes -= removed.lengthInBytes;
    }
  }

  /// 清除包含特定URI的所有内存缓存
  static void clearCacheByUri(Uri? uri) {
    if (uri != null) {
      final keysToRemove = _imageDataCache.keys
          .where((key) => key.contains(uri.toString()))
          .toList();
      for (final key in keysToRemove) {
        clearCache(key);
      }
    }
  }

  /// 清空全部缓存（例如内存告警时可调用）
  static void clearAll() {
    _imageDataCache.clear();
    _currentBytes = 0;
  }

  /// 获取缓存的图片数据（命中会将其标记为最近使用）
  static Uint8List? getData(String? cacheKey) {
    if (cacheKey == null) return null;
    final data = _imageDataCache.remove(cacheKey);
    if (data != null) {
      // 重新插入到末尾 = 最近使用
      _imageDataCache[cacheKey] = data;
    }
    return data;
  }

  /// 返回缓存数据但不改变 LRU 顺序（用于 build 中的高频读取）
  static Uint8List? peekData(String? cacheKey) {
    if (cacheKey == null) return null;
    return _imageDataCache[cacheKey];
  }

  /// 存储图片数据到缓存，并在超出上限时逐出最久未使用的条目
  static void setData(String? cacheKey, Uint8List data) {
    if (cacheKey == null) return;
    final existing = _imageDataCache.remove(cacheKey);
    if (existing != null) _currentBytes -= existing.lengthInBytes;

    // 单张图超过上限的一半就不进缓存，避免一张大图清空整个缓存
    if (data.lengthInBytes > maxCacheBytes ~/ 2) return;

    _imageDataCache[cacheKey] = data;
    _currentBytes += data.lengthInBytes;

    while (_currentBytes > maxCacheBytes ||
        _imageDataCache.length > maxCacheEntries) {
      final oldestKey = _imageDataCache.keys.first;
      final evicted = _imageDataCache.remove(oldestKey);
      if (evicted == null) break;
      _currentBytes -= evicted.lengthInBytes;
    }
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

  /// 加载重试次数上限。原实现无限重试，会堆积大量永久后台任务。
  static const int _maxRetries = 5;

  int _retryCount = 0;

  void _tryLoad(_) async {
    if (_imageData != null) {
      return;
    }
    try {
      await _load();
      _retryCount = 0;
    } on IOException catch (_) {
      if (!mounted) return;
      if (_retryCount >= _maxRetries) return;
      _retryCount++;
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
    
    // 当URI变化时，重新加载图片（包括从null到有值，或从有值到null的情况）
    final oldUri = oldWidget.uri;
    final newUri = widget.uri;
    
    // 检查URI是否发生变化（包括从null到有值或从有值到null）
    final uriChanged = (oldUri == null && newUri != null) || 
                       (oldUri != null && newUri == null) ||
                       (oldUri != null && newUri != null && oldUri.toString() != newUri.toString());
                       
    // 检查key或缓存键是否发生变化
    final keyChanged = widget.key != oldWidget.key;
    final cacheKeyChanged = widget.cacheKey != oldWidget.cacheKey;
    
    if (uriChanged || keyChanged || cacheKeyChanged) {
      // 注意：不再在此处清除缓存。缓存是多个组件共享的（例如同一尺寸的同
      // 一头像），随意清除会导致其他组件被迫重新下载/解码，反而造成卡顿。
      // 过期条目交由 LRU 自然逐出即可。
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
              // 避免重建（例如滚动出屏再回屏）时图片闪烁
              gaplessPlayback: true,
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
