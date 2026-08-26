import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yomi/config/app_config.dart';
import 'package:yomi/config/setting_keys.dart';
import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/utils/client_manager.dart';
import 'package:yomi/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:yomi/utils/platform_infos.dart';

/// The interval is deliberately short so a message can be delivered without a
/// Google/UnifiedPush distributor. This requires a foreground service: Android
/// does not permit normal background work at a 20-second cadence.
const backgroundSyncInterval = Duration(seconds: 20);

/// Starts the Android foreground service used as the non-Google push fallback.
///
/// The service owns a second, background-only Matrix client. It restores the
/// encrypted database and uses one-shot syncs, so it also works after Android
/// has killed the UI process. A visible foreground notification is required by
/// Android and makes the battery cost explicit to the user.
class BackgroundSync {
  static Future<void> startIfEnabled() async {
    if (!PlatformInfos.isAndroid) return;

    final store = await SharedPreferences.getInstance();
    if (!AppSettings.enableBackgroundSync.getItem(store)) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: const AndroidNotificationOptions(
        channelId: 'yomi_background_sync',
        channelName: 'Yomi background connection',
        channelDescription: 'Keeps Yomi connected for new messages',
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        interval: backgroundSyncInterval.inMilliseconds,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    // Android 13+ requires this before it can show the mandatory service
    // notification. If denied, starting the service is still attempted; the
    // platform may show it in the task manager only.
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) return;

    final started = await FlutterForegroundTask.startService(
      notificationTitle: AppConfig.applicationName,
      notificationText: 'Background connection is active',
      callback: startBackgroundSyncService,
    );
    if (!started) {
      Logs().w('[BackgroundSync] Android refused to start foreground service');
    }
  }

  static Future<void> stop() async {
    if (PlatformInfos.isAndroid &&
        await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

/// Entry point invoked by the foreground-service Flutter engine. Do not move
/// this into a class: Android starts this isolate after a process restart.
@pragma('vm:entry-point')
void startBackgroundSyncService() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_BackgroundSyncTask());
}

class _BackgroundSyncTask extends TaskHandler {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final List<Client> _clients = [];
  final List<StreamSubscription<Event>> _notificationSubscriptions = [];
  bool _syncing = false;
  bool _ready = false;

  @override
  void onStart(DateTime timestamp, SendPort? sendPort) async {
    WidgetsFlutterBinding.ensureInitialized();
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('notifications_icon'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (_) => FlutterForegroundTask.launchApp(),
    );

    try {
      final store = await SharedPreferences.getInstance();
      if (!AppSettings.enableBackgroundSync.getItem(store)) {
        await FlutterForegroundTask.stopService();
        return;
      }

      _clients.addAll(
        await ClientManager.getClients(store: store, backgroundSync: false),
      );
      for (final client in _clients.where((client) => client.isLogged())) {
        // Do not announce events emitted while restoring the local database.
        // Only events received by later polling syncs are notifications.
        _notificationSubscriptions.add(
          client.onNotification.stream.listen(_showNotification),
        );
        client.backgroundSync = false;
        client.syncPresence = PresenceType.offline;
      }
      if (_clients.every((client) => !client.isLogged())) {
        await FlutterForegroundTask.stopService();
        return;
      }
      _ready = true;
      await _poll();
    } catch (error, stackTrace) {
      Logs().e('[BackgroundSync] Unable to restore Matrix clients', error, stackTrace);
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    if (_ready && _clients.any((client) => client.isLogged())) {
      unawaited(_poll());
    } else if (_ready) {
      unawaited(FlutterForegroundTask.stopService());
    }
  }

  Future<void> _poll() async {
    if (_syncing) return;
    _syncing = true;
    try {
      for (final client in _clients.where((client) => client.isLogged())) {
        await client
            .oneShotSync(timeout: const Duration(seconds: 15))
            .timeout(const Duration(seconds: 18));
      }
    } catch (error, stackTrace) {
      // Network loss is expected. The next 20-second tick retries it.
      Logs().w('[BackgroundSync] Poll failed', error, stackTrace);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _showNotification(Event event) async {
    try {
      final l10n = await L10n.delegate.load(PlatformDispatcher.instance.locale);
      final room = event.room;
      final title = room.getLocalizedDisplayname(MatrixLocals(l10n));
      final body = await event.calcLocalizedBody(
        MatrixLocals(l10n),
        plaintextBody: true,
        hideReply: true,
        hideEdit: true,
        removeMarkdown: true,
      );
      await _notifications.show(
        room.id.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConfig.pushNotificationsChannelId,
            l10n.incomingMessages,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: room.id,
      );
    } catch (error, stackTrace) {
      Logs().w('[BackgroundSync] Unable to display notification', error, stackTrace);
    }
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) async {
    for (final subscription in _notificationSubscriptions) {
      await subscription.cancel();
    }
    _notificationSubscriptions.clear();
    for (final client in _clients) {
      await client.dispose();
    }
    _clients.clear();
  }
}
