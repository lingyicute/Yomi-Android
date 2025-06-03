import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:yomi/config/app_config.dart';
import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:yomi/widgets/layouts/login_scaffold.dart';
import 'package:yomi/widgets/matrix.dart';
import '../../config/themes.dart';
import 'homeserver_picker.dart';

class HomeserverPickerView extends StatelessWidget {
  final HomeserverPickerController controller;

  const HomeserverPickerView(
    this.controller, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LoginScaffold(
      enforceMobileMode: Matrix.of(context).client.isLogged(),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          controller.widget.addMultiAccount
              ? L10n.of(context).addAccount
              : L10n.of(context).login,
        ),
        actions: [
          PopupMenuButton<MoreLoginActions>(
            useRootNavigator: true,
            onSelected: controller.onMoreAction,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: MoreLoginActions.importBackup,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.import_export_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).hydrate),
                  ],
                ),
              ),
              PopupMenuItem(
                value: MoreLoginActions.about,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).about),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  // display a prominent banner to import session for TOR browser
                  // users. This feature is just some UX sugar as TOR users are
                  // usually forced to logout as TOR browser is non-persistent
                  const SizedBox(height: 24),
                  AnimatedContainer(
                    height: controller.isTorBrowser ? 64 : 0,
                    duration: LyiThemes.animationDuration,
                    curve: LyiThemes.animationCurve,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: Material(
                      clipBehavior: Clip.hardEdge,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(8),
                      ),
                      color: theme.colorScheme.surface,
                      child: ListTile(
                        leading: const Icon(Icons.vpn_key),
                        title: Text(L10n.of(context).hydrateTor),
                        subtitle: Text(L10n.of(context).hydrateTorLong),
                        trailing: const Icon(Icons.chevron_right_outlined),
                        onTap: controller.restoreBackup,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
                    child: Hero(
                      tag: 'info-logo',
                      child: Image.asset(
                        './assets/logo.png',
                        fit: BoxFit.contain,
                        width: 120,
                        height: 120,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: SelectableLinkify(
                      text: L10n.of(context).appIntroduction,
                      textScaleFactor:
                          MediaQuery.textScalerOf(context).scale(1),
                      textAlign: TextAlign.center,
                      linkStyle: TextStyle(
                        color: theme.colorScheme.secondary,
                        decorationColor: theme.colorScheme.secondary,
                      ),
                      onOpen: (link) => launchUrlString(link.url),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: MediaQuery.of(context).size.width > 400 ? 200 : double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: controller.isLoading
                                ? null
                                : controller.checkHomeserverAction,
                            child: controller.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '让我们开始吧',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_rounded, size: 18),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
