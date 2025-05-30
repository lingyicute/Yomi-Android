import 'package:shared_preferences/shared_preferences.dart';

abstract class SettingKeys {
  static const String renderHtml = 'chat.lyi.renderHtml';
  static const String hideRedactedEvents = 'chat.lyi.hideRedactedEvents';
  static const String hideUnknownEvents = 'chat.lyi.hideUnknownEvents';
  static const String hideUnimportantStateEvents =
      'chat.lyi.hideUnimportantStateEvents';
  static const String separateChatTypes = 'chat.lyi.separateChatTypes';
  static const String sentry = 'sentry';
  static const String theme = 'theme';
  static const String amoledEnabled = 'amoled_enabled';
  static const String codeLanguage = 'code_language';
  static const String showNoGoogle = 'chat.lyi.show_no_google';
  static const String fontSizeFactor = 'chat.lyi.font_size_factor';
  static const String showNoPid = 'chat.lyi.show_no_pid';
  static const String databasePassword = 'database-password';
  static const String appLockKey = 'chat.lyi.app_lock';
  static const String unifiedPushRegistered =
      'chat.lyi.unifiedpush.registered';
  static const String unifiedPushEndpoint = 'chat.lyi.unifiedpush.endpoint';
  static const String ownStatusMessage = 'chat.lyi.status_msg';
  static const String dontAskForBootstrapKey =
      'chat.yomi.dont_ask_bootstrap';
  static const String autoplayImages = 'chat.lyi.autoplay_images';
  static const String sendTypingNotifications =
      'chat.lyi.send_typing_notifications';
  static const String sendPublicReadReceipts =
      'chat.lyi.send_public_read_receipts';
  static const String sendOnEnter = 'chat.lyi.send_on_enter';
  static const String swipeRightToLeftToReply =
      'chat.lyi.swipeRightToLeftToReply';
  static const String experimentalVoip = 'chat.lyi.experimental_voip';
  static const String showPresences = 'chat.lyi.show_presences';
}

enum AppSettings<T> {
  audioRecordingNumChannels<int>('audioRecordingNumChannels', 1),
  audioRecordingAutoGain<bool>('audioRecordingAutoGain', true),
  audioRecordingEchoCancel<bool>('audioRecordingEchoCancel', false),
  audioRecordingNoiseSuppress<bool>('audioRecordingNoiseSuppress', true),
  audioRecordingBitRate<int>('audioRecordingBitRate', 64000),
  audioRecordingSamplingRate<int>('audioRecordingSamplingRate', 44100),
  pushNotificationsGatewayUrl<String>(
    'pushNotificationsGatewayUrl',
    'https://push.yomi.im/_matrix/push/v1/notify',
  ),
  pushNotificationsPusherFormat<String>(
    'pushNotificationsPusherFormat',
    'event_id_only',
  ),
  shareKeysWith<String>('chat.lyi.share_keys_with_2', 'all'),
  noEncryptionWarningShown<bool>(
    'chat.lyi.no_encryption_warning_shown',
    false,
  ),
  displayChatDetailsColumn(
    'chat.lyi.display_chat_details_column',
    false,
  ),
  enableSoftLogout<bool>('chat.lyi.enable_soft_logout', false);

  final String key;
  final T defaultValue;

  const AppSettings(this.key, this.defaultValue);
}

extension AppSettingsBoolExtension on AppSettings<bool> {
  bool getItem(SharedPreferences store) => store.getBool(key) ?? defaultValue;

  Future<void> setItem(SharedPreferences store, bool value) =>
      store.setBool(key, value);
}

extension AppSettingsStringExtension on AppSettings<String> {
  String getItem(SharedPreferences store) =>
      store.getString(key) ?? defaultValue;

  Future<void> setItem(SharedPreferences store, String value) =>
      store.setString(key, value);
}

extension AppSettingsIntExtension on AppSettings<int> {
  int getItem(SharedPreferences store) => store.getInt(key) ?? defaultValue;

  Future<void> setItem(SharedPreferences store, int value) =>
      store.setInt(key, value);
}

extension AppSettingsDoubleExtension on AppSettings<double> {
  double getItem(SharedPreferences store) =>
      store.getDouble(key) ?? defaultValue;

  Future<void> setItem(SharedPreferences store, double value) =>
      store.setDouble(key, value);
}
