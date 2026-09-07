import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final TextEditingController search = TextEditingController();

  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  void _chat(
    String id,
    String name,
    String email,
    String photo,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IndividualChatPage(
          userId: id,
          userName: name,
          userEmail: email,
          photoUrl: photo,
        ),
      ),
    );
  }

  Future<void> _toggle(String id, bool active) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .update({
        'active': !active,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _message('Unable to update status: $e');
    }
  }

  Future<void> _remove(String id, String name) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (id == currentUid) {
      _message('You cannot remove yourself.');
      return;
    }

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove staff?'),
          content: Text(
            'Remove $name from the staff list?',
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .delete();
    } catch (e) {
      _message('Unable to remove staff: $e');
    }
  }

  void _details(
    String id,
    Map<String, dynamic> data,
  ) {
    final String name =
        (data['name'] ?? data['email'] ?? 'Staff').toString();

    final String email =
        (data['email'] ?? '').toString();

    final String role =
        (data['role'] ?? 'Staff').toString();

    final bool active =
        data['active'] == true;

    final String photo =
        (data['photoUrl'] ?? '').toString();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundImage:
                      photo.isNotEmpty ? NetworkImage(photo) : null,
                  child: photo.isEmpty
                      ? Text(
                          name.isEmpty
                              ? '?'
                              : name[0].toUpperCase(),
                        )
                      : null,
                ),
                title: Text(name),
                subtitle: Text(email),
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Role'),
                subtitle: Text(role),
              ),
              ListTile(
                leading: Icon(
                  active
                      ? Icons.check_circle
                      : Icons.block,
                  color:
                      active ? Colors.green : Colors.grey,
                ),
                title: const Text('Status'),
                subtitle: Text(
                  active ? 'Active' : 'Inactive',
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.chat_outlined,
                ),
                title: const Text('Open chat'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _chat(
                    id,
                    name,
                    email,
                    photo,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Management'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {});
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: search,
              onChanged: (value) {
                setState(() {
                  query = value.trim().toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search name, email or role',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          search.clear();

                          setState(() {
                            query = '';
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<
                QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Unable to load staff.\n'
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = snapshot.data!.docs.where(
                  (doc) {
                    final data = doc.data();

                    final String searchable =
                        '${data['name'] ?? ''} '
                        '${data['email'] ?? ''} '
                        '${data['role'] ?? ''}'
                            .toLowerCase();

                    return searchable.contains(query);
                  },
                ).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No staff found.'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();

                    final String name =
                        (data['name'] ??
                                data['email'] ??
                                'Staff')
                            .toString();

                    final String email =
                        (data['email'] ?? '').toString();

                    final String role =
                        (data['role'] ?? 'Staff').toString();

                    final bool active =
                        data['active'] == true;

                    final String photo =
                        (data['photoUrl'] ?? '').toString();

                    final bool mine =
                        doc.id ==
                        FirebaseAuth
                            .instance
                            .currentUser
                            ?.uid;

                    return Card(
                      child: ListTile(
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              backgroundImage:
                                  photo.isNotEmpty
                                      ? NetworkImage(photo)
                                      : null,
                              child: photo.isEmpty
                                  ? Text(
                                      name.isEmpty
                                          ? '?'
                                          : name[0]
                                              .toUpperCase(),
                                    )
                                  : null,
                            ),
                            Positioned(
                              right: -1,
                              bottom: -1,
                              child: Container(
                                width: 13,
                                height: 13,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: active
                                      ? Colors.green
                                      : Colors.grey,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '$email\n'
                          '$role • '
                          '${active ? 'Active' : 'Inactive'}',
                        ),
                        isThreeLine: true,
                        onTap: () {
                          _details(doc.id, data);
                        },
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'chat') {
                              _chat(
                                doc.id,
                                name,
                                email,
                                photo,
                              );
                            } else if (value == 'toggle') {
                              _toggle(
                                doc.id,
                                active,
                              );
                            } else if (value == 'remove') {
                              _remove(
                                doc.id,
                                name,
                              );
                            }
                          },
                          itemBuilder: (context) {
                            return [
                              const PopupMenuItem<String>(
                                value: 'chat',
                                child: Text('Open Chat'),
                              ),
                              PopupMenuItem<String>(
                                value: 'toggle',
                                child: Text(
                                  active
                                      ? 'Deactivate'
                                      : 'Activate',
                                ),
                              ),
                              if (!mine)
                                const PopupMenuItem<String>(
                                  value: 'remove',
                                  child: Text('Remove'),
                                ),
                            ];
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}