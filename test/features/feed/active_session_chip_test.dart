import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xflow/features/feed/widgets/active_session_chip.dart';

void main() {
  test('session label is normalized and never claims the video source', () {
    expect(activeSessionLabel('TestAccount'), '@TestAccount');
    expect(activeSessionLabel('@second_account'), '@second_account');
    expect(activeSessionLabel(null), 'Sans compte X');
    expect(activeSessionLabel('  '), 'Sans compte X');
  });

  testWidgets('selected X account replaces the app logo in a narrow header',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 145,
          child: ActiveSessionChip(screenName: 'long_user_handle_123'),
        ),
      ),
    ));
    expect(find.text('@long_user_handle_123'), findsOneWidget);
    expect(find.text('Twitter vidéo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
