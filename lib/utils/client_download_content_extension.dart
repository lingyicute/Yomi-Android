import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:matrix/matrix.dart';

import 'package:yomi/widgets/mxc_image.dart';

// 全局缓存清理函数，避免扩展方法问题
Future<void> clearAvatarCache(Client client, Uri? mxc) async {
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
  } catch (e) {
    // 忽略错误，不影响流程
  }
}

// 强制刷新头像的全局函数
Future<Uint8List?> forceRefreshAvatar(Client client, Uri? mxc, {double size = 110}) async {
  if (mxc == null) return null;
  
  try {
    // 清除缓存
    await clearAvatarCache(client, mxc);
    
    // 重新下载头像
    return await client.downloadMxcCached(
      mxc,
      width: size,
      height: size,
      isThumbnail: true,
    );
  } catch (e) {
    return null;
  }
}

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
}
