import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:yomi/config/app_config.dart';
import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/utils/date_time_extension.dart';
import 'package:yomi/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:yomi/widgets/avatar.dart';

class RoomCreationStateEvent extends StatelessWidget {
  final Event event;

  const RoomCreationStateEvent({required this.event, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final matrixLocals = MatrixLocals(l10n);
    final theme = Theme.of(context);
    final roomName = event.room.getLocalizedDisplayname(matrixLocals);
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 256),
          child: Material(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius * 1.5),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Avatar(
                    mxContent: event.room.avatar,
                    name: roomName,
                    size: Avatar.defaultSize * 2,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    roomName,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${event.originServerTs.localizedTime(context)} | ${l10n.countParticipants((event.room.summary.mJoinedMemberCount ?? 1) + (event.room.summary.mInvitedMemberCount ?? 0))}',
                    style: theme.textTheme.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
