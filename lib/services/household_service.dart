import 'package:cloud_firestore/cloud_firestore.dart';

/// Basic household details for display (name + member count).
class HouseholdInfo {
  const HouseholdInfo({
    this.id,
    required this.name,
    required this.memberCount,
    this.ownerId,
    this.memberIds = const [],
  });

  final String? id;
  final String name;
  final int memberCount;
  final String? ownerId;
  final List<String> memberIds;
}

/// A household member for the management list.
class HouseholdMember {
  const HouseholdMember({
    required this.uid,
    required this.name,
    required this.isOwner,
  });

  final String uid;
  final String name;
  final bool isOwner;
}

/// Manages the households a user belongs to (supports multiple).
///
/// Firestore layout:
///   users/{uid}      -> { householdIds: [id...], activeHouseholdId, name,
///                         householdId (legacy mirror of active) }
///   households/{id}  -> { name, members: [uid...], createdAt }
class HouseholdService {
  HouseholdService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Reads the user's household IDs + active id, migrating the legacy single
  /// `householdId` field into the list form when needed.
  ({List<String> ids, String? active}) _parseUser(
      Map<String, dynamic>? data) {
    if (data == null) return (ids: const [], active: null);
    final ids = ((data['householdIds'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final legacy = data['householdId'] as String?;
    if (ids.isEmpty && legacy != null && legacy.isNotEmpty) {
      return (ids: [legacy], active: legacy);
    }
    var active = data['activeHouseholdId'] as String?;
    if ((active == null || !ids.contains(active)) && ids.isNotEmpty) {
      active = ids.first;
    }
    return (ids: ids, active: active);
  }

  /// Returns the display name stored in the user's Firestore profile, or null.
  Future<String?> getUserName(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.data()?['name'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Real-time stream of the user's *effective active* household ID.
  ///
  /// Watches the user's profile, resolves the active household, then verifies
  /// the user is still a member. If removed, falls back to another household
  /// they belong to, or null (routes to setup).
  Stream<String?> watchHouseholdId(String uid) {
    return _db.collection('users').doc(uid).snapshots().asyncMap((doc) async {
      final parsed = _parseUser(doc.data());
      if (parsed.ids.isEmpty) return null;
      // Prefer active; verify membership, else try others.
      final candidates = <String>[
        if (parsed.active != null) parsed.active!,
        ...parsed.ids.where((id) => id != parsed.active),
      ];
      for (final id in candidates) {
        try {
          final household = await _db.collection('households').doc(id).get();
          final members =
              ((household.data()?['members'] as List?) ?? const [])
                  .whereType<String>();
          if (members.contains(uid)) return id;
        } catch (_) {
          // Can't verify (offline) — accept the active candidate.
          return id;
        }
      }
      return null;
    });
  }

  /// One-time repair: finds all households the user is actually a member of
  /// (via Firestore query) and ensures they're in the user's householdIds list.
  /// Fixes the case where a legacy single-householdId was lost on migration.
  Future<void> repairMemberships(String uid) async {
    try {
      final snap = await _db
          .collection('households')
          .where('members', arrayContains: uid)
          .get();
      final foundIds = snap.docs.map((d) => d.id).toSet();
      if (foundIds.isEmpty) return;
      final userDoc = await _db.collection('users').doc(uid).get();
      final parsed = _parseUser(userDoc.data());
      final current = parsed.ids.toSet();
      if (foundIds.difference(current).isEmpty) return; // nothing missing
      final merged = {...current, ...foundIds}.toList();
      final active = parsed.active != null && merged.contains(parsed.active!)
          ? parsed.active!
          : merged.first;
      await _db.collection('users').doc(uid).set({
        'householdIds': merged,
        'activeHouseholdId': active,
        'householdId': active,
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-critical; will try again next launch.
    }
  }

  /// Streams the list of households the user belongs to (for the switcher).
  Stream<List<HouseholdInfo>> watchMemberships(String uid) {
    return _db.collection('users').doc(uid).snapshots().asyncMap((doc) async {
      final parsed = _parseUser(doc.data());
      final result = <HouseholdInfo>[];
      for (final id in parsed.ids) {
        try {
          final h = await _db.collection('households').doc(id).get();
          final data = h.data();
          if (data == null) continue;
          final members = ((data['members'] as List?) ?? const [])
              .whereType<String>()
              .toList();
          if (!members.contains(uid)) continue; // removed elsewhere
          result.add(HouseholdInfo(
            id: id,
            name: (data['name'] ?? 'Household') as String,
            memberCount: members.length,
            ownerId: members.isNotEmpty ? members.first : null,
            memberIds: members,
          ));
        } catch (_) {
          // skip unreadable
        }
      }
      return result;
    });
  }

  /// Sets which household is currently active for the user.
  Future<void> setActiveHousehold({
    required String uid,
    required String householdId,
  }) async {
    await _db.collection('users').doc(uid).set({
      'activeHouseholdId': householdId,
      'householdId': householdId, // legacy mirror
    }, SetOptions(merge: true));
  }

  /// Real-time stream of a household's display info (name + member count).
  Stream<HouseholdInfo?> watchHousehold(String householdId) {
    return _db
        .collection('households')
        .doc(householdId)
        .snapshots()
        .map((doc) {
      final data = doc.data();
      if (data == null) return null;
      final members = ((data['members'] as List?) ?? const [])
          .whereType<String>()
          .toList();
      return HouseholdInfo(
        id: householdId,
        name: (data['name'] ?? 'Household') as String,
        memberCount: members.length,
        ownerId: members.isNotEmpty ? members.first : null,
        memberIds: members,
      );
    });
  }

  /// Fetches the members of a household, resolving display names from the
  /// `users` collection where available. The creator is marked as owner.
  Future<List<HouseholdMember>> getMembers(String householdId) async {
    final doc = await _db.collection('households').doc(householdId).get();
    final data = doc.data();
    if (data == null) return const [];
    final memberIds = ((data['members'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final ownerId = memberIds.isNotEmpty ? memberIds.first : null;

    final members = <HouseholdMember>[];
    for (final uid in memberIds) {
      String name = 'Member';
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        final n = userDoc.data()?['name'] as String?;
        if (n != null && n.trim().isNotEmpty) name = n.trim();
      } catch (_) {
        // Fall back to generic label.
      }
      members.add(HouseholdMember(
        uid: uid,
        name: name,
        isOwner: uid == ownerId,
      ));
    }
    return members;
  }

  /// Removes a member from a household's members array.
  Future<void> removeMember({
    required String householdId,
    required String memberUid,
  }) async {
    await _db.collection('households').doc(householdId).update({
      'members': FieldValue.arrayRemove([memberUid]),
    });
  }

  /// Returns the user's existing household IDs, migrating a legacy single
  /// `householdId` into the list form so it isn't lost when adding another.
  Future<List<String>> _existingHouseholdIds(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final parsed = _parseUser(doc.data());
    return parsed.ids;
  }

  /// Creates a new household, adds it to the user's list, and makes it active.
  Future<String> createHousehold({
    required String uid,
    required String name,
    String? displayName,
  }) async {
    final existing = await _existingHouseholdIds(uid);
    final ref = _db.collection('households').doc();
    await ref.set({
      'name': name.trim(),
      'members': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
    final ids = {...existing, ref.id}.toList();
    await _db.collection('users').doc(uid).set({
      'householdIds': ids,
      'activeHouseholdId': ref.id,
      'householdId': ref.id, // legacy mirror
      if (displayName != null && displayName.trim().isNotEmpty)
        'name': displayName.trim(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  /// Joins an existing household (adds to the user's list, makes it active).
  Future<void> joinHousehold({
    required String uid,
    required String householdId,
    String? displayName,
  }) async {
    final ref = _db.collection('households').doc(householdId.trim());
    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('No household found with that code.');
    }
    final existing = await _existingHouseholdIds(uid);
    await ref.update({
      'members': FieldValue.arrayUnion([uid]),
    });
    final ids = {...existing, ref.id}.toList();
    await _db.collection('users').doc(uid).set({
      'householdIds': ids,
      'activeHouseholdId': ref.id,
      'householdId': ref.id, // legacy mirror
      if (displayName != null && displayName.trim().isNotEmpty)
        'name': displayName.trim(),
    }, SetOptions(merge: true));
  }

  /// Leaves a household: removes the user from its members and from their
  /// list. If it was active, the next household (if any) becomes active.
  Future<void> leaveHousehold({
    required String uid,
    required String householdId,
  }) async {
    await _db.collection('households').doc(householdId).update({
      'members': FieldValue.arrayRemove([uid]),
    });
    final userRef = _db.collection('users').doc(uid);
    final userDoc = await userRef.get();
    final parsed = _parseUser(userDoc.data());
    final remaining = parsed.ids.where((id) => id != householdId).toList();
    final newActive = remaining.isEmpty ? null : remaining.first;
    await userRef.set({
      'householdIds': remaining,
      'activeHouseholdId': newActive,
      'householdId': newActive, // legacy mirror
    }, SetOptions(merge: true));
  }
}
