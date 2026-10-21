import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_ticker/main.dart';

void main() {
  testWidgets('ProviderScope boots and shows the stub page', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TickerApp()));
    expect(find.text('Ticker'), findsOneWidget);
  });
}
