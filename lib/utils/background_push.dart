/*
 *   Famedly
 *   Copyright (C) 2020, 2021 Famedly GmbH
 *   Copyright (C) 2021, 2026 Yomi
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as
 *   published by the Free Software Foundation, either version 3 of the
 *   License, or (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_new_badger/flutter_new_badger.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/utils/background_sync_host.dart';
import 'package:yomi/utils/push_helper.dart';
import 'package:yomi/widgets/lyi_chat_app.dart';
import '../config/app_config.dart';
import '../config/setting_keys.dart';
import '../widgets/matrix.dart';
import 'platform_infos.dart';

/// Local notification pipeline that does **not** use Firebase or ntfy.
///
/// Matrix homeservers cannot push into the app without a third-party gateway.
/// The robust alternative (and the one that still feels like "server push")
/// is `/sync` long-polling:
///
/// * `timeout=20s` — the server returns *immediately* when a new event
///   arrives, otherwise it replies empty after 20 seconds.
/// * An Android foreground service keeps the Dart isolate alive so the
///   long-poll survives the user leaving the app.
/// * A 2-minute native watchdog + BOOT_COMPLETED receiver restart the
///   service if a Chinese OEM kills the process.
///
/// Incoming events that match the user's push rules are delivered on
/// [Client.onNotification] and shown with [flutter_local_notifications].
class BackgroundPush {
  static BackgroundPush? _instance;

  static const Duration syncTimeout = Duration(seconds: 20);
  static const Duration _syncSafetyTimeout = Duration(seconds: 45);
  static const Duration _minBackoff = Duration(seconds: 2);
  static const Duration _maxBackoff = Duration(seconds: 60);

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  List<Client> _clients;
  MatrixState? matrix;
  L10n? l10n;

  final Map<String, StreamSubscription<Event>> _notificationSubs = {};
  final Map<String, StreamSubscription<LoginState>> _loginSubs = {};

  bool _polling = false;
  bool _wantPolling = false;
  bool _clearingPushers = false;
  String? _pendingRoomId;
  static bool _wentToRoomOnStartup = false;

  DateTime? lastReceivedPush;

  Future<void> loadLocale() async {
    final context = matrix?.context;
    l10n ??= (context != null ? L10n.of(context) : null) ??
        (await L10n.delegate.load(PlatformDispatcher.instance.locale));
  }

  void _init() async {
    try {
      await _flutterLocalNotificationsPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('notifications_icon'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: goToRoom,
      );
      Logs().v('Flutter Local Notifications initialized');
    } catch (e, s) {
      Logs().e('Unable to initialize Flutter local notifications', e, s);
    }
  }

  BackgroundPush._(this._clients) {
    _init();
  }

  factory BackgroundPush.clientOnly(Client client) {
    return BackgroundPush.clientsOnly([client]);
  }

  factory BackgroundPush.clientsOnly(List<Client> clients) {
    final instance = _instance ??= BackgroundPush._(clients);
    instance.updateClients(clients);
    return instance;
  }

  factory BackgroundPush(MatrixState matrix) {
    final instance = BackgroundPush.clientsOnly(matrix.widget.clients);
    instance.matrix = matrix;
    return instance;
  }

  void updateClients(List<Client> clients) {
    _clients = List<Client>.from(clients);
    _bindClients();
  }

  List<Client> get _loggedInClients =>
      _clients.where((client) => client.isLogged()).toList();

  void _bindClients() {
    final living = <String>{};
    for (final client in _clients) {
      living.add(client.clientName);
      _notificationSubs[client.clientName] ??=
          client.onNotification.stream.listen(
        (event) => _onNotificationEvent(client, event),
        onError: (e, s) =>
            Logs().w('[Push] onNotification error for ${client.userID}', e, s),
      );
      _loginSubs[client.clientName] ??= client.onLoginStateChanged.stream
          .listen((state) => _onLoginStateChanged(client, state));
    }
    for (final name in _notificationSubs.keys.toList()) {
      if (living.contains(name)) continue;
      _notificationSubs.remove(name)?.cancel();
      _loginSubs.remove(name)?.cancel();
    }
  }

  void _onLoginStateChanged(Client client, LoginState state) {
    if (state == LoginState.loggedIn) {
      unawaited(setupPush());
      return;
    }
    if (_loggedInClients.isEmpty) {
      unawaited(stop());
    }
  }

  Future<void> cancelNotification(String roomId) async {
    Logs().v('Cancel notification for room', roomId);
    await _flutterLocalNotificationsPlugin.cancel(roomId.hashCode);

    // Workaround for app icon badge not updating
    if (Platform.isIOS) {
      final unreadCount = _clients.fold<int>(
        0,
        (sum, client) =>
            sum +
            client.rooms
                .where((room) => room.isUnreadOrInvited && room.id != roomId)
                .length,
      );
      if (unreadCount == 0) {
        FlutterNewBadger.removeBadge();
      } else {
        FlutterNewBadger.setBadge(unreadCount);
      }
    }
  }

  Future<void> setupPush() async {
    Logs().d('SetupPush (local background sync)');
    if (matrix != null) {
      updateClients(matrix!.widget.clients);
    }
    if (!PlatformInfos.isMobile) return;
    final loggedIn = _loggedInClients;
    if (loggedIn.isEmpty) {
      await stop();
      return;
    }

    await _requestNotificationPermission();
    await _clearHttpPushers(loggedIn);
    _bindClients();
    await _markEnabled(true);
    if (PlatformInfos.isAndroid) {
      await BackgroundSyncHost.start();
      unawaited(_maybeAskBatteryOptimization());
    }
    _startPollLoop();

    // ignore: unawaited_futures
    _flutterLocalNotificationsPlugin
        .getNotificationAppLaunchDetails()
        .then((details) {
      if (details == null ||
          !details.didNotificationLaunchApp ||
          _wentToRoomOnStartup) {
        return;
      }
      _wentToRoomOnStartup = true;
      goToRoom(details.notificationResponse);
    });

    if (_pendingRoomId != null) {
      await _openRoom(_pendingRoomId);
    }
  }

  Future<void> onResumed() async {
    if (_loggedInClients.isEmpty) return;
    _startPollLoop();
    if (PlatformInfos.isAndroid) {
      await BackgroundSyncHost.start();
    }
    if (_pendingRoomId != null) {
      await _openRoom(_pendingRoomId);
    }
  }

  Future<void> stop() async {
    _wantPolling = false;
    await _markEnabled(false);
    if (PlatformInfos.isAndroid) {
      await BackgroundSyncHost.stop();
    }
  }

  Future<void> _markEnabled(bool enabled) async {
    try {
      final store = matrix?.store ?? await SharedPreferences.getInstance();
      await store.setBool(SettingKeys.backgroundSyncEnabled, enabled);
    } catch (e, s) {
      Logs().w('[Push] Unable to persist background-sync flag', e, s);
    }
  }

  Future<void> _maybeAskBatteryOptimization() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      final store = matrix?.store ?? await SharedPreferences.getInstance();
      if (store.getBool(SettingKeys.askedBatteryOptimization) == true) {
        return;
      }
      if (await BackgroundSyncHost.isIgnoringBatteryOptimizations()) {
        await store.setBool(SettingKeys.askedBatteryOptimization, true);
        return;
      }
      // Only prompt when we have a visible UI so the system dialog can show.
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      await store.setBool(SettingKeys.askedBatteryOptimization, true);
      await BackgroundSyncHost.requestIgnoreBatteryOptimizations();
    } catch (e, s) {
      Logs().w('[Push] Battery-optimization prompt failed', e, s);
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (PlatformInfos.isAndroid) {
      try {
        await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } catch (e, s) {
        Logs().w('[Push] Unable to request notification permission', e, s);
      }
    }
  }

  /// Delete leftover Firebase / UnifiedPush / ntfy HTTP pushers for *this*
  /// device so the homeserver stops trying to reach a gateway we no longer
  /// listen on.
  Future<void> _clearHttpPushers(List<Client> clients) async {
    if (_clearingPushers) return;
    _clearingPushers = true;
    try {
      for (final client in clients) {
        if (!client.isLogged()) continue;
        List<Pusher> pushers;
        try {
          pushers = await client.getPushers() ?? [];
        } catch (e, s) {
          Logs().w('[Push] Unable to list pushers for ${client.userID}', e, s);
          continue;
        }
        final ownName = client.deviceName;
        for (final pusher in pushers) {
          final isThisDevice = pusher.deviceDisplayName == ownName ||
              (client.deviceID != null &&
                  pusher.appId.contains(client.deviceID!));
          if (!isThisDevice) continue;
          try {
            await client.deletePusher(pusher);
            Logs().i(
              '[Push] Removed leftover HTTP pusher ${pusher.appId} '
              'for ${client.userID}',
            );
          } catch (e, s) {
            Logs().w('[Push] Failed to delete pusher ${pusher.appId}', e, s);
          }
        }
      }
    } finally {
      _clearingPushers = false;
    }
  }

  void _startPollLoop() {
    _wantPolling = true;
    if (_polling) return;
    unawaited(_runPollLoop());
  }

  Future<void> _runPollLoop() async {
    if (_polling) return;
    _polling = true;
    var backoff = _minBackoff;
    Logs().i('[Push] Starting local /sync loop (timeout=${syncTimeout.inSeconds}s)');
    try {
      while (_wantPolling) {
        if (matrix != null) {
          updateClients(matrix!.widget.clients);
        }
        final loggedIn = _loggedInClients;
        if (loggedIn.isEmpty) {
          Logs().i('[Push] No logged-in clients, stopping sync loop');
          await stop();
          break;
        }

        // We own the cadence. Disable the SDK's 30s auto-loop so a hung
        // long-poll can be aborted and retried on our 20s schedule.
        for (final client in loggedIn) {
          client.backgroundSync = false;
        }

        var hadError = false;
        await Future.wait(
          loggedIn.map((client) async {
            try {
              await client
                  .oneShotSync(timeout: syncTimeout)
                  .timeout(_syncSafetyTimeout);
            } on TimeoutException {
              Logs().w(
                '[Push] /sync hung for ${client.userID}, aborting and retrying',
              );
              try {
                await client.abortSync();
              } catch (_) {}
              hadError = true;
            } catch (e, s) {
              Logs().w('[Push] /sync failed for ${client.userID}', e, s);
              hadError = true;
            }
          }),
        );

        if (hadError) {
          await Future.delayed(backoff);
          backoff = Duration(
            seconds: min(backoff.inSeconds * 2, _maxBackoff.inSeconds),
          );
        } else {
          backoff = _minBackoff;
        }
      }
    } finally {
      _polling = false;
      Logs().i('[Push] Local /sync loop stopped');
    }
  }

  Future<void> _onNotificationEvent(Client client, Event event) async {
    lastReceivedPush = DateTime.now();
    try {
      await loadLocale();
      await showEventNotification(
        event,
        client: client,
        l10n: l10n,
        activeRoomId: matrix?.activeRoomId,
        flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
        unreadCount: event.room.notificationCount,
      );
    } catch (e, s) {
      Logs().e('[Push] Failed to display local notification', e, s);
      try {
        await loadLocale();
        final fallback = l10n;
        if (fallback != null) {
          await _flutterLocalNotificationsPlugin.show(
            event.room.id.hashCode,
            fallback.newMessageInYomi,
            fallback.openAppToReadMessages,
            NotificationDetails(
              android: AndroidNotificationDetails(
                AppConfig.pushNotificationsChannelId,
                fallback.incomingMessages,
                importance: Importance.high,
                priority: Priority.max,
              ),
            ),
            payload: event.room.id,
          );
        }
      } catch (_) {}
    }
  }

  Future<void> goToRoom(NotificationResponse? response) =>
      _openRoom(response?.payload);

  Future<void> _openRoom(String? roomId) async {
    try {
      Logs().v('[Push] Attempting to go to room $roomId...');
      if (roomId == null) {
        return;
      }
      final clients = _loggedInClients;
      if (clients.isEmpty) {
        _pendingRoomId = roomId;
        return;
      }
      Client? owner;
      for (final client in clients) {
        await client.roomsLoading;
        await client.accountDataLoading;
        if (client.getRoomById(roomId) != null) {
          owner = client;
          break;
        }
      }
      owner ??= clients.first;
      if (owner.getRoomById(roomId) == null) {
        try {
          await owner
              .waitForRoomInSync(roomId)
              .timeout(const Duration(seconds: 30));
        } catch (e, s) {
          Logs().w('[Push] Room $roomId did not appear in sync', e, s);
        }
      }
      try {
        YomiApp.router.go(
          owner.getRoomById(roomId)?.membership == Membership.invite
              ? '/rooms'
              : '/rooms/$roomId',
        );
        _pendingRoomId = null;
      } catch (e) {
        Logs().w('[Push] Router not ready, deferring navigation to $roomId', e);
        _pendingRoomId = roomId;
      }
    } catch (e, s) {
      Logs().e('[Push] Failed to open room', e, s);
    }
  }
}
