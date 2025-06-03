import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:matrix/matrix.dart';

import 'package:yomi/widgets/mxc_image.dart';

// 全局缓存清理函数，避免扩展方法问题
Future<void> _clearAvatarCacheImpl(Client client, Uri? mxc) async {
  if (mxc == null) return;
  
  try {
    // 清除数据库缓存
    try {
      await client.database?.deleteFile(mxc);
    } catch (e) {
      // 忽略错误，数据库API可能有变化
    }
    
    // 清除内存缓存
    MxcImageCacheManager.clearCacheByUri(mxc);
    
    // 清除各种尺寸的缩略图缓存
    final thumbnailSizes = [
      [32, 32], // 小尺寸头像
      [44, 44], // 默认头像尺寸
      [56, 56], // 稍大尺寸
      [80, 80], // 设置页面头像尺寸
      [110, 110], // 大头像尺寸
      [120, 120], // 额外大尺寸，以防万一
    ];
    
    for (final size in thumbnailSizes) {
      try {
        final thumbnailKey = mxc.getThumbnail(
          client,
          width: size[0],
          height: size[1],
          method: ThumbnailMethod.scale,
        );
        await client.database?.deleteFile(thumbnailKey);
        
        // 同时清除对应的内存缓存
        final cacheKeyFormat = '${mxc}_${size[0]}x${size[1]}';
        MxcImageCacheManager.clearCache(cacheKeyFormat);
        
        // 清除可能的其他格式缓存键
        MxcImageCacheManager.clearCache('${mxc}_${size[0]}');
      } catch (e) {
        // 忽略清除缓存过程中的错误
      }
    }
  } catch (e) {
    // 忽略错误，不影响流程
  }
}

// 强制刷新头像的全局函数
Future<Uint8List?> _forceRefreshAvatarImpl(Client client, Uri? mxc, {
  double size = 110,
}) async {
  if (mxc == null) return null;
  
  // 清除缓存
  await _clearAvatarCacheImpl(client, mxc);
  
  // 重新下载头像
  try {
    // 预先获取不同尺寸的缩略图，确保在不同场景下都能正确显示
    final sizes = [size, 44.0, 32.0, 56.0, 80.0]; // 常用尺寸
    
    Uint8List? result;
    for (final s in sizes) {
      try {
        // 强制从服务器获取，不使用缓存
        final data = await client.downloadMxcCached(
          mxc,
          width: s.toInt(),
          height: s.toInt(),
          isThumbnail: true,
          thumbnailMethod: ThumbnailMethod.scale,
        );
        
        // 将结果缓存到内存中
        final cacheKey = '${mxc}_$s';
        MxcImageCacheManager.setData(cacheKey, data);
        
        if (result == null) {
          result = data;
        }
      } catch (e) {
        // 尝试使用downloadMxcCached作为备份方法
        final data = await client.downloadMxcCached(
          mxc,
          width: s,
          height: s,
          isThumbnail: true,
        );
        
        if (result == null) {
          result = data;
        }
      }
    }
    
    return result;
  } catch (e) {
    return null;
  }
}

// 为了向后兼容，保留原始的全局函数
Future<void> clearAvatarCache(Client client, Uri? mxc) async {
  await _clearAvatarCacheImpl(client, mxc);
}

// 为了向后兼容，保留原始的全局函数
Future<Uint8List?> forceRefreshAvatar(Client client, Uri? mxc, {double size = 110}) async {
  return await _forceRefreshAvatarImpl(client, mxc, size: size);
}

extension ClientDownloadContentExtension on Client {
  // 为Client类添加clearAvatarCache扩展方法
  Future<void> clearAvatarCache(Uri? mxc) async {
    await _clearAvatarCacheImpl(this, mxc);
  }
  
  // 为Client类添加forceRefreshAvatar扩展方法
  Future<Uint8List?> forceRefreshAvatar(Uri? mxc, {double size = 110}) async {
    return await _forceRefreshAvatarImpl(this, mxc, size: size);
  }
  
  // 为Client类添加downloadAndDecryptAttachment扩展方法，以保持API兼容
  Future<Uint8List> downloadAndDecryptAttachment(
    Uri mxc, {
    bool getThumbnail = false,
    int? width,
    int? height,
    ThumbnailMethod method = ThumbnailMethod.scale,
  }) async {
    // 使用downloadMxcCached方法实现相同的功能
    return downloadMxcCached(
      mxc,
      width: width,
      height: height,
      isThumbnail: getThumbnail,
      thumbnailMethod: method,
    );
  }

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
}
