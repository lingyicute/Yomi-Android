import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';

import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/utils/client_manager.dart';
import 'package:yomi/utils/file_selector.dart';
import 'package:yomi/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:yomi/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:yomi/widgets/future_loading_dialog.dart';
import '../../widgets/matrix.dart';
import 'import_archive_dialog.dart';
import 'settings_emotes_view.dart';

import 'package:archive/archive.dart'
    if (dart.library.io) 'package:archive/archive_io.dart';

class EmotesSettings extends StatefulWidget {
  const EmotesSettings({super.key});

  @override
  EmotesSettingsController createState() => EmotesSettingsController();
}

class EmotesSettingsController extends State<EmotesSettings> {
  String? get roomId => GoRouterState.of(context).pathParameters['roomid'];

  Room? get room =>
      roomId != null ? Matrix.of(context).client.getRoomById(roomId!) : null;

  String? get stateKey => GoRouterState.of(context).pathParameters['state_key'];

  bool showSave = false;
  TextEditingController newImageCodeController = TextEditingController();
  ValueNotifier<ImagePackImageContent?> newImageController =
      ValueNotifier<ImagePackImageContent?>(null);

  ImagePackContent _getPack() {
    final client = Matrix.of(context).client;
    final event = (room != null
            ? room!.getState('im.ponies.room_emotes', stateKey ?? '')
            : client.accountData['im.ponies.user_emotes']) ??
        BasicEvent(
          type: 'm.dummy',
          content: {},
        );
    // make sure we work on a *copy* of the event
    return BasicEvent.fromJson(event.toJson()).parsedImagePackContent;
  }

  ImagePackContent? _pack;

  ImagePackContent? get pack {
    if (_pack != null) {
      return _pack;
    }
    _pack = _getPack();
    return _pack;
  }

  Future<void> save(BuildContext context) async {
    if (readonly) {
      return;
    }
    try {
      final client = Matrix.of(context).client;
      if (room != null) {
        await showFutureLoadingDialog(
          context: context,
          future: () => client.setRoomStateWithKey(
            room!.id,
            'im.ponies.room_emotes',
            stateKey ?? '',
            pack!.toJson(),
          ),
        );
      } else {
        await showFutureLoadingDialog(
          context: context,
          future: () => client.setAccountData(
            client.userID!,
            'im.ponies.user_emotes',
            pack!.toJson(),
          ),
        );
      }
    } catch (e, s) {
      Logs().e('保存表情包失败', e, s);
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: '保存失败',
        message: '无法保存表情包，请稍后再试',
        okLabel: L10n.of(context).ok,
      );
    }
  }

  Future<void> setIsGloballyActive(bool active) async {
    if (room == null) {
      return;
    }

    try {
      final client = Matrix.of(context).client;
      final content = client.accountData['im.ponies.emote_rooms']?.content ??
          <String, dynamic>{};
      if (active) {
        if (content['rooms'] is! Map) {
          content['rooms'] = <String, dynamic>{};
        }
        if (content['rooms'][room!.id] is! Map) {
          content['rooms'][room!.id] = <String, dynamic>{};
        }
        if (content['rooms'][room!.id][stateKey ?? ''] is! Map) {
          content['rooms'][room!.id][stateKey ?? ''] = <String, dynamic>{};
        }
      } else if (content['rooms'] is Map && content['rooms'][room!.id] is Map) {
        content['rooms'][room!.id].remove(stateKey ?? '');
      }
      // and save
      await showFutureLoadingDialog(
        context: context,
        future: () => client.setAccountData(
          client.userID!,
          'im.ponies.emote_rooms',
          content,
        ),
      );
      setState(() {});
    } catch (e, s) {
      Logs().e('设置表情包全局可用性失败', e, s);
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: '设置失败',
        message: '无法更新表情包设置，请稍后再试',
        okLabel: L10n.of(context).ok,
      );
    }
  }

  void removeImageAction(String oldImageCode) => setState(() {
        pack!.images.remove(oldImageCode);
        showSave = true;
      });

  void submitImageAction(
    String oldImageCode,
    String imageCode,
    ImagePackImageContent image,
    TextEditingController controller,
  ) {
    if (pack!.images.keys.any((k) => k == imageCode && k != oldImageCode)) {
      controller.text = oldImageCode;
      showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteExists,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    if (!RegExp(r'^[-\w]+$').hasMatch(imageCode)) {
      controller.text = oldImageCode;
      showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteInvalid,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    setState(() {
      pack!.images[imageCode] = image;
      pack!.images.remove(oldImageCode);
      showSave = true;
    });
  }

  bool isGloballyActive(Client? client) =>
      room != null &&
      client!.accountData['im.ponies.emote_rooms']?.content
              .tryGetMap<String, Object?>('rooms')
              ?.tryGetMap<String, Object?>(room!.id)
              ?.tryGetMap<String, Object?>(stateKey ?? '') !=
          null;

  bool get readonly =>
      room == null ? false : !(room!.canSendEvent('im.ponies.room_emotes'));

  void saveAction() async {
    await save(context);
    setState(() {
      showSave = false;
    });
  }

  void addImageAction() async {
    if (newImageCodeController.text.isEmpty ||
        newImageController.value == null) {
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteWarnNeedToPick,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    final imageCode = newImageCodeController.text;
    if (pack!.images.containsKey(imageCode)) {
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteExists,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    if (!RegExp(r'^[-\w]+$').hasMatch(imageCode)) {
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteInvalid,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    pack!.images[imageCode] = newImageController.value!;
    await save(context);
    setState(() {
      newImageCodeController.text = '';
      newImageController.value = null;
      showSave = false;
    });
  }

  void imagePickerAction(
    ValueNotifier<ImagePackImageContent?> controller,
  ) async {
    try {
      final result = await selectFiles(
        context,
        type: FileSelectorType.images,
      );
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return;
      
      var file = MatrixImageFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
      try {
        file = (await file.generateThumbnail(
          nativeImplementations: ClientManager.nativeImplementations,
        ))!;
      } catch (e, s) {
        Logs().w('无法创建缩略图', e, s);
        // 显示警告但继续执行
        await showOkAlertDialog(
          useRootNavigator: false,
          context: context,
          title: '警告',
          message: '无法生成缩略图，将使用原始图片',
          okLabel: L10n.of(context).ok,
        );
      }
      
      final uploadResp = await showFutureLoadingDialog(
        context: context,
        future: () => Matrix.of(context).client.uploadContent(
              file.bytes,
              filename: file.name,
              contentType: file.mimeType,
            ),
      );
      
      if (uploadResp.error != null) {
        Logs().e('上传表情图片失败', uploadResp.error);
        await showOkAlertDialog(
          useRootNavigator: false,
          context: context,
          title: '上传失败',
          message: '无法上传表情图片，请检查网络连接后重试',
          okLabel: L10n.of(context).ok,
        );
        return;
      }
      
      setState(() {
        final info = <String, dynamic>{
          ...file.info,
        };
        // normalize width / height to 256, required for stickers
        if (info['w'] is int && info['h'] is int) {
          final ratio = info['w'] / info['h'];
          if (info['w'] > info['h']) {
            info['w'] = 256;
            info['h'] = (256.0 / ratio).round();
          } else {
            info['h'] = 256;
            info['w'] = (ratio * 256.0).round();
          }
        }
        controller.value = ImagePackImageContent.fromJson(<String, dynamic>{
          'url': uploadResp.result.toString(),
          'info': info,
        });
      });
    } catch (e, s) {
      Logs().e('选择或处理表情图片失败', e, s);
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: '操作失败',
        message: '选择或处理图片时发生错误，请重试',
        okLabel: L10n.of(context).ok,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return EmotesSettingsView(this);
  }

  Future<void> importEmojiZip() async {
    try {
      final result = await showFutureLoadingDialog<Archive?>(
        context: context,
        future: () async {
          final result = await selectFiles(
            context,
            type: FileSelectorType.zip,
          );

          if (result.isEmpty) return null;

          final buffer = InputStream(await result.first.readAsBytes());

          final archive = ZipDecoder().decodeBuffer(buffer);

          return archive;
        },
      );

      if (result.error != null) {
        Logs().e('导入表情包ZIP文件失败', result.error);
        await showOkAlertDialog(
          useRootNavigator: false,
          context: context,
          title: '导入失败',
          message: '无法读取或处理ZIP文件，请确认文件格式正确',
          okLabel: L10n.of(context).ok,
        );
        return;
      }

      final archive = result.result;
      if (archive == null) return;

      await showDialog(
        context: context,
        // breaks [Matrix.of] calls otherwise
        useRootNavigator: false,
        builder: (context) => ImportEmoteArchiveDialog(
          controller: this,
          archive: archive,
        ),
      );
      setState(() {});
    } catch (e, s) {
      Logs().e('导入表情包过程中发生错误', e, s);
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: '导入错误',
        message: '导入表情包时发生错误，请重试',
        okLabel: L10n.of(context).ok,
      );
    }
  }

  Future<void> exportAsZip() async {
    try {
      final client = Matrix.of(context).client;

      await showFutureLoadingDialog(
        context: context,
        future: () async {
          final pack = _getPack();
          final archive = Archive();
          
          for (final entry in pack.images.entries) {
            try {
              final emote = entry.value;
              final name = entry.key;
              final url = await emote.url.getDownloadUri(client);
              final response = await get(
                url,
                headers: {'authorization': 'Bearer ${client.accessToken}'},
              );

              archive.addFile(
                ArchiveFile(
                  name,
                  response.bodyBytes.length,
                  response.bodyBytes,
                ),
              );
            } catch (e, s) {
              Logs().w('导出表情 "${entry.key}" 失败，跳过', e, s);
              // 继续处理其他表情
              continue;
            }
          }
          
          final fileName =
              '${pack.pack.displayName ?? client.userID?.localpart ?? 'emotes'}.zip';
          final output = ZipEncoder().encode(archive);

          if (output == null) {
            throw Exception('无法创建ZIP文件');
          }

          MatrixFile(
            name: fileName,
            bytes: Uint8List.fromList(output),
          ).save(context);
        },
      );
    } catch (e, s) {
      Logs().e('导出表情包失败', e, s);
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: '导出失败',
        message: '无法导出表情包，请稍后重试',
        okLabel: L10n.of(context).ok,
      );
    }
  }
}
