import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:yomi/config/app_config.dart';
import 'package:yomi/config/themes.dart';
import 'package:yomi/utils/stream_extension.dart';
import 'package:yomi/widgets/avatar.dart';
import 'package:yomi/widgets/hover_builder.dart';
import 'package:yomi/widgets/matrix.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';

class StatusMessageList extends StatelessWidget {
  final void Function() onStatusEdit;

  const StatusMessageList({
    required this.onStatusEdit,
    super.key,
  });

  static const double height = 116;

  void _onStatusTab(BuildContext context, Profile profile) {
    final client = Matrix.of(context).client;
    if (profile.userId == client.userID) return onStatusEdit();

    UserDialog.show(
      context: context,
      profile: profile,
    );
    return;
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    if (client.userID == null) {
      return const SizedBox.shrink();
    }
    
    final interestingPresences = client.interestingPresences;

    return StreamBuilder(
      stream: client.onSync.stream.rateLimit(const Duration(seconds: 3)),
      builder: (context, snapshot) {
        return AnimatedSize(
          duration: LyiThemes.animationDuration,
          curve: Curves.easeInOut,
          child: FutureBuilder<List<CachedPresence>>(
            initialData: client.userID != null 
                ? interestingPresences
                    // ignore: deprecated_member_use
                    .map((userId) => client.presences[userId])
                    .whereType<CachedPresence>()
                    .toList()
                : <CachedPresence>[],
            future: client.userID != null 
                ? Future.wait(
                    interestingPresences.map(
                      (userId) => client.fetchCurrentPresence(
                        userId,
                        fetchOnlyFromCached: true,
                      ),
                    ),
                  ) 
                : Future.value(<CachedPresence>[]),
            builder: (context, snapshot) {
              final presences = snapshot.data
                  ?.where(isInterestingPresence)
                  .toList();

              // If no other presences than the own entry is interesting, we
              // hide the presence header.
              if (presences == null || presences.length <= 1) {
                return const SizedBox.shrink();
              }

              // Make sure own entry is at the first position. Sort by last
              // active instead.
              presences.sort((a, b) {
                if (client.userID == null) {
                  return b.sortOrderDateTime.compareTo(a.sortOrderDateTime);
                }
                if (a.userid == client.userID) return -1;
                if (b.userid == client.userID) return 1;
                return b.sortOrderDateTime.compareTo(a.sortOrderDateTime);
              });

              return SizedBox(
                height: StatusMessageList.height,
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  scrollDirection: Axis.horizontal,
                  itemCount: presences.length,
                  itemBuilder: (context, i) => PresenceAvatar(
                    presence: presences[i],
                    height: StatusMessageList.height,
                    onTap: (profile) => _onStatusTab(context, profile),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class PresenceAvatar extends StatelessWidget {
  final CachedPresence presence;
  final double height;
  final void Function(Profile) onTap;

  const PresenceAvatar({
    required this.presence,
    required this.height,
    required this.onTap,
    super.key,
  });

  // 从状态消息中提取第一个emoji，如果没有则返回默认emoji
  String? _extractFirstEmoji(String? text) {
    if (text == null || text.isEmpty) {
      return null;
    }
    
    // 匹配Unicode emoji的正则表达式
    final emojiRegex = RegExp(
      r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])',
    );
    
    final matches = emojiRegex.allMatches(text);
    if (matches.isNotEmpty) {
      return matches.first.group(0);
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final avatarSize = height - 16 - 16 - 8;
    final client = Matrix.of(context).client;
    return FutureBuilder<Profile>(
      future: client.getProfileFromUserId(presence.userid),
      builder: (context, snapshot) {
        final theme = Theme.of(context);

        final profile = snapshot.data;
        final displayName = profile?.displayName ??
            presence.userid.localpart ??
            presence.userid;
        final statusMsg = presence.statusMsg;
        final statusEmoji = _extractFirstEmoji(statusMsg);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: SizedBox(
            width: avatarSize,
            child: Column(
              children: [
                HoverBuilder(
                  builder: (context, hovered) {
                    return AnimatedScale(
                      scale: hovered ? 1.15 : 1.0,
                      duration: LyiThemes.animationDuration,
                      curve: LyiThemes.animationCurve,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(avatarSize),
                        onTap: profile == null ? null : () => onTap(profile),
                        child: Material(
                          borderRadius: BorderRadius.circular(avatarSize),
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  gradient: presence.gradient,
                                  borderRadius:
                                      BorderRadius.circular(avatarSize),
                                ),
                                child: Avatar(
                                  name: displayName,
                                  mxContent: profile?.avatarUrl,
                                  size: avatarSize - 6,
                                ),
                              ),
                              if (presence.userid == client.userID)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: FloatingActionButton.small(
                                      heroTag: null,
                                      onPressed: () => onTap(
                                        profile ??
                                            Profile(userId: presence.userid),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.add_outlined,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              if (statusMsg != null)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(
                                        color: theme.colorScheme.background,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        statusEmoji ?? '💬',
                                        style: const TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    displayName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension on Client {
  Set<String> get interestingPresences {
    final allHeroes = rooms.map((room) => room.summary.mHeroes).fold(
      <String>{},
      (previousValue, element) => previousValue..addAll(element ?? {}),
    );
    if (userID != null) {
      allHeroes.add(userID!);
    }
    return allHeroes;
  }
}

bool isInterestingPresence(CachedPresence presence) =>
    !presence.presence.isOffline || (presence.statusMsg?.isNotEmpty ?? false);

extension on CachedPresence {
  DateTime get sortOrderDateTime =>
      lastActiveTimestamp ??
      (currentlyActive == true
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(0));

  LinearGradient get gradient => presence.isOnline == true
      ? LinearGradient(
          colors: [
            Colors.green,
            Colors.green.shade200,
            Colors.green.shade900,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : presence.isUnavailable
          ? LinearGradient(
              colors: [
                Colors.yellow,
                Colors.yellow.shade200,
                Colors.yellow.shade900,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : LinearGradient(
              colors: [
                Colors.grey,
                Colors.grey.shade200,
                Colors.grey.shade900,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            );
}
