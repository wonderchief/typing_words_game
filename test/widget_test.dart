import 'package:flutter_test/flutter_test.dart';
import 'package:typing_words_game/main.dart';

void main() {
  testWidgets('Start button launches the game', (tester) async {
    await tester.pumpWidget(const TypingWordsGame());

    // Initial overlay should show the start button and intro text.
    expect(find.text('START'), findsOneWidget);
    expect(find.text('Typing Words Game'), findsOneWidget);

    await tester.tap(find.text('START'));
    await tester.pump();

    // Overlay should disappear and HUD should be visible.
    expect(find.text('START'), findsNothing);
    expect(find.text('Typing Words Game'), findsNothing);
  });
}
