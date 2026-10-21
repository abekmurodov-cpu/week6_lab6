import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_ticker/main.dart';

void main() {
  testWidgets('cold load shows spinner, then rows', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TickerApp()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('ETH'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // dispose provider
    await tester.pump(const Duration(seconds: 1)); // flush the feed's pending delay
  });
}
