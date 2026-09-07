import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GroupInfoScreen extends StatefulWidget {
  final String chatId;

  const GroupInfoScreen({
    super.key,
    required this.chatId,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  String query = '';
  bool loading = false;

  User? get user => FirebaseAuth.instance.currentUser;

  DocumentReference<Map<String, dynamic>> get ref {
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId);
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _rename(String currentName) async {
    final controller = TextEditingController(
      text: currentName,
    );

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Change Group Name'),
          content: TextField(
            controller: controller,
            maxLength: 50,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Group name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  controller.text.trim(),
                );
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (value == null ||
        value.isEmpty ||
        value == currentName) {
      return;
    }

    try {
      await ref.update({
        'name': value,
        'groupName': value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _message('Unable to rename group: $e');
    }
  }

  Future<void> _addMember(
    String uid,
    String name,
    String email,
  ) async {
    final me = user;

    if (me == null) return;

    setState(() {
      loading = true;
    });

    try {
      await ref.update({
        'participants': FieldValue.arrayUnion([uid]),
        'participantNames.$uid': name,
        'participantEmails.$uid': email,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await ref.collection('messages').add({
        'senderUid': me.uid,
        'senderName':
            me.displayName ?? me.email ?? 'Admin',
        'text': '$name was added to the group.',
        'type': 'system',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      _message('Unable to add member: $e');
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> _removeMember(
    String uid,
    String name,
  ) async {
    final me = user?.uid;

    if (me == null) return;

    if (uid == me) {
      _message(
        'You cannot remove yourself. Use Leave Group.',
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove Member'),
          content: Text(
            'Remove $name from this group?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('REMOVE'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await ref.update({
        'participants': FieldValue.arrayRemove([uid]),
        'participantNames.$uid': FieldValue.delete(),
        'participantEmails.$uid': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await ref.collection('messages').add({
        'senderUid': me,
        'senderName':
            user?.displayName ?? user?.email ?? 'Admin',
        'text': '$name was removed from the group.',
        'type': 'system',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _message('Unable to remove member: $e');
    }
  }

  Future<void> _leave() async {
    final me = user?.uid;

    if (me == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Leave Group'),
          content: const Text(
            'Are you sure you want to leave this group?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('LEAVE'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await ref.update({
        'participants': FieldValue.arrayRemove([me]),
        'participantNames.$me': FieldValue.delete(),
        'participantEmails.$me': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      _message('Unable to leave group: $e');
    }
  }

  Future<void> _deleteGroup() async {
    final me = user?.uid;

    if (me == null) return;

    try {
      final snap = await ref.get();
      final data = snap.data() ?? {};

      final admins = List<String>.from(
        data['admins'] ?? const [],
      );

      final isAdmin =
          data['adminId']?.toString() == me ||
          admins.contains(me);

      if (!isAdmin) {
        _message(
          'Only the group admin can delete this group.',
        );
        return;
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Delete Group'),
            content: const Text(
              'Delete this group and its messages?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('CANCEL'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('DELETE'),
              ),
            ],
          );
        },
      );

      if (ok != true) return;

      final messages = await ref
          .collection('messages')
          .get();

      final batch =
          FirebaseFirestore.instance.batch();

      for (final doc in messages.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(ref);

      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      _message('Unable to delete group: $e');
    }
  }

  Future<void> _showAddMembers(
    List<String> current,
  ) async {
    final controller = TextEditingController();

    String searchQuery = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (
            modalContext,
            setModalState,
          ) {
            return SizedBox(
              height:
                  MediaQuery.of(context).size.height * 0.8,
              child: SafeArea(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'ADD MEMBERS',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      child: TextField(
                        controller: controller,
                        onChanged: (value) {
                          setModalState(() {
                            searchQuery =
                                value.toLowerCase();
                          });
                        },
                        decoration:
                            const InputDecoration(
                          prefixIcon:
                              Icon(Icons.search),
                          hintText: 'Search staff...',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Expanded(
                      child: StreamBuilder<
                          QuerySnapshot<
                              Map<String, dynamic>>>(
                        stream: FirebaseFirestore
                            .instance
                            .collection('users')
                            .where(
                              'active',
                              isEqualTo: true,
                            )
                            .snapshots(),
                        builder: (
                          context,
                          snapshot,
                        ) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.all(
                                  20,
                                ),
                                child: Text(
                                  'Unable to load staff.\n'
                                  '${snapshot.error}',
                                  textAlign:
                                      TextAlign.center,
                                ),
                              ),
                            );
                          }

                          if (!snapshot.hasData) {
                            return const Center(
                              child:
                                  CircularProgressIndicator(),
                            );
                          }

                          final docs = snapshot
                              .data!.docs
                              .where((doc) {
                            if (current
                                .contains(doc.id)) {
                              return false;
                            }

                            final data =
                                doc.data();

                            final searchable =
                                '${data['name'] ?? ''} '
                                '${data['email'] ?? ''}'
                                    .toLowerCase();

                            return searchable
                                .contains(
                              searchQuery,
                            );
                          }).toList();

                          if (docs.isEmpty) {
                            return const Center(
                              child: Text(
                                'No staff found.',
                              ),
                            );
                          }

                          return ListView.builder(
                            itemCount: docs.length,
                            itemBuilder:
                                (context, index) {
                              final doc = docs[index];
                              final data =
                                  doc.data();

                              final name =
                                  (data['name'] ??
                                          data['email'] ??
                                          'Staff')
                                      .toString();

                              final email =
                                  (data['email'] ??
                                          '')
                                      .toString();

                              return ListTile(
                                leading:
                                    CircleAvatar(
                                  child: Text(
                                    name.isEmpty
                                        ? '?'
                                        : name[0]
                                            .toUpperCase(),
                                  ),
                                ),
                                title: Text(name),
                                subtitle:
                                    Text(email),
                                trailing:
                                    IconButton(
                                  icon: const Icon(
                                    Icons
                                        .add_circle,
                                  ),
                                  onPressed: loading
                                      ? null
                                      : () {
                                          Navigator.pop(
                                            sheetContext,
                                          );

                                          _addMember(
                                            doc.id,
                                            name,
                                            email,
                                          );
                                        },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<
        DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            !snapshot.hasData ||
            !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(
              child: Text(
                'Group information not available.',
              ),
            ),
          );
        }

        final data = snapshot.data!.data()!;

        final name =
            (data['name'] ??
                    data['groupName'] ??
                    'Group')
                .toString();

        final members = List<String>.from(
          data['participants'] ?? const [],
        );

        final names =
            Map<String, dynamic>.from(
          data['participantNames'] ?? {},
        );

        final emails =
            Map<String, dynamic>.from(
          data['participantEmails'] ?? {},
        );

        final admins = <String>{
          ...List<String>.from(
            data['admins'] ?? const [],
          ),
        };

        if (data['adminId'] != null) {
          admins.add(
            data['adminId'].toString(),
          );
        }

        final me = user?.uid;
        final isAdmin =
            me != null && admins.contains(me);

        final visible = members.where((uid) {
          final memberName =
              (names[uid] ?? 'Staff').toString();

          final memberEmail =
              (emails[uid] ?? '').toString();

          final searchable =
              '$memberName $memberEmail'
                  .toLowerCase();

          return searchable.contains(query);
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Group Info'),
          ),
          body: ListView(
            children: [
              const SizedBox(height: 25),

              const Center(
                child: CircleAvatar(
                  radius: 48,
                  child: Icon(
                    Icons.groups,
                    size: 48,
                  ),
                ),
              ),

              const SizedBox(height: 15),

              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isAdmin)
                      IconButton(
                        onPressed: () {
                          _rename(name);
                        },
                        icon: const Icon(
                          Icons.edit,
                        ),
                      ),
                  ],
                ),
              ),

              Center(
                child: Text(
                  '${members.length} members',
                  style: const TextStyle(
                    color: Colors.grey,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (isAdmin)
                ListTile(
                  leading: const Icon(
                    Icons.person_add,
                  ),
                  title: const Text(
                    'Add Members',
                  ),
                  onTap: () {
                    _showAddMembers(members);
                  },
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  8,
                ),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      query =
                          value.trim().toLowerCase();
                    });
                  },
                  decoration:
                      const InputDecoration(
                    prefixIcon:
                        Icon(Icons.search),
                    hintText: 'Search members...',
                    border:
                        OutlineInputBorder(),
                  ),
                ),
              ),

              ...visible.map((uid) {
                final memberName =
                    (names[uid] ?? 'Staff')
                        .toString();

                final memberEmail =
                    (emails[uid] ?? '').toString();

                final admin =
                    admins.contains(uid);

                final mine = uid == me;

                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      memberName.isEmpty
                          ? '?'
                          : memberName[0]
                              .toUpperCase(),
                    ),
                  ),
                  title: Text(
                    mine
                        ? '$memberName (You)'
                        : memberName,
                  ),
                  subtitle:
                      Text(memberEmail),
                  trailing: Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      if (admin)
                        const Chip(
                          label: Text('ADMIN'),
                        ),
                      if (isAdmin && !mine)
                        IconButton(
                          onPressed: () {
                            _removeMember(
                              uid,
                              memberName,
                            );
                          },
                          icon: const Icon(
                            Icons
                                .remove_circle_outline,
                          ),
                        ),
                    ],
                  ),
                );
              }),

              const Divider(height: 30),

              ListTile(
                leading: const Icon(
                  Icons.exit_to_app,
                ),
                title: const Text(
                  'Leave Group',
                ),
                onTap: _leave,
              ),

              if (isAdmin)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                  title: const Text(
                    'Delete Group',
                    style: TextStyle(
                      color: Colors.red,
                    ),
                  ),
                  onTap: _deleteGroup,
                ),

              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }
}