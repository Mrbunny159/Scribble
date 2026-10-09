import 'package:flutter_test/flutter_test.dart';
import 'package:scribble/main.dart';
import 'package:scribble/models/connection_model.dart';
import 'package:scribble/models/scribble_model.dart';
import 'package:scribble/models/user_profile.dart';

void main() {
  testWidgets('Scribble app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ScribbleApp(isFirebaseInitialized: false));
    expect(find.text('Firebase Setup Error'), findsOneWidget);
  });

  test('ConnectionModel safely parses snake_case columns', () {
    final connectionMap = {
      'id': 'conn-123',
      'user_1': 'user-alice',
      'user_2': 'user-bob',
      'created_at': '2026-09-29T00:00:00.000Z',
    };

    final conn = ConnectionModel.fromMap(connectionMap);
    expect(conn.id, 'conn-123');
    expect(conn.user1, 'user-alice');
    expect(conn.user2, 'user-bob');
    expect(conn.getPartnerId('user-alice'), 'user-bob');
    expect(conn.getPartnerId('user-bob'), 'user-alice');
  });

  test('UserProfile and ScribbleModel safely parse maps with nullables', () {
    final profileMap = {
      'id': 'user-123',
      'username': 'Test User',
      'avatar_url': null,
    };
    final profile = UserProfile.fromMap(profileMap);
    expect(profile.id, 'user-123');
    expect(profile.username, 'Test User');
    expect(profile.avatarUrl, isNull);

    final scribbleMap = {
      'id': 'scribble-1',
      'connection_id': 'conn-1',
      'sender_id': 'user-123',
      'image_url': 'https://example.com/scribble.png',
      'is_cleared': false,
    };
    final scribble = ScribbleModel.fromMap(scribbleMap);
    expect(scribble.id, 'scribble-1');
    expect(scribble.connectionId, 'conn-1');
    expect(scribble.senderId, 'user-123');
    expect(scribble.imageUrl, 'https://example.com/scribble.png');
    expect(scribble.isCleared, isFalse);
  });
}
