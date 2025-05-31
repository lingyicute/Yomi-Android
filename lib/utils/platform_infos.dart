import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:yomi/l10n/l10n.dart';
import '../config/app_config.dart';

abstract class PlatformInfos {
  static bool get isWeb => kIsWeb;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static bool get isCupertinoStyle => isIOS || isMacOS;

  static bool get isMobile => isAndroid || isIOS;

  /// For desktops which don't support ChachedNetworkImage yet
  static bool get isBetaDesktop => isWindows || isLinux;

  static bool get isDesktop => isLinux || isWindows || isMacOS;

  static bool get usesTouchscreen => !isMobile;

  static bool get supportsVideoPlayer =>
      !PlatformInfos.isWindows && !PlatformInfos.isLinux;

  /// Web could also record in theory but currently only wav which is too large
  static bool get platformCanRecord => (isMobile || isMacOS);

  static String get clientName =>
      '${AppConfig.applicationName} ${isWeb ? 'web' : Platform.operatingSystem}${kReleaseMode ? '' : 'Debug'}';

  static Future<String> getVersion() async {
    var version = kIsWeb ? 'Web' : 'Unknown';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    return version;
  }

  static void showAboutAppDialog(BuildContext context) async {
    final version = await PlatformInfos.getVersion();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                Center(
                  child: SvgPicture.asset(
                    'assets/logo.svg',
                    width: 64,
                    height: 64,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    AppConfig.applicationName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Center(
                  child: Text('版本: $version'),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => launchUrlString(AppConfig.sourceCodeUrl),
                  icon: const Icon(Icons.source_outlined),
                  label: Text(L10n.of(context).sourceCode),
                ),
                TextButton.icon(
                  onPressed: () {
                    context.go('/logs');
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.list_outlined),
                  label: const Text('日志'),
                ),
                TextButton.icon(
                  onPressed: () {
                    context.go('/configs');
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.settings_applications_outlined),
                  label: const Text('调试选项'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}