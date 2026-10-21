# Lab 6 — Real-Time Data Ticker with AsyncValue — Notes

Stack: Flutter 3.47.7, Dart 3.13.5, flutter_riverpod 3.4.3.

Setup deviation: `riverpod_test` could not be added. Every published version
depends on `riverpod ^2.x`, which conflicts with `flutter_riverpod 3.x`. The tests
only need `flutter_test` and `ProviderContainer`, so I dropped it. `mocktail` is
installed as a dev dependency.

## Part 2 — Model and stream provider

**Checkpoint log.** With a temporary
`ref.listen(tickerProvider, (_, next) => debugPrint('$next'))` in `TickerPage`
(run with `flutter run -d macos`), I saw:

```
flutter: AsyncData<List<Tick>>(value: [Instance of 'Tick', Instance of 'Tick', Instance of 'Tick'])
flutter: AsyncData<List<Tick>>(value: [Instance of 'Tick', Instance of 'Tick', Instance of 'Tick'])
...
```

`ref.listen` only fires on *changes*, so the initial `AsyncLoading` doesn't show up
in that log. `WidgetRef.listen` has no `fireImmediately` option. I listened on a
`ProviderContainer` with `fireImmediately: true` instead, and it printed:

```
AsyncLoading<List<Tick>>()
AsyncData<List<Tick>>(value: [Instance of 'Tick', Instance of 'Tick', Instance of 'Tick'])
AsyncData<List<Tick>>(value: [Instance of 'Tick', Instance of 'Tick', Instance of 'Tick'])
```

**Why is the feed behind its own `Provider` instead of being constructed inside `tickerProvider`?**
It's dependency injection. `tickerProvider` asks Riverpod for a `TickFeed`
instead of creating one, so tests and demos can swap it with
`tickFeedProvider.overrideWithValue(TickFeed(failAfter: 1))` (or a fake) without
touching the stream logic. It also lets other providers rebuild the feed. In Part 4
`failAfterProvider` changes the feed, and because `tickerProvider` watches
`tickFeedProvider`, the stream restarts on its own.

**What does `autoDispose` do when the user navigates away mid-stream?**
Once nothing listens to `tickerProvider` any more (the page is popped), Riverpod
disposes the provider. That cancels the `StreamSubscription`, which stops the
`async*` generator, so no more ticks are produced and nothing leaks. The cached
state is thrown away too, so coming back starts a fresh cold load (`AsyncLoading`
with no value).

**What `AsyncValue` does `tickerProvider` hold during the 800 ms delay, and what is `hasValue`?**
It holds `AsyncLoading<List<Tick>>()` with no previous value, so `isLoading == true`
and `hasValue == false`. After the first emission it becomes `AsyncData` and
`hasValue` is `true`; my log test printed `hasValue now: true`.

**Riverpod 3 note.** Riverpod 3 retries failing providers automatically
(exponential backoff, 200 ms → 6.4 s). While it retries, the state is
`AsyncLoading(retrying: true)` rather than `AsyncError`, so the error arms in this
lab would never match. `tickerProvider` sets `retry: (_, _) => null` to turn that
off. Errors then surface as `AsyncError`, and the user retries with the Retry button.
