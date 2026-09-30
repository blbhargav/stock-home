import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/household_service.dart';

/// Shows household members. The owner can remove other members.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  late Future<List<HouseholdMember>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AuthProvider>().getMembers();
  }

  void _reload() {
    setState(() {
      _future = context.read<AuthProvider>().getMembers();
    });
  }

  Future<void> _remove(HouseholdMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          '${member.name} will be removed from the household and lose access '
          'to the shared list. They can rejoin with the household code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().removeMember(member.uid);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final myUid = auth.user?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Household members')),
      body: FutureBuilder<List<HouseholdMember>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final members = snapshot.data ?? const [];
          if (members.isEmpty) {
            return const Center(child: Text('No members found.'));
          }
          final iAmOwner = auth.isHouseholdOwner;

          return ListView.separated(
            itemCount: members.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = members[index];
              final isMe = m.uid == myUid;
              final scheme = Theme.of(context).colorScheme;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(_initial(m.name)),
                ),
                title: Text(isMe ? '${m.name} (You)' : m.name),
                subtitle: m.isOwner ? const Text('Owner') : null,
                trailing: (iAmOwner && !m.isOwner)
                    ? IconButton(
                        tooltip: 'Remove member',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () => _remove(m),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  String _initial(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }
}
