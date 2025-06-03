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
    
    try {
      // 清除原始文件缓存
      // 注意：Matrix SDK没有removeFile方法，使用deleteFile代替
      if (database?.supportFileStoring == true) {
        await database?.deleteFile(mxc.toString());
      }
      
      // 清除内存缓存
      MxcImageCacheManager.clearCacheByUri(mxc);
    } catch (e) {
      // 忽略错误，不影响流程
    }
  }

  /// 重新下载头像以确保它已刷新
  Future<Uint8List?> forceRefreshAvatar(Uri? mxc, {double size = 110}) async {
    if (mxc == null) return null;
    
    try {
      // 清除缓存
      await clearAvatarCache(mxc);
      
      // 只重新下载一次，不需要多个尺寸
      return await downloadMxcCached(
        mxc,
        width: size,
        height: size,
        isThumbnail: true,
      );
    } catch (e) {
      return null;
    }
  }
}
