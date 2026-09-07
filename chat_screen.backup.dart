import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'group_info_screen.dart';

String directChatId(String a, String b) {
  final ids = [a, b]..sort();
  return '${ids[0]}_${ids[1]}';
}

String fmtTime(dynamic value) {
  if (value is! Timestamp) return '';
  final d = value.toDate();
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

class IndividualChatPage extends StatelessWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final String photoUrl;

  const IndividualChatPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.photoUrl = '',
  });

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;

    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in again.')),
      );
    }

    return ChatPage(
      chatId: directChatId(me.uid, userId),
      title: userName,
      isGroup: false,
      otherUserId: userId,
      otherUserName: userName,
      otherUserEmail: userEmail,
      otherPhotoUrl: photoUrl,
    );
  }
}

class GroupChatPage extends StatelessWidget {
  final String groupId;
  final String groupName;

  const GroupChatPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    return ChatPage(
      chatId: groupId,
      title: groupName,
      isGroup: true,
    );
  }
}

class ChatPage extends StatefulWidget {
  final String chatId;
  final String title;
  final bool isGroup;
  final String? otherUserId;
  final String? otherUserName;
  final String? otherUserEmail;
  final String? otherPhotoUrl;

  const ChatPage({
    super.key,
    required this.chatId,
    required this.title,
    required this.isGroup,
    this.otherUserId,
    this.otherUserName,
    this.otherUserEmail,
    this.otherPhotoUrl,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final message = TextEditingController();
  final scroll = ScrollController();
  bool sending = false;

  DocumentReference<Map<String, dynamic>> get chatRef =>
      FirebaseFirestore.instance.collection('chats').doc(widget.chatId);

  @override
  void dispose() {
    message.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _ensureChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User is not logged in.');

    final existing = await chatRef.get();
    if (existing.exists) return;

    final otherId = widget.otherUserId;

    await chatRef.set({
      'type': widget.isGroup ? 'group' : 'direct',
      if (widget.isGroup) 'name': widget.title,
      'participants': [
        user.uid,
        if (!widget.isGroup && otherId != null) otherId,
      ],
      'participantNames': {
        user.uid: user.displayName ?? user.email ?? 'User',
        if (otherId != null) otherId: widget.otherUserName ?? 'User',
      },
      'participantEmails': {
        user.uid: user.email ?? '',
        if (otherId != null) otherId: widget.otherUserEmail ?? '',
      },
      if (widget.isGroup) 'adminId': user.uid,
      if (widget.isGroup) 'admins': [user.uid],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendText() async {
    final text = message.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (text.isEmpty || user == null) return;

    setState(() => sending = true);

    try {
      await _ensureChat();

      await chatRef.collection('messages').add({
        'senderUid': user.uid,
        'senderName': user.displayName ?? user.email ?? 'User',
        'text': text,
        'type': 'text',
        'edited': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await chatRef.set({
        'lastMessage': text,
        'lastMessageBy': user.uid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      message.clear();
      _scrollBottom();
    } catch (e) {
      _snack('Message failed: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> pickFile() async {
    try {
      final files = await FilePicker.pickFiles();

      if (files.isEmpty) return;

      final file = files.first;
      final bytes = await file.readAsBytes();
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) return;

      setState(() => sending = true);
      await _ensureChat();

      final safeName = file.name.replaceAll(RegExp(r'[^\w.\-]'), '_');

      final storageRef = FirebaseStorage.instance.ref(
        'chat_files/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_$safeName',
      );

      await storageRef.putData(bytes);
      final url = await storageRef.getDownloadURL();

      await chatRef.collection('messages').add({
        'senderUid': user.uid,
        'senderName': user.displayName ?? user.email ?? 'User',
        'text': '',
        'type': 'file',
        'fileUrl': url,
        'fileName': file.name,
        'fileSize': bytes.length,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await chatRef.set({
        'lastMessage': '📎 ${file.name}',
        'lastMessageBy': user.uid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _scrollBottom();
    } catch (e) {
      _snack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _openFile(String url) async {
    if (url.isEmpty) return;
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _messageBubble(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final mine = data['senderUid'] == FirebaseAuth.instance.currentUser?.uid;
    final type = (data['type'] ?? 'text').toString();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isGroup && !mine)
              Text(
                (data['senderName'] ?? 'User').toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            if (type == 'file')
              InkWell(
                onTap: () => _openFile((data['fileUrl'] ?? '').toString()),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insert_drive_file, size: 30),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        (data['fileName'] ?? 'Attachment').toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            else
              SelectableText((data['text'] ?? '').toString()),
            const SizedBox(height: 4),
            Text(
              fmtTime(data['createdAt']),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = chatRef
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (!widget.isGroup)
              CircleAvatar(
                backgroundImage: widget.otherPhotoUrl?.isNotEmpty == true
                    ? NetworkImage(widget.otherPhotoUrl!)
                    : null,
                child: widget.otherPhotoUrl?.isNotEmpty == true
                    ? null
                    : Text(widget.title.isEmpty ? '?' : widget.title[0]),
              ),
            if (!widget.isGroup) const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (widget.isGroup)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupInfoScreen(chatId: widget.chatId),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Unable to load messages.\n${snapshot.error}',
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No messages yet. Start the conversation.'),
                  );
                }

                _scrollBottom();

                return ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: docs.length,
                  itemBuilder: (_, index) {
                    return _messageBubble(docs[index]);
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: sending ? null : pickFile,
                    icon: const Icon(Icons.attach_file),
                  ),
                  Expanded(
                    child: TextField(
                      controller: message,
                      enabled: !sending,
                      minLines: 1,
                      maxLines: 5,
                      onSubmitted: (_) => sendText(),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: sending ? null : sendText,
                    icon: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}