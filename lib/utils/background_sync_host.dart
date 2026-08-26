import 'dart:async';

import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import 'package:yomi/utils/platform_infos.dart';

/// Native bridge for the Android foreground service that keeps `/sync` alive.
class BackgroundSyncHost {
  static const MethodChannel _channel =
      MethodChannel('chat.lyi.yomi/background_sync');

  static Future<void> start() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start');
    } catch (e, s) {
      Logs().w('[Push] Unable to start native background sync service', e, s);
    }
  }

  static Future<void> stop() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e, s) {
      Logs().w('[Push] Unable to stop native background sync service', e, s);
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!PlatformInfos.isAndroid) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } catch (e, s) {
      Logs().w('[Push] Unable to query battery optimization state', e, s);
      return false;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!PlatformInfos.isAndroid) return true;
    try {
      return await _channel
              .invokeMethod<bool>('requestIgnoreBatteryOptimizations') ??
          false;
    } catch (e, s) {
      Logs().w('[Push] Unable to request battery optimization exemption', e, s);
      return false;
    }
  }

  static Future<bool> openAutostartSettings() async {
    if (!PlatformInfos.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAutostartSettings') ??
          false;
    } catch (e, s) {
      Logs().w('[Push] Unable to open OEM autostart settings', e, s);
      return false;
    }
  }
}
