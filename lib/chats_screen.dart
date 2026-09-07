import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'group_create_screen.dart';
import 'contacts_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with SingleTickerProviderStateMixin {
  late final TabController tabs;
  final search = TextEditingController();
  String query = '';
  bool searching = false;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    tabs.dispose();
    search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      searching = !searching;
      if (!searching) {
        query = '';
        search.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                controller: search,
                autofocus: true,
                onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search chats...',
                  border: InputBorder.none,
                ),
              )
            : const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: _toggleSearch,
            icon: Icon(searching ? Icons.close : Icons.search),
          ),
          IconButton(
            tooltip: 'New group',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GroupCreateScreen()),
            ),
            icon: const Icon(Icons.group_add_outlined),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContactsScreen()),
            ),
            icon: const Icon(Icons.message_outlined),
          ),
        ],
        bottom: TabBar(
          controller: tabs,
          tabs: const [Tab(text: 'CHATS'), Tab(text: 'GROUPS'), Tab(text: 'CONTACTS')],
        ),
      ),
      body: TabBarView(
        controller: tabs,
        children: [_directChats(), _groups(), const ContactsScreen(showAppBar: false)],
      ),
    );
  }

  Widget _directChats() {
    final me = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('chats').where('type', isEqualTo: 'direct').where('participants', arrayContains: me).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Unable to load chats.\n${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data();
          final participants = List<String>.from(data['participants'] ?? const []);
          if (me == null || !participants.contains(me)) return false;
          if (query.isEmpty) return true;
          final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
          final emails = Map<String, dynamic>.from(data['participantEmails'] ?? {});
          return participants.any((uid) {
            final value = '${names[uid] ?? ''} ${emails[uid] ?? ''}'.toLowerCase();
            return value.contains(query);
          });
        }).toList()
          ..sort((a, b) => _timestamp(b.data()['lastMessageAt']).compareTo(_timestamp(a.data()['lastMessageAt'])));

        if (docs.isEmpty) return const Center(child: Text('No chats yet.'));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final participants = List<String>.from(data['participants'] ?? const []);
            final other = participants.firstWhere((id) => id != me, orElse: () => '');
            final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
            final emails = Map<String, dynamic>.from(data['participantEmails'] ?? {});
            final name = (names[other] ?? emails[other] ?? 'Staff').toString();
            return ListTile(
              leading: _avatar(name, ''),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                (data['lastMessage'] ?? 'Start a conversation').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(fmtTime(data['lastMessageAt']), style: const TextStyle(fontSize: 11)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => IndividualChatPage(
                    userId: other,
                    userName: name,
                    userEmail: (emails[other] ?? '').toString(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _groups() {
    final me = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('chats').where('type', isEqualTo: 'group').where('participants', arrayContains: me).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Unable to load groups.\n${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data();
          final members = List<String>.from(data['participants'] ?? const []);
          final name = (data['name'] ?? '').toString().toLowerCase();
          return me != null && members.contains(me) && name.contains(query);
        }).toList()
          ..sort((a, b) => _timestamp(b.data()['lastMessageAt']).compareTo(_timestamp(a.data()['lastMessageAt'])));

        if (docs.isEmpty) return const Center(child: Text('No groups found.'));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final name = (data['name'] ?? 'Group').toString();
            final members = List<String>.from(data['participants'] ?? const []);
            return ListTile(
              leading: _avatar(name, ''),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                (data['lastMessage'] ?? '${members.length} members').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(fmtTime(data['lastMessageAt']), style: const TextStyle(fontSize: 11)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GroupChatPage(groupId: docs[index].id, groupName: name)),
              ),
            );
          },
        );
      },
    );
  }

  DateTime _timestamp(dynamic value) => value is Timestamp ? value.toDate() : DateTime.fromMillisecondsSinceEpoch(0);

  Widget _avatar(String name, String url) {
    return CircleAvatar(
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty ? Text(name.isEmpty ? '?' : name[0].toUpperCase()) : null,
    );
  }
}
