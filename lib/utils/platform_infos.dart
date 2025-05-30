import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

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

  static void showDialog(BuildContext context) async {
    final version = await PlatformInfos.getVersion();

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 上方空白
                const SizedBox(height: 24),
                // 图标居中显示
                Center(
                  child: Image.asset(
                    'assets/logo.png',
                    width: 64,
                    height: 64,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(height: 16),
                // 应用名称
                Center(
                  child: Text(
                    AppConfig.applicationName,
                    style: Theme.of(context).textTheme.headline6,
                  ),
                ),
                const SizedBox(height: 8),
                // 版本号
                Center(
                  child: Text(
                    'Version: $version',
                    style: Theme.of(context).textTheme.bodyText2,
                  ),
                ),
                const SizedBox(height: 24),
                // 底部按钮区域
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        launchUrlString(AppConfig.sourceCodeUrl);
                      },
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
                const SizedBox(height: 8),
                // 关闭按钮
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
