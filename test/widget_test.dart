// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/chat_screen.dart';

void main() {
  test('direct chat ids are stable regardless of user order', () {
    expect(directChatId('user-b', 'user-a'), 'user-a_user-b');
    expect(directChatId('user-a', 'user-b'), 'user-a_user-b');
  });
}
