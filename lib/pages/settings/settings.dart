import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/utils/client_download_content_extension.dart' as cache_utils;
import 'package:yomi/utils/file_selector.dart';
import 'package:yomi/utils/platform_infos.dart';
import 'package:yomi/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:yomi/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:yomi/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:yomi/widgets/future_loading_dialog.dart';
import '../../widgets/matrix.dart';
import '../bootstrap/bootstrap_dialog.dart';
import 'settings_view.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  SettingsController createState() => SettingsController();
}

class SettingsController extends State<Settings> {
  Future<Profile>? profileFuture;
  bool profileUpdated = false;
  int _avatarUpdateTimestamp = DateTime.now().millisecondsSinceEpoch;
  
  // 公共访问器
  int get avatarUpdateTimestamp => _avatarUpdateTimestamp;

  void updateProfile() => setState(() {
        profileUpdated = true;
        profileFuture = null;
        _avatarUpdateTimestamp = DateTime.now().millisecondsSinceEpoch;
      });

  void setDisplaynameAction() async {
    final profile = await profileFuture;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).editDisplayname,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText:
          profile?.displayName ?? Matrix.of(context).client.userID!.localpart,
    );
    if (input == null) return;
    final matrix = Matrix.of(context);
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setDisplayName(matrix.client.userID!, input),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  void logoutAction() async {
    final noBackup = showChatBackupBanner == true;
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: L10n.of(context).areYouSureYouWantToLogout,
          message: L10n.of(context).noBackupWarning,
          isDestructive: noBackup,
          okLabel: L10n.of(context).logout,
          cancelLabel: L10n.of(context).cancel,
        ) ==
        OkCancelResult.cancel) {
      return;
    }
    final matrix = Matrix.of(context);
    await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.logout(),
    );
  }

  void setAvatarAction() async {
    final profile = await profileFuture;
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: L10n.of(context).openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: L10n.of(context).openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (profile?.avatarUrl != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: L10n.of(context).removeYourAvatar,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: L10n.of(context).changeYourAvatar,
            cancelLabel: L10n.of(context).cancel,
            actions: actions,
          );
    if (action == null) return;
    final matrix = Matrix.of(context);
    final oldAvatarUrl = profile?.avatarUrl;
    
    if (action == AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () async {
          await matrix.client.setAvatar(null);
          
          if (oldAvatarUrl != null) {
            await matrix.client.clearAvatarCache(oldAvatarUrl);
          }
          
          // 等待一小段时间以确保服务器端处理完成
          await Future.delayed(Duration(milliseconds: 300));
          
          return;
        },
      );
      if (success.error == null) {
        updateProfile();
      }
      return;
    }
    MatrixFile file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(
        bytes: await result.readAsBytes(),
        name: result.path,
      );
    } else {
      final result = await selectFiles(
        context,
        type: FileSelectorType.images,
      );
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
    }
    
    final success = await showFutureLoadingDialog(
      context: context,
      future: () async {
        await matrix.client.setAvatar(file);
        
        if (oldAvatarUrl != null) {
          await matrix.client.clearAvatarCache(oldAvatarUrl);
        }
        
        // 等待一小段时间以确保服务器端处理完成
        await Future.delayed(Duration(milliseconds: 300));
        
        final newProfile = await matrix.client.getProfileFromUserId(
          matrix.client.userID!,
          getFromRooms: false,
        );
        
        if (newProfile.avatarUrl != null) {
          await matrix.client.forceRefreshAvatar(newProfile.avatarUrl);
        }
        
        return;
      },
    );
    
    if (success.error == null) {
      updateProfile();
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkBootstrap();
      refreshCurrentAvatar();
    });

    super.initState();
  }

  void checkBootstrap() async {
    final client = Matrix.of(context).client;
    if (!client.encryptionEnabled) return;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }
    final crossSigning =
        await client.encryption?.crossSigning.isCached() ?? false;
    final needsBootstrap =
        await client.encryption?.keyManager.isCached() == false ||
            client.encryption?.crossSigning.enabled == false ||
            crossSigning == false;
    final isUnknownSession = client.isUnknownSession;
    setState(() {
      showChatBackupBanner = needsBootstrap || isUnknownSession;
    });
  }

  bool? crossSigningCached;
  bool? showChatBackupBanner;

  void firstRunBootstrapAction([_]) async {
    if (showChatBackupBanner != true) {
      showOkAlertDialog(
        context: context,
        title: L10n.of(context).chatBackup,
        message: L10n.of(context).onlineKeyBackupEnabled,
        okLabel: L10n.of(context).close,
      );
      return;
    }
    await BootstrapDialog(
      client: Matrix.of(context).client,
    ).show(context);
    checkBootstrap();
  }

  // 刷新当前头像
  void refreshCurrentAvatar() async {
    try {
      // 只通过更新profile来刷新界面，不做缓存操作
      if (mounted) {
        updateProfile();
      }
    } catch (e) {
      // 忽略异常
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    profileFuture ??= client.getProfileFromUserId(
      client.userID!,
    );
    return SettingsView(this);
  }
}

enum AvatarAction { camera, file, remove }
