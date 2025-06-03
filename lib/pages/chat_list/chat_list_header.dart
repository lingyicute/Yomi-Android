import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:yomi/config/themes.dart';
import 'package:yomi/l10n/l10n.dart';
import 'package:yomi/pages/chat_list/chat_list.dart';
import 'package:yomi/pages/chat_list/client_chooser_button.dart';
import 'package:yomi/utils/sync_status_localization.dart';
import '../../widgets/matrix.dart';

class ChatListHeader extends StatelessWidget implements PreferredSizeWidget {
  final ChatListController controller;
  final bool globalSearch;

  const ChatListHeader({
    super.key,
    required this.controller,
    this.globalSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;

    return SliverAppBar(
      floating: true,
      toolbarHeight: 72,
      pinned: LyiThemes.isColumnMode(context),
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      automaticallyImplyLeading: false,
      title: StreamBuilder(
        stream: client.onSyncStatus.stream,
        builder: (context, snapshot) {
          final status = client.onSyncStatus.value ??
              const SyncStatusUpdate(SyncStatus.waitingForResponse);
          final hide = client.onSync.value != null &&
              status.status != SyncStatus.error &&
              client.prevBatch != null;
          return TextField(
            controller: controller.searchController,
            focusNode: controller.searchFocusNode,
            textInputAction: TextInputAction.search,
            onChanged: (text) => controller.onSearchEnter(
              text,
              globalSearch: globalSearch,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.colorScheme.secondaryContainer,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(99),
              ),
              contentPadding: EdgeInsets.zero,
              hintText: hide
                  ? L10n.of(context).searchChatsRooms
                  : status.calcLocalizedString(context),
              hintStyle: TextStyle(
                color: status.error != null
                    ? theme.colorScheme.error
                    : theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.normal,
              ),
              prefixIcon: hide
                  ? controller.isSearchMode
                      ? IconButton(
                          tooltip: L10n.of(context).cancel,
                          icon: const Icon(Icons.close_outlined),
                          onPressed: controller.cancelSearch,
                          color: theme.colorScheme.onPrimaryContainer,
                        )
                      : IconButton(
                          onPressed: controller.startSearch,
                          icon: Icon(
                            Icons.search_outlined,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        )
                  : Container(
                      margin: const EdgeInsets.all(12),
                      width: 8,
                      height: 8,
                      child: Center(
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                          value: status.progress,
                          valueColor: status.error != null
                              ? AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.error,
                                )
                              : null,
                        ),
                      ),
                    ),
              suffixIcon: controller.isSearchMode && controller.isSearching
                  ? Container(
                      padding: const EdgeInsets.all(16.0),
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      child: const AspectRatio(
                        aspectRatio: 1.0,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : SizedBox(
                      width: 0,
                      child: ClientChooserButton(controller),
                    ),
            ),
          );
        },
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
