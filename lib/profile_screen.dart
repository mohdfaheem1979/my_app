import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final name = TextEditingController();
  final about = TextEditingController();
  String photo = '';
  bool loading = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final d = snap.data() ?? {};
      if (mounted) setState(() { name.text = (d['name'] ?? u.displayName ?? '').toString(); about.text = (d['about'] ?? '').toString(); photo = (d['photoUrl'] ?? u.photoURL ?? '').toString(); });
    } catch (e) { debugPrint('Profile load error: $e'); }
  }

  @override
  void dispose() { name.dispose(); about.dispose(); super.dispose(); }

  Future<void> save() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    setState(() => loading = true);
    try {
      final n = name.text.trim();
      await u.updateDisplayName(n);
      await FirebaseFirestore.instance.collection('users').doc(u.uid).set({'name': n, 'about': about.text.trim(), 'photoUrl': photo}, SetOptions(merge: true));
      _message('Profile updated.');
    } catch (e) { _message('Update failed: $e'); } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> pick() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      setState(() => loading = true);
      final ref = FirebaseStorage.instance.ref('profile_pictures/${u.uid}.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await u.updatePhotoURL(url);
      await FirebaseFirestore.instance.collection('users').doc(u.uid).set({'photoUrl': url}, SetOptions(merge: true));
      if (mounted) setState(() => photo = url);
      _message('Profile picture updated.');
    } catch (e) { _message('Image upload failed: $e'); } finally { if (mounted) setState(() => loading = false); }
  }

  void _message(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: Stack(children: [CircleAvatar(radius: 60, backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, child: photo.isEmpty ? const Icon(Icons.person, size: 60) : null), Positioned(right: 0, bottom: 0, child: IconButton.filled(onPressed: loading ? null : pick, icon: const Icon(Icons.camera_alt)))])),
        const SizedBox(height: 25),
        TextField(controller: name, maxLength: 60, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: about, maxLength: 120, decoration: const InputDecoration(labelText: 'About', hintText: 'Available, at work, etc.', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        ListTile(leading: const Icon(Icons.email_outlined), title: Text(u?.email ?? ''), subtitle: const Text('Email')),
        const SizedBox(height: 10),
        FilledButton(onPressed: loading ? null : save, child: loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('SAVE CHANGES')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: loading ? null : () => FirebaseAuth.instance.signOut(), child: const Text('LOG OUT')),
      ]))),
    );
  }
}
