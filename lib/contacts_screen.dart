import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ContactsScreen extends StatefulWidget {
  final bool showAppBar;

  const ContactsScreen({
    super.key,
    this.showAppBar = true,
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _createGroup() async {
    final controller = TextEditingController();

    final groupName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Group name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(dialogContext, name);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (groupName == null || groupName.trim().isEmpty) return;

    await _firestore.collection('groups').add({
      'name': groupName.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Group created successfully')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Contacts'),
              actions: [
                IconButton(
                  onPressed: _createGroup,
                  icon: const Icon(Icons.group_add),
                ),
              ],
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data?.docs ?? [];

          if (users.isEmpty) {
            return const Center(child: Text('No contacts found'));
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index].data();
              final name = (user['name'] ?? 'User').toString();
              final email = (user['email'] ?? '').toString();
              final online = user['online'] == true;

              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    name.isEmpty ? '?' : name[0].toUpperCase(),
                  ),
                ),
                title: Text(name),
                subtitle: Text(
                  online
                      ? 'Online'
                      : email.isEmpty
                          ? 'Offline'
                          : email,
                ),
                trailing: online
                    ? const Icon(
                        Icons.circle,
                        color: Colors.green,
                        size: 12,
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}