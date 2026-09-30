import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/household_service.dart';

/// Exposes authentication state and the user's linked household to the UI.
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    AuthService? authService,
    HouseholdService? householdService,
  })  : _authService = authService ?? AuthService(),
        _householdService = householdService ?? HouseholdService() {
    _authSub = _authService.authStateChanges().listen(_onAuthChanged);
  }

  final AuthService _authService;
  final HouseholdService _householdService;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<String?>? _householdSub;

  User? _user;
  String? _householdId;
  bool _initialized = false;

  User? get user => _user;
  String? get householdId => _householdId;
  bool get isSignedIn => _user != null;
  bool get hasHousehold => _householdId != null;
  bool get initialized => _initialized;

  void _onAuthChanged(User? user) {
    _user = user;
    _householdSub?.cancel();
    _householdSub = null;
    _householdId = null;

    if (user != null) {
      _householdSub =
          _householdService.watchHouseholdId(user.uid).listen((id) {
        _householdId = id;
        _initialized = true;
        notifyListeners();
      });
    } else {
      _initialized = true;
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) {
    return _authService.signIn(email: email, password: password);
  }

  Future<void> register(String email, String password, String displayName) {
    return _authService.register(
      email: email,
      password: password,
      displayName: displayName,
    );
  }

  Future<void> createHousehold(String name) async {
    final uid = _user?.uid;
    if (uid == null) return;
    await _householdService.createHousehold(
      uid: uid,
      name: name,
      displayName: _user?.displayName ?? _user?.email,
    );
  }

  Future<void> joinHousehold(String householdId) async {
    final uid = _user?.uid;
    if (uid == null) return;
    await _householdService.joinHousehold(
      uid: uid,
      householdId: householdId,
      displayName: _user?.displayName ?? _user?.email,
    );
  }

  /// Whether the current user is the household owner (its creator).
  bool get isHouseholdOwner => _householdOwnerId != null && _householdOwnerId == _user?.uid;
  String? _householdOwnerId;

  Future<List<HouseholdMember>> getMembers() async {
    final id = _householdId;
    if (id == null) return const [];
    final members = await _householdService.getMembers(id);
    final owners = members.where((m) => m.isOwner).toList();
    _householdOwnerId = owners.isEmpty ? null : owners.first.uid;
    return members;
  }

  Future<void> removeMember(String memberUid) async {
    final id = _householdId;
    if (id == null) return;
    await _householdService.removeMember(
      householdId: id,
      memberUid: memberUid,
    );
  }

  /// Leaves the current household so the user can create or join another.
  Future<void> leaveHousehold() async {
    final uid = _user?.uid;
    final id = _householdId;
    if (uid == null || id == null) return;
    await _householdService.leaveHousehold(uid: uid, householdId: id);
  }

  /// Real-time stream of the current household's display info.
  Stream<HouseholdInfo?> watchHousehold() {
    final id = _householdId;
    if (id == null) return Stream.value(null);
    return _householdService.watchHousehold(id);
  }

  Future<void> signOut() => _authService.signOut();

  Future<void> sendPasswordResetEmail(String email) {
    return _authService.sendPasswordResetEmail(email);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _householdSub?.cancel();
    super.dispose();
  }
}
