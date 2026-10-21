import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/tick.dart';
import '../services/tick_feed.dart';

/// Number of ticks before the feed throws; `null` means never fail.
final failAfterProvider = StateProvider<int?>((ref) => null);

/// Overridable in tests and in the error demo.
final tickFeedProvider = Provider<TickFeed>((ref) {
  return TickFeed(failAfter: ref.watch(failAfterProvider));
});

final tickerProvider = StreamProvider.autoDispose<List<Tick>>(
  (ref) {
    return ref.watch(tickFeedProvider).watch();
  },
  // Riverpod 3 retries failed providers automatically, which would turn every
  // feed error into AsyncLoading(retrying). The lab wants a real AsyncError
  // and a manual Retry button, so automatic retry is disabled here.
  retry: (_, _) => null,
);
