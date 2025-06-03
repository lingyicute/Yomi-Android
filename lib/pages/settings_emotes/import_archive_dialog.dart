import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/pages/settings_emotes/settings_emotes.dart';
import 'package:yomi/utils/client_manager.dart';
import 'package:yomi/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:yomi/widgets/matrix.dart';

class ImportEmoteArchiveDialog extends StatefulWidget {
  final EmotesSettingsController controller;
  final Archive archive;

  const ImportEmoteArchiveDialog({
    super.key,
    required this.controller,
    required this.archive,
  });

  @override
  State<ImportEmoteArchiveDialog> createState() =>
      _ImportEmoteArchiveDialogState();
}

class _ImportEmoteArchiveDialogState extends State<ImportEmoteArchiveDialog> {
  Map<ArchiveFile, String> _importMap = {};

  bool _loading = false;

  double _progress = 0;

  @override
  void initState() {
    _importFileMap();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.of(context).importEmojis),
      content: _loading
          ? Center(
              child: CircularProgressIndicator(
                value: _progress,
              ),
            )
          : SingleChildScrollView(
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                spacing: 8,
                children: _importMap.entries
                    .map(
                      (e) => _EmojiImportPreview(
                        key: ValueKey(e.key.name),
                        entry: e,
                        onNameChanged: (name) => _importMap[e.key] = name,
                        onRemove: () =>
                            setState(() => _importMap.remove(e.key)),
                      ),
                    )
                    .toList(),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _loading ? null : Navigator.of(context).pop,
          child: Text(L10n.of(context).cancel),
        ),
        TextButton(
          onPressed: _loading
              ? null
              : _importMap.isNotEmpty
                  ? _addEmotePack
                  : null,
          child: Text(L10n.of(context).importNow),
        ),
      ],
    );
  }

  void _importFileMap() {
    _importMap = Map.fromEntries(
      widget.archive.files
          .where((e) => e.isFile)
          .map(
            (e) => MapEntry(e, e.name.emoteNameFromPath),
          )
          .sorted(
            (a, b) => a.value.compareTo(b.value),
          ),
    );
  }

  Future<void> _addEmotePack() async {
    setState(() {
      _loading = true;
      _progress = 0;
    });
    
    try {
      final imports = _importMap;
      final successfulUploads = <String>{};
      final failedUploads = <String, String>{};

      // check for duplicates first
      final skipKeys = [];

      for (final entry in imports.entries) {
        final imageCode = entry.value;

        if (widget.controller.pack!.images.containsKey(imageCode)) {
          final completer = Completer<OkCancelResult>();
          WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
            final result = await showOkCancelAlertDialog(
              useRootNavigator: false,
              context: context,
              title: L10n.of(context).emoteExists,
              message: imageCode,
              cancelLabel: L10n.of(context).replace,
              okLabel: L10n.of(context).skip,
            );
            completer.complete(result);
          });

          final result = await completer.future;
          if (result == OkCancelResult.ok) {
            skipKeys.add(entry.key);
          }
        }
      }

      for (final key in skipKeys) {
        imports.remove(key);
      }

      for (final entry in imports.entries) {
        setState(() {
          _progress += 1 / imports.length;
        });
        final file = entry.key;
        final imageCode = entry.value;

        try {
          var mxcFile = MatrixImageFile(
            bytes: file.content,
            name: file.name,
          );

          final thumbnail = (await mxcFile.generateThumbnail(
            nativeImplementations: ClientManager.nativeImplementations,
          ));
          if (thumbnail == null) {
            Logs().w('无法为表情 $imageCode 创建缩略图，使用原始图片');
          } else {
            mxcFile = thumbnail;
          }
          final uri = await Matrix.of(context).client.uploadContent(
                mxcFile.bytes,
                filename: mxcFile.name,
                contentType: mxcFile.mimeType,
              );

          final info = <String, dynamic>{
            ...mxcFile.info,
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
          widget.controller.pack!.images[imageCode] =
              ImagePackImageContent.fromJson(<String, dynamic>{
            'url': uri.toString(),
            'info': info,
          });
          successfulUploads.add(file.name);
        } catch (e, s) {
          Logs().e('无法上传表情 $imageCode', e, s);
          failedUploads[file.name] = imageCode;
        }
      }

      // 如果有失败的表情上传，显示提示
      if (failedUploads.isNotEmpty) {
        final failedCount = failedUploads.length;
        final totalCount = imports.length;
        
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await showOkAlertDialog(
            useRootNavigator: false,
            context: context,
            title: '部分表情上传失败',
            message: '共有 $failedCount/$totalCount 个表情上传失败，\n'
                '已上传成功的表情将被保存',
            okLabel: L10n.of(context).ok,
          );
        });
      }

      // 只有存在成功上传的表情才保存
      if (successfulUploads.isNotEmpty) {
        try {
          await widget.controller.save(context);
        } catch (e, s) {
          Logs().e('保存表情包失败', e, s);
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await showOkAlertDialog(
              useRootNavigator: false,
              context: context,
              title: '保存失败',
              message: '无法保存表情包，请稍后重试',
              okLabel: L10n.of(context).ok,
            );
          });
        }
      }

      _importMap.removeWhere(
        (key, value) => successfulUploads.contains(key.name),
      );

    } catch (e, s) {
      Logs().e('导入表情包过程中发生错误', e, s);
      
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await showOkAlertDialog(
          useRootNavigator: false,
          context: context,
          title: '导入错误',
          message: '导入表情包时发生错误，请重试',
          okLabel: L10n.of(context).ok,
        );
      });
    } finally {
      _loading = false;
      _progress = 0;

      // in case we have unhandled / duplicated emotes left, don't pop
      if (mounted) setState(() {});
      if (_importMap.isEmpty) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => Navigator.of(context).pop());
      }
    }
  }
}

class _EmojiImportPreview extends StatefulWidget {
  final MapEntry<ArchiveFile, String> entry;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onRemove;

  const _EmojiImportPreview({
    super.key,
    required this.entry,
    required this.onNameChanged,
    required this.onRemove,
  });

  @override
  State<_EmojiImportPreview> createState() => _EmojiImportPreviewState();
}

class _EmojiImportPreviewState extends State<_EmojiImportPreview> {
  final hasErrorNotifier = ValueNotifier(false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // TODO: support Lottie here as well ...
    final controller = TextEditingController(text: widget.entry.value);

    return Stack(
      alignment: Alignment.topRight,
      children: [
        IconButton(
          onPressed: widget.onRemove,
          icon: const Icon(Icons.remove_circle),
          tooltip: L10n.of(context).remove,
        ),
        ValueListenableBuilder(
          valueListenable: hasErrorNotifier,
          builder: (context, hasError, child) {
            if (hasError) return _ImageFileError(name: widget.entry.key.name);

            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.memory(
                  widget.entry.key.content,
                  height: 64,
                  width: 64,
                  errorBuilder: (context, e, s) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _setRenderError());

                    return _ImageFileError(
                      name: widget.entry.key.name,
                    );
                  },
                ),
                SizedBox(
                  width: 128,
                  child: TextField(
                    controller: controller,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^[-\w]+$')),
                    ],
                    autocorrect: false,
                    minLines: 1,
                    maxLines: 1,
                    decoration: InputDecoration(
                      hintText: L10n.of(context).emoteShortcode,
                      prefixText: ': ',
                      suffixText: ':',
                      border: const OutlineInputBorder(),
                      prefixStyle: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                      suffixStyle: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onChanged: widget.onNameChanged,
                    onSubmitted: widget.onNameChanged,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  _setRenderError() {
    hasErrorNotifier.value = true;
    widget.onRemove.call();
  }
}

class _ImageFileError extends StatelessWidget {
  final String name;

  const _ImageFileError({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox.square(
      dimension: 64,
      child: Tooltip(
        message: name,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.error),
            Text(
              L10n.of(context).notAnImage,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  /// normalizes a file path into its name only replacing any special character
  /// [^-\w] with an underscore and removing the extension
  ///
  /// Used to compute emote name proposal based on file name
  String get emoteNameFromPath {
    // ... removing leading path
    return split(RegExp(r'[/\\]'))
        .last
        // ... removing file extension
        .split('.')
        .first
        // ... lowering
        .toLowerCase()
        // ... replacing unexpected characters
        .replaceAll(RegExp(r'[^-\w]'), '_');
  }
}
