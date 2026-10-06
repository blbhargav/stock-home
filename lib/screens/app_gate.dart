import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import '../services/notification_service.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'household_setup_screen.dart';

/// Decides which screen to show based on auth and household state.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool _notificationPermissionRequested = false;

  void _requestNotificationPermissionOnce() {
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    // Fire after the frame so we're not in a build callback.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.requestPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (!auth.initialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!auth.isSignedIn) {
          return const AuthScreen();
        }

        if (!auth.hasHousehold) {
          return const HouseholdSetupScreen();
        }

        // Bind grocery stream and request notification permission once the
        // user reaches the main screen.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<GroceryProvider>().bindHousehold(auth.householdId);
        });
        _requestNotificationPermissionOnce();

        return const HomeScreen();
      },
    );
  }
}
