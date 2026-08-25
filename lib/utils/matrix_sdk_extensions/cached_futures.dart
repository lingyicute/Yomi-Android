import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:matrix/matrix.dart';

/// Performance helpers which memoize frequently used async lookups on SDK
/// objects.
///
/// The SDK objects ([Event], [Room], [Client]) are long-lived, which allows
/// us to cache Futures on them in [Expando]s. Expandos hold their keys
/// weakly, so nothing here prevents garbage collection of SDK objects.
///
/// Using these helpers in `FutureBuilder`s prevents re-creating a Future on
/// every `build()` call. Re-creating Futures is a major jank source: each new
/// Future restarts the async work and triggers an extra `setState` once it
/// completes, effectively doubling the rebuild count of every message bubble.

/// Evicts [key] from [expando] when [future] completes with an error, so a
/// failed lookup is retried on the next read instead of being cached forever.
void _evictOnError<T>(Future<T> future, void Function() evict) {
  unawaited(
    future.then<void>(
      (_) {},
      onError: (_) => evict(),
    ),
  );
}

final Expando<Future<User?>> _fetchSenderUserFutures = Expando('fetchSender');

/// Cached version of [Event.fetchSenderUser]. The returned Future is created
/// at most once per [Event] (unless it failed) which makes it safe to use
/// directly inside `FutureBuilder`s in the hot timeline build path.
Future<User?> fetchSenderUserCached(Event event) {
  final cached = _fetchSenderUserFutures[event];
  if (cached != null) return cached;
  final future = event.fetchSenderUser();
  _fetchSenderUserFutures[event] = future;
  _evictOnError(future, () => _fetchSenderUserFutures[event] = null);
  return future;
}

final Expando<Future<List<User>>> _loadHeroUsersFutures = Expando('heroUsers');

/// Cached version of [Room.loadHeroUsers]. Only runs once per [Room]
/// instance instead of on every rebuild of a chat list item.
Future<List<User>> loadHeroUsersCached(Room room) {
  final cached = _loadHeroUsersFutures[room];
  if (cached != null) return cached;
  final future = room.loadHeroUsers();
  _loadHeroUsersFutures[room] = future;
  _evictOnError(future, () => _loadHeroUsersFutures[room] = null);
  return future;
}

final Expando<Future<Profile>> _ownProfileFutures = Expando('ownProfile');

/// Cached version of [Client.fetchOwnProfile].
///
/// The uncached call performs an HTTP request, so calling it inside `build()`
/// (as was done before) fires a network request on every rebuild — e.g. on
/// every keystroke in the chat input row.
Future<Profile> fetchOwnProfileCached(Client client) {
  final cached = _ownProfileFutures[client];
  if (cached != null) return cached;
  final future = client.fetchOwnProfile();
  _ownProfileFutures[client] = future;
  _evictOnError(future, () => _ownProfileFutures[client] = null);
  return future;
}

/// Invalidates the cached own profile, e.g. after the user changed their
/// avatar or displayname.
void invalidateOwnProfileCache(Client client) {
  _ownProfileFutures[client] = null;
}

final Expando<Future<Uint8List>> _fileBytesFutures = Expando('fileBytes');

/// Cached version of [XFile.readAsBytes]. Reading several megabytes from
/// disk on every rebuild of a preview dialog (as was done before) causes
/// noticeable jank and memory churn for large attachments.
Future<Uint8List> readAsBytesCached(XFile file) {
  final cached = _fileBytesFutures[file];
  if (cached != null) return cached;
  final future = file.readAsBytes();
  _fileBytesFutures[file] = future;
  _evictOnError(future, () => _fileBytesFutures[file] = null);
  return future;
}

final Expando<Map<String, Future<Profile>>> _profileFutures =
    Expando('profiles');

/// Cached version of [Client.getProfileFromUserId] per (client, userId).
///
/// The SDK call performs an HTTP request and was previously invoked inline in
/// `FutureBuilder`s, spamming the homeserver with a request per rebuild
/// (e.g. every 3 seconds for every presence avatar in the status list).
Future<Profile> getProfileCached(Client client, String userId) {
  final clientCache = _profileFutures[client] ??= <String, Future<Profile>>{};
  final cached = clientCache[userId];
  if (cached != null) return cached;
  final future = client.getProfileFromUserId(userId);
  clientCache[userId] = future;
  _evictOnError(future, () => clientCache.remove(userId));
  return future;
}

/// Invalidates a cached profile, e.g. when a member event changed it.
void invalidateProfileCache(Client client, String userId) {
  _profileFutures[client]?.remove(userId);
}

final Expando<Map<String, Future<Event?>>> _eventsByIdFutures =
    Expando('eventsById');

/// Cached version of [Room.getEventById] for remote events.
///
/// Locally stored events are served from the in-memory map anyway; remote
/// lookups hit the database so they should not be re-triggered on every
/// rebuild of e.g. the pinned events banner.
Future<Event?> getEventByIdCached(Room room, String eventId) {
  final roomCache = _eventsByIdFutures[room] ??= <String, Future<Event?>>{};
  final cached = roomCache[eventId];
  if (cached != null) return cached;
  final future = room.getEventById(eventId);
  roomCache[eventId] = future;
  _evictOnError(future, () => roomCache.remove(eventId));
  return future;
}

/// Short-lived cache for [Event.receipts].
///
/// The SDK getter iterates over *all* receipts of the room and re-parses them
/// from the account data on every access. The timeline rebuilds every visible
/// message on each event update, so a room with a busy receipt stream used to
/// pay O(receipts x own messages) per rebuild. A sub-second TTL keeps the UI
/// fresh while collapsing the burst of reads inside one rebuild.
class _ReceiptsCacheEntry {
  final List<Receipt> receipts;
  final DateTime at;

  _ReceiptsCacheEntry(this.receipts, this.at);
}

final Expando<_ReceiptsCacheEntry> _receiptsCache = Expando('receipts');

const Duration _receiptsCacheTtl = Duration(milliseconds: 1500);

List<Receipt> receiptsCached(Event event) {
  final now = DateTime.now();
  final cached = _receiptsCache[event];
  if (cached != null && now.difference(cached.at) < _receiptsCacheTtl) {
    return cached.receipts;
  }
  final receipts = event.receipts;
  _receiptsCache[event] = _ReceiptsCacheEntry(receipts, now);
  return receipts;
}

final Expando<Future<EncryptionHealthState>> _encryptionHealthFutures =
    Expando('encryptionHealth');

/// Cached version of [Room.calcEncryptionHealthState]. Iterating over all
/// room members' device keys is expensive; the result only needs to be
/// recomputed when the device list changed (the caller's StreamBuilder
/// invalidates this cache in that case). This prevents recomputation on
/// unrelated rebuilds.
Future<EncryptionHealthState> calcEncryptionHealthStateCached(Room room) {
  final cached = _encryptionHealthFutures[room];
  if (cached != null) return cached;
  final future = room.calcEncryptionHealthState();
  _encryptionHealthFutures[room] = future;
  _evictOnError(future, () => _encryptionHealthFutures[room] = null);
  return future;
}

/// Call when the device list changed to force recomputation.
void invalidateEncryptionHealthCache(Room room) {
  _encryptionHealthFutures[room] = null;
}
