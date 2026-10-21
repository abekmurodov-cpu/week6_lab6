import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_ticker/providers/ticker_providers.dart';
import 'package:riverpod_ticker/services/tick_feed.dart';

void main() {
  test('starts loading, then emits data', () async {
    final container = ProviderContainer(overrides: [
      tickFeedProvider.overrideWithValue(TickFeed(symbols: const ['BTC'])),
    ]);
    addTearDown(container.dispose);
    // read() does not keep an autoDispose provider alive in Riverpod 3; without
    // a listener it is disposed during the 800 ms delay and .future throws.
    final sub = container.listen(tickerProvider, (_, _) {});
    addTearDown(sub.close);

    expect(container.read(tickerProvider), isA<AsyncLoading<Object?>>());

    final first = await container.read(tickerProvider.future);
    expect(first.single.symbol, 'BTC');
    expect(container.read(tickerProvider).hasValue, isTrue);
  });

  test('surfaces FeedException as AsyncError with previous value', () async {
    final container = ProviderContainer(overrides: [
      tickFeedProvider.overrideWithValue(TickFeed(symbols: const ['BTC'], failAfter: 1)),
    ]);
    addTearDown(container.dispose);

    final sub = container.listen(tickerProvider, (_, _) {});
    await container.read(tickerProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final state = container.read(tickerProvider);
    expect(state, isA<AsyncError<Object?>>());
    expect(state.hasValue, isTrue, reason: 'previous ticks are kept');
    expect(state.error, isA<FeedException>());
    sub.close();
  });
}
