import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/utils/matrix_sdk_extensions/cached_futures.dart';
import '../../widgets/matrix.dart';

class EncryptionButton extends StatelessWidget {
  final Room room;
  const EncryptionButton(this.room, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncUpdate>(
      stream: Matrix.of(context)
          .client
          .onSync
          .stream
          .where((s) => s.deviceLists != null),
      builder: (context, snapshot) {
        // The device list changed: recompute the health state next time.
        invalidateEncryptionHealthCache(room);
        return FutureBuilder<EncryptionHealthState>(
          // Memoized: iterating all members' device keys is expensive and must
          // not run on every rebuild of the app bar.
          future: room.encrypted
              ? calcEncryptionHealthStateCached(room)
              : Future.value(EncryptionHealthState.allVerified),
          builder: (BuildContext context, snapshot) => IconButton(
            tooltip: room.encrypted
                ? L10n.of(context).encrypted
                : L10n.of(context).encryptionNotEnabled,
            icon: Icon(
              room.encrypted ? Icons.lock_outlined : Icons.lock_open_outlined,
              size: 20,
              color: room.joinRules != JoinRules.public && !room.encrypted
                  ? Colors.red
                  : room.joinRules != JoinRules.public &&
                          snapshot.data ==
                              EncryptionHealthState.unverifiedDevices
                      ? Colors.orange
                      : null,
            ),
            onPressed: () => context.go('/rooms/${room.id}/encryption'),
          ),
        );
      },
    );
  }
}
