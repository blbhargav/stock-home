import 'package:cloud_firestore/cloud_firestore.dart';

/// Basic household details for display (name + member count).
class HouseholdInfo {
  const HouseholdInfo({
    required this.name,
    required this.memberCount,
    this.ownerId,
    this.memberIds = const [],
  });

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

/// Manages the household a user belongs to.
///
/// Firestore layout:
///   users/{uid}            -> { householdId }
///   households/{id}        -> { name, members: [uid...], createdAt }
class HouseholdService {
  HouseholdService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Returns the household ID linked to the user, or null if none.
  Future<String?> getHouseholdId(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['householdId'] as String?;
  }

  /// Real-time stream of the user's linked household ID.
  Stream<String?> watchHouseholdId(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.data()?['householdId'] as String?);
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
        name: (data['name'] ?? 'Household') as String,
        memberCount: members.length,
        // The creator (first member) is treated as the owner.
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

  /// Removes a member from the household. Only meaningful when performed by
  /// the owner (enforced by security rules in production).
  Future<void> removeMember({
    required String householdId,
    required String memberUid,
  }) async {
    await _db.collection('households').doc(householdId).update({
      'members': FieldValue.arrayRemove([memberUid]),
    });
    // Clear the removed user's link so they return to household setup.
    await _db.collection('users').doc(memberUid).set({
      'householdId': null,
    }, SetOptions(merge: true));
  }

  /// Creates a new household and links the user to it. Returns the new ID.
  Future<String> createHousehold({
    required String uid,
    required String name,
    String? displayName,
  }) async {
    final ref = _db.collection('households').doc();
    await ref.set({
      'name': name.trim(),
      'members': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('users').doc(uid).set({
      'householdId': ref.id,
      if (displayName != null && displayName.trim().isNotEmpty)
        'name': displayName.trim(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  /// Joins an existing household by its ID. Throws if it does not exist.
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
    await ref.update({
      'members': FieldValue.arrayUnion([uid]),
    });
    await _db.collection('users').doc(uid).set({
      'householdId': ref.id,
      if (displayName != null && displayName.trim().isNotEmpty)
        'name': displayName.trim(),
    }, SetOptions(merge: true));
  }

  /// Removes the user from their household and clears their link, so they can
  /// create or join another one.
  Future<void> leaveHousehold({
    required String uid,
    required String householdId,
  }) async {
    await _db.collection('households').doc(householdId).update({
      'members': FieldValue.arrayRemove([uid]),
    });
    await _db.collection('users').doc(uid).set({
      'householdId': null,
    }, SetOptions(merge: true));
  }
}
