import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/grocery_provider.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'household_setup_screen.dart';

/// Decides which screen to show based on auth and household state.
class AppGate extends StatelessWidget {
  const AppGate({super.key});

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

        // Keep the grocery stream bound to the active household.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<GroceryProvider>().bindHousehold(auth.householdId);
        });
        return const HomeScreen();
      },
    );
  }
}
