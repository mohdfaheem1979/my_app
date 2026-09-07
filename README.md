# Company Messenger – WhatsApp-style cross-platform upgrade

This project is a clean cross-platform Flutter messenger implementation based on the supplied `my_app` project.

## Included
- Individual chats
- Groups
- Group creation, members, admin and delete confirmation
- Search users/groups
- Online/last-seen heartbeat
- Profile picture and profile editing
- Reply
- Emoji reactions
- Pin/unpin
- Forward
- Copy
- Message info
- Edit
- Delete confirmation
- Select multiple messages + delete
- Private reply from a group message
- Image/PDF/Word/Excel/other file attachments
- Firebase Storage uploads using `PlatformFile.bytes` (no `dart:io`)
- Windows, Android, iOS and Web project targets

## Important
This is an independent messenger implementation with WhatsApp-style interaction patterns. It does not contain WhatsApp proprietary source code, branding, or private encryption implementation.

## Firebase setup
The supplied Firebase project configuration is retained in `lib/firebase_options.dart`.

1. Enable Email/Password in Firebase Authentication.
2. Create Firestore database.
3. Create Firebase Storage.
4. Deploy rules:
   - `firebase deploy --only firestore:rules,storage`
5. Deploy Functions if required:
   - `cd functions`
   - `npm install`
   - `firebase deploy --only functions`
6. Run:
   - `flutter pub get`
   - `flutter run -d windows`
   - `flutter run -d chrome`
   - `flutter run` with an Android device/emulator
   - `flutter run` with an iOS simulator/device on macOS

## Data model
`users/{uid}`
- name
- email
- role
- active
- photoUrl
- online
- lastSeen

`chats/{chatId}`
- type: `direct` or `group`
- participants
- name
- adminId
- participantNames
- participantEmails
- lastMessage
- updatedAt

`chats/{chatId}/messages/{messageId}`
- senderId
- senderName
- text
- type
- fileUrl/fileName/fileSize
- replyTo/replyText/replyName
- reactions
- pinned
- edited
- deleted
- createdAt

## Note about testing
The development environment used to prepare this archive did not contain the Flutter/Dart SDK, so a local `flutter analyze` / device build could not be executed here. The source was written to avoid `dart:io` in shared UI code and to use cross-platform file bytes for uploads.
