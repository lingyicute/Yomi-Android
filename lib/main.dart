import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yomi/config/app_config.dart';
import 'package:yomi/utils/client_manager.dart';
import 'package:yomi/utils/platform_infos.dart';
import 'package:yomi/widgets/error_widget.dart';
import 'config/setting_keys.dart';
import 'utils/background_push.dart';
import 'widgets/lyi_chat_app.dart';

void main() async {
  Logs().i('Welcome to ${AppConfig.applicationName} <3');

  // Our background push shared isolate accesses flutter-internal things very early in the startup proccess
  // To make sure that the parts of flutter needed are started up already, we need to ensure that the
  // widget bindings are initialized already.
  WidgetsFlutterBinding.ensureInitialized();

  Logs().nativeColors = !PlatformInfos.isIOS;
  final store = await SharedPreferences.getInstance();
  final clients = await ClientManager.getClients(store: store);

  // If the app starts in detached mode, a native component (the persistent
  // foreground service, boot receiver or watchdog) woke the Flutter engine
  // to keep Matrix /sync running without Firebase / ntfy.
  if (PlatformInfos.isAndroid &&
      AppLifecycleState.detached == WidgetsBinding.instance.lifecycleState) {
    // Do not send online presences when the UI is not visible.
    for (final client in clients) {
      client.syncPresence = PresenceType.offline;
    }

    final push = BackgroundPush.clientsOnly(clients);
    unawaited(push.setupPush());
    // Start the GUI once the user actually opens the activity.
    WidgetsBinding.instance.addObserver(AppStarter(clients, store));
    Logs().i(
      '${AppConfig.applicationName} started in background-sync mode. No GUI will be created unless the app is no longer detached.',
    );
    return;
  }

  // Started in foreground mode.
  Logs().i(
    '${AppConfig.applicationName} started in foreground mode. Rendering GUI...',
  );
  await startGui(clients, store);
}

/// Fetch the pincode for the applock and start the flutter engine.
Future<void> startGui(List<Client> clients, SharedPreferences store) async {
  // Fetch the pin for the applock if existing for mobile applications.
  String? pin;
  if (PlatformInfos.isMobile) {
    try {
      pin =
          await const FlutterSecureStorage().read(key: SettingKeys.appLockKey);
    } catch (e, s) {
      Logs().d('Unable to read PIN from Secure storage', e, s);
    }
  }

  // Do not block the first frame on the full initial sync: the chat list and
  // timeline already await `roomsLoading` / `accountDataLoading` themselves
  // and render loading states until then. Previously cold starts on accounts
  // with many rooms showed a blank screen for seconds.
  ErrorWidget.builder = (details) => YomiErrorWidget(details);
  runApp(YomiApp(clients: clients, pincode: pin, store: store));
}

/// Watches the lifecycle changes to start the application when it
/// is no longer detached.
class AppStarter with WidgetsBindingObserver {
  final List<Client> clients;
  final SharedPreferences store;
  bool guiStarted = false;

  AppStarter(this.clients, this.store);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (guiStarted) return;
    if (state == AppLifecycleState.detached) return;

    Logs().i(
      '${AppConfig.applicationName} switches from the detached background-sync mode to ${state.name} mode. Rendering GUI...',
    );
    // The local /sync loop is owned by BackgroundPush; only flip presence.
    for (final client in clients) {
      client.syncPresence =
          state == AppLifecycleState.resumed ? null : PresenceType.unavailable;
    }
    startGui(clients, store);
    // We must make sure that the GUI is only started once.
    guiStarted = true;
  }
}
