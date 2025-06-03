import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:yomi/config/themes.dart';
import 'package:yomi/pages/chat/chat.dart';
import 'package:yomi/utils/room_status_extension.dart';
import 'package:yomi/widgets/avatar.dart';
import 'package:yomi/widgets/matrix.dart';

class SeenByRow extends StatelessWidget {
  final ChatController controller;
  const SeenByRow(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final seenByUsers = controller.room.getSeenByUsers(controller.timeline!);
    const maxAvatars = 7;
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      child: AnimatedContainer(
        constraints:
            const BoxConstraints(maxWidth: LyiThemes.columnWidth * 2.5),
        height: seenByUsers.isEmpty ? 0 : 24,
        duration: seenByUsers.isEmpty
            ? Duration.zero
            : LyiThemes.animationDuration,
        curve: LyiThemes.animationCurve,
        alignment: controller.timeline!.events.isNotEmpty &&
                controller.timeline!.events.first.senderId ==
                    Matrix.of(context).client.userID
            ? Alignment.topRight
            : Alignment.topLeft,
        padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
        child: Wrap(
          spacing: 4,
          children: [
            ...(seenByUsers.length > maxAvatars
                    ? seenByUsers.sublist(0, maxAvatars)
                    : seenByUsers)
                .map(
              (user) => Avatar(
                mxContent: user.avatarUrl,
                name: user.calcDisplayname(),
                size: 16,
              ),
            ),
            if (seenByUsers.length > maxAvatars)
              SizedBox(
                width: 16,
                height: 16,
                child: Material(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(32),
                  child: Center(
                    child: Text(
                      '+${seenByUsers.length - maxAvatars}',
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReadReceipt extends StatelessWidget {
  final bool hasReadReceipts;
  final bool ownMessage;
  final int receiptsCount;
  final List<Receipt> receipts;
  
  const ReadReceipt({
    super.key,
    required this.hasReadReceipts,
    required this.ownMessage,
    required this.receiptsCount,
    required this.receipts,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasReadReceipts) return const SizedBox.shrink();
    
    final theme = Theme.of(context);
    
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showReadReceiptUsers(context),
        child: AnimatedContainer(
          duration: LyiThemes.animationDuration,
          curve: LyiThemes.animationCurve,
          width: 18,
          height: 18,
          margin: EdgeInsets.zero,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
            border: Border.all(
              color: theme.colorScheme.background,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withOpacity(0.3),
                blurRadius: 2,
                spreadRadius: 0.5,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: receiptsCount > 1
                ? Text(
                    '+${receiptsCount - 1}',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : Icon(
                    Icons.check,
                    size: 12,
                    color: theme.colorScheme.onPrimary,
                  ),
          ),
        ),
      ),
    );
  }
  
  void _showReadReceiptUsers(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('已读用户'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: receipts.length,
              itemBuilder: (context, index) {
                final receipt = receipts[index];
                return ListTile(
                  leading: Avatar(
                    mxContent: receipt.user.avatarUrl,
                    name: receipt.user.calcDisplayname(),
                    size: 32,
                  ),
                  title: Text(receipt.user.calcDisplayname()),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}
