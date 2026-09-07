import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final name = TextEditingController();
  final search = TextEditingController();
  final selected = <String>{};
  String query = '';
  bool loading = false;

  @override
  void dispose() {
    name.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> create() async {
    final user = FirebaseAuth.instance.currentUser;
    final groupName = name.text.trim();
    if (user == null || groupName.isEmpty) {
      _message('Enter a group name.');
      return;
    }
    if (selected.isEmpty) {
      _message('Select at least one member.');
      return;
    }

    setState(() => loading = true);
    try {
      final members = <String>[user.uid, ...selected];
      final docs = await Future.wait(
        members.map((uid) => FirebaseFirestore.instance.collection('users').doc(uid).get()),
      );
      final names = <String, String>{};
      final emails = <String, String>{};
      for (final doc in docs) {
        final data = doc.data() ?? {};
        names[doc.id] = (data['name'] ?? data['email'] ?? 'User').toString();
        emails[doc.id] = (data['email'] ?? '').toString();
      }

      final ref = FirebaseFirestore.instance.collection('chats').doc();
      await ref.set({
        'type': 'group',
        'name': groupName,
        'participants': members,
        'participantNames': names,
        'participantEmails': emails,
        'adminId': user.uid,
        'admins': [user.uid],
        'lastMessage': 'Group created',
        'lastMessageBy': user.uid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await ref.collection('messages').add({
        'senderUid': user.uid,
        'senderName': user.displayName ?? user.email ?? 'Admin',
        'text': 'Group created',
        'type': 'system',
        'createdAt': FieldValue.serverTimestamp(),
        'edited': false,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _message('Unable to create group: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Group')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: name, maxLength: 50, decoration: const InputDecoration(labelText: 'Group name', border: OutlineInputBorder()))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(controller: search, onChanged: (v) => setState(() => query = v.trim().toLowerCase()), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search members...'))),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('users').where('active', isEqualTo: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Unable to load staff.\n${snapshot.error}'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final me = FirebaseAuth.instance.currentUser?.uid;
              final docs = snapshot.data!.docs.where((doc) {
                if (doc.id == me) return false;
                final data = doc.data();
                final text = '${data['name'] ?? ''} ${data['email'] ?? ''}'.toLowerCase();
                return text.contains(query);
              }).toList();
              if (docs.isEmpty) return const Center(child: Text('No staff found.'));
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final n = (data['name'] ?? data['email'] ?? 'User').toString();
                  final checked = selected.contains(doc.id);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: loading ? null : (value) => setState(() => value == true ? selected.add(doc.id) : selected.remove(doc.id)),
                    secondary: CircleAvatar(child: Text(n.isEmpty ? '?' : n[0].toUpperCase())),
                    title: Text(n),
                    subtitle: Text((data['email'] ?? '').toString()),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: loading ? null : create, child: loading ? const CircularProgressIndicator() : Text('CREATE GROUP (${selected.length})'))),
          ),
        ),
      ]),
    );
  }
}
