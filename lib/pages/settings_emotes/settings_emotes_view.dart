import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/utils/platform_infos.dart';
import 'package:yomi/widgets/layouts/max_width_body.dart';
import 'package:yomi/widgets/mxc_image.dart';
import 'package:yomi/widgets/safe_popup_menu.dart';
import '../../widgets/matrix.dart';
import 'settings_emotes.dart';

enum PopupMenuEmojiActions { import, export }

class EmotesSettingsView extends StatelessWidget {
  final EmotesSettingsController controller;

  const EmotesSettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    
    // 捕获获取表情包可能的错误
    List<String> imageKeys = [];
    try {
      imageKeys = controller.pack!.images.keys.toList();
    } catch (e, s) {
      Logs().e('获取表情包数据失败', e, s);
      // 稍后在UI中处理这个错误
    }
    
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(L10n.of(context).customEmojisAndStickers),
        actions: [
          SafePopupMenu<PopupMenuEmojiActions>(
            onSelected: (value) {
              try {
                switch (value) {
                  case PopupMenuEmojiActions.export:
                    controller.exportAsZip();
                    break;
                  case PopupMenuEmojiActions.import:
                    controller.importEmojiZip();
                    break;
                }
              } catch (e, s) {
                Logs().e('执行表情包操作失败', e, s);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('操作失败，请稍后重试')),
                );
              }
            },
            enabled: !controller.readonly,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: PopupMenuEmojiActions.import,
                child: Text(L10n.of(context).importFromZipFile),
              ),
              PopupMenuItem(
                value: PopupMenuEmojiActions.export,
                child: Text(L10n.of(context).exportEmotePack),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: controller.showSave
          ? FloatingActionButton(
              onPressed: () {
                try {
                  controller.saveAction();
                } catch (e, s) {
                  Logs().e('保存表情包失败', e, s);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('保存失败，请稍后重试')),
                  );
                }
              },
              child: const Icon(Icons.save_outlined, color: Colors.white),
            )
          : null,
      body: MaxWidthBody(
        child: Builder(
          builder: (context) {
            // 处理表情包加载错误
            if (imageKeys.isEmpty && controller.pack == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '无法加载表情包数据',
                        style: TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: Text('返回'),
                      ),
                    ],
                  ),
                ),
              );
            }
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (!controller.readonly)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8.0,
                    ),
                    child: ListTile(
                      leading: SizedBox(
                        width: 180.0,
                        child: TextField(
                          controller: controller.newImageCodeController,
                          autocorrect: false,
                          minLines: 1,
                          maxLines: 1,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceVariant,
                            hintText: L10n.of(context).emoteShortcode,
                            prefixText: ': ',
                            prefixStyle: TextStyle(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                      title: _ImagePicker(
                        controller: controller.newImageController,
                        onPressed: controller.imagePickerAction,
                      ),
                      trailing: InkWell(
                        onTap: () {
                          try {
                            controller.addImageAction();
                          } catch (e, s) {
                            Logs().e('添加表情失败', e, s);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('添加表情失败，请重试')),
                            );
                          }
                        },
                        child: const Icon(
                          Icons.add_outlined,
                          color: Colors.green,
                          size: 32.0,
                        ),
                      ),
                    ),
                  ),
                if (controller.room != null)
                  SwitchListTile.adaptive(
                    title: Text(L10n.of(context).enableEmotesGlobally),
                    value: controller.isGloballyActive(client),
                    onChanged: (value) {
                      try {
                        controller.setIsGloballyActive(value);
                      } catch (e, s) {
                        Logs().e('设置全局可用性失败', e, s);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('设置失败，请重试')),
                        );
                      }
                    },
                  ),
                if (!controller.readonly || controller.room != null)
                  const Divider(),
                imageKeys.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            L10n.of(context).noEmotesFound,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        separatorBuilder: (BuildContext context, int i) =>
                            const SizedBox.shrink(),
                        itemCount: imageKeys.length + 1,
                        itemBuilder: (BuildContext context, int i) {
                          if (i >= imageKeys.length) {
                            return Container(height: 70);
                          }
                          
                          final imageCode = imageKeys[i];
                          ImagePackImageContent? image;
                          
                          try {
                            image = controller.pack!.images[imageCode];
                            if (image == null) {
                              throw Exception('表情内容为空');
                            }
                          } catch (e, s) {
                            Logs().e('获取表情数据失败: $imageCode', e, s);
                            // 返回占位错误显示
                            return ListTile(
                              title: Text('表情加载错误: $imageCode',
                                style: TextStyle(color: theme.colorScheme.error),
                              ),
                            );
                          }
                          
                          final textEditingController = TextEditingController();
                          textEditingController.text = imageCode;
                          final useShortCuts =
                              (PlatformInfos.isWeb || PlatformInfos.isDesktop);
                          return ListTile(
                            leading: SizedBox(
                              width: 180.0,
                              child: Shortcuts(
                                shortcuts: !useShortCuts
                                    ? {}
                                    : {
                                        LogicalKeySet(LogicalKeyboardKey.enter):
                                            SubmitLineIntent(),
                                      },
                                child: Actions(
                                  actions: !useShortCuts
                                      ? {}
                                      : {
                                          SubmitLineIntent: CallbackAction(
                                            onInvoke: (i) {
                                              try {
                                                controller.submitImageAction(
                                                  imageCode,
                                                  textEditingController.text,
                                                  image!,
                                                  textEditingController,
                                                );
                                              } catch (e, s) {
                                                Logs().e('提交表情修改失败', e, s);
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('修改失败，请重试')),
                                                );
                                              }
                                              return null;
                                            },
                                          ),
                                        },
                                  child: TextField(
                                    readOnly: controller.readonly,
                                    controller: textEditingController,
                                    autocorrect: false,
                                    minLines: 1,
                                    maxLines: 1,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceVariant,
                                      hintText: L10n.of(context).emoteShortcode,
                                      prefixText: ': ',
                                      prefixStyle: TextStyle(
                                        color: theme.colorScheme.secondary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    onSubmitted: (s) {
                                      try {
                                        controller.submitImageAction(
                                          imageCode,
                                          s,
                                          image!,
                                          textEditingController,
                                        );
                                      } catch (e, s) {
                                        Logs().e('提交表情修改失败', e, s);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('修改失败，请重试')),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                            title: _EmoteImage(image!.url),
                            trailing: controller.readonly
                                ? null
                                : InkWell(
                                    onTap: () {
                                      try {
                                        controller.removeImageAction(imageCode);
                                      } catch (e, s) {
                                        Logs().e('删除表情失败', e, s);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('删除失败，请重试')),
                                        );
                                      }
                                    },
                                    child: const Icon(
                                      Icons.delete_outlined,
                                      color: Colors.red,
                                      size: 32.0,
                                    ),
                                  ),
                          );
                        },
                      ),
              ],
            );
          }
        ),
      ),
    );
  }
}

class _EmoteImage extends StatelessWidget {
  final Uri mxc;

  const _EmoteImage(this.mxc);

  @override
  Widget build(BuildContext context) {
    const size = 38.0;
    return SizedBox.square(
      dimension: size,
      child: MxcImage(
        uri: mxc,
        fit: BoxFit.contain,
        width: size,
        height: size,
        isThumbnail: false,
      ),
    );
  }
}

class _ImagePicker extends StatefulWidget {
  final ValueNotifier<ImagePackImageContent?> controller;

  final void Function(ValueNotifier<ImagePackImageContent?>) onPressed;

  const _ImagePicker({required this.controller, required this.onPressed});

  @override
  _ImagePickerState createState() => _ImagePickerState();
}

class _ImagePickerState extends State<_ImagePicker> {
  @override
  Widget build(BuildContext context) {
    if (widget.controller.value == null) {
      return ElevatedButton(
        onPressed: () => widget.onPressed(widget.controller),
        child: Text(L10n.of(context).pickImage),
      );
    } else {
      return _EmoteImage(widget.controller.value!.url);
    }
  }
}

class SubmitLineIntent extends Intent {}
