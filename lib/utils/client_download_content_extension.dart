import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:matrix/matrix.dart';

import 'package:yomi/widgets/mxc_image.dart';

extension ClientDownloadContentExtension on Client {
  Future<Uint8List> downloadMxcCached(
    Uri mxc, {
    num? width,
    num? height,
    bool isThumbnail = false,
    bool? animated,
    ThumbnailMethod? thumbnailMethod,
    bool rounded = false,
  }) async {
    // To stay compatible with previous storeKeys:
    final cacheKey = isThumbnail
        // ignore: deprecated_member_use
        ? mxc.getThumbnail(
            this,
            width: width,
            height: height,
            animated: animated,
            method: thumbnailMethod!,
          )
        : mxc;

    final cachedData = await database?.getFile(cacheKey);
    if (cachedData != null) return cachedData;

    final httpUri = isThumbnail
        ? await mxc.getThumbnailUri(
            this,
            width: width,
            height: height,
            animated: animated,
            method: thumbnailMethod,
          )
        : await mxc.getDownloadUri(this);

    final response = await httpClient.get(
      httpUri,
      headers:
          accessToken == null ? null : {'authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      throw Exception();
    }
    var imageData = response.bodyBytes;

    if (rounded) {
      final image = decodeImage(imageData);
      if (image != null) {
        imageData = encodePng(copyCropCircle(image));
      }
    }

    await database?.storeFile(cacheKey, imageData, 0);

    return imageData;
  }

  /// 清除与给定mxc URI相关的缓存
  /// 在头像更新后调用此方法可以确保头像更新后立即显示
  Future<void> clearAvatarCache(Uri? mxc) async {
    if (mxc == null) return;
    
    // 清除原始文件缓存
    await database?.removeFile(mxc);
    
    // 清除内存缓存
    MxcImageCacheManager.clearCacheByUri(mxc);
    
    // 清除各种尺寸的缩略图缓存
    final thumbnailSizes = [
      [32, 32], // 小尺寸头像
      [44, 44], // 默认头像尺寸
      [56, 56], // 稍大尺寸
      [80, 80], // 设置页面头像尺寸
      [110, 110], // 大头像尺寸
    ];
    
    for (final size in thumbnailSizes) {
      final thumbnailKey = mxc.getThumbnail(
        this,
        width: size[0],
        height: size[1],
        method: ThumbnailMethod.scale,
      );
      await database?.removeFile(thumbnailKey);
      
      // 同时清除对应的内存缓存
      final cacheKeyFormat = '${mxc}_${size[0]}x${size[1]}';
      MxcImageCacheManager.clearCache(cacheKeyFormat);
    }
  }

  /// 强制刷新头像
  /// 用于确保新头像能立即显示出来
  Future<Uint8List?> forceRefreshAvatar(Uri? mxc, {
    double size = 110,
  }) async {
    if (mxc == null) return null;
    
    // 清除缓存
    await clearAvatarCache(mxc);
    
    // 重新下载头像
    try {
      // 预先获取不同尺寸的缩略图，确保在不同场景下都能正确显示
      final sizes = [size, 44.0, 32.0]; // 常用尺寸
      
      Uint8List? result;
      for (final s in sizes) {
        final data = await downloadMxcCached(
          mxc,
          width: s,
          height: s,
          isThumbnail: true,
        );
        if (result == null) {
          result = data;
        }
      }
      
      return result;
    } catch (e) {
      return null;
    }
  }
}
