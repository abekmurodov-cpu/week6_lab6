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

## Part 3 — Ticker UI with AsyncValue pattern matching

**3.3 Breaking the switch on purpose.** With the `AsyncLoading()` arm commented
out, `flutter analyze` reports:

```
error • The type 'AsyncValue<List<Tick>>' isn't exhaustively matched by the switch cases since it doesn't match the pattern 'AsyncLoading<List<Tick>>()'. Try adding a wildcard pattern or cases that match 'AsyncLoading<List<Tick>>()' • lib/ticker_page.dart:15:13 • non_exhaustive_switch_expression
```

`AsyncValue` is `sealed`, so the compiler knows the full list of subtypes and
refuses to build a switch expression that misses one.

**3.4 Matching on content.** I added `AsyncData(value: [])` (shows "No symbols
subscribed") and `AsyncData(value: [final only])` (shows one centred `TickRow`).
I checked both with throwaway widget tests that override the feed in
`ProviderScope.overrides` with `TickFeed(symbols: const [])` and
`TickFeed(symbols: const ['BTC'])`. A third throwaway test used
`TickFeed(failAfter: 5)` and showed `Error: Feed disconnected`, so all three states
can be reached.

**Why must these arms come before the general `AsyncData` arm?**
Switch arms are checked top to bottom and the first match wins.
`AsyncData(:final value)` matches *every* `AsyncData`, empty and one-element lists
included. If it came first, the specific arms could never run. I tried it, and the analyzer
reports:

```
warning • This case is covered by the previous cases. Try removing the case clause, or restructuring the preceding patterns • lib/ticker_page.dart:19:30 • unreachable_switch_case
```

## Part 4 — Errors, retry, and preserving previous data

Two `IconButton`s in the `AppBar` set `failAfterProvider` to `5` (wifi-off icon)
or back to `null` (wifi icon). `tickFeedProvider` watches `failAfterProvider`, so
each toggle builds a new feed and restarts the stream.

To see the states Riverpod 3.4.3 really emits, I logged them from a
`ProviderContainer`:

| Action | State emitted |
| --- | --- |
| cold start | `AsyncLoading` (hasValue=false) |
| `ref.invalidate` / `ref.refresh` from data | `AsyncData` isLoading=true, **isRefreshing=true** |
| `failAfterProvider` changed (a watched dependency) | `AsyncLoading` hasValue=true, **isReloading=true** |
| feed throws after ticks | `AsyncError` hasValue=true |
| Retry (`invalidate`) from that error | `AsyncError` isLoading=true, isRefreshing=true |

Riverpod 3 keeps the previous subtype during a refresh, so a retry from an error
is still an `AsyncError`, now with `isLoading: true`. In the lab's arm order the
"error with stale data" arm catches it first. I kept that order, but the arm also
destructures `isLoading`. While it's true, it shows a `LinearProgressIndicator` above
the banner and disables Retry, so the user can see the reconnect. The "error with
nothing to show" arm does the same with a small spinner in place of the button.

**4.3 `refresh` vs `invalidate`.** In Riverpod 3 **both** keep the previous rows
visible. Either way the provider rebuilds and the new state carries the old value
(`AsyncData` with `isLoading: true`), so the
`AsyncValue(:final value?, isLoading: true)` arm shows the rows under a thin
progress bar. The difference is what `onRefresh` gets back:

- `ref.refresh(tickerProvider.future)` invalidates the provider, reads it again
  straight away, and returns the new `Future<List<Tick>>`. That future completes
  with the first value of the restarted stream. `RefreshIndicator` awaits it, so
  the pull spinner stays up until fresh prices arrive (about 800 ms here).
- `ref.invalidate(tickerProvider)` returns `void`. It only marks the provider
  dirty, and the rebuild happens later. `onRefresh` (`() async => ref.invalidate(...)`)
  completes at once, so the pull spinner leaves while the reload is still running.
  In a widget test it disappeared at about 500 ms while the progress bar kept going.

I kept `refresh(...future)`, wrapped in a `try/catch`. If the refresh fails, or the
provider is disposed mid-refresh, the future throws; the `AsyncError` arms already
show that, so the exception doesn't need to go unhandled.

**4.4 Reconnect vs first load.** The arms already handle it. The full-screen
`AsyncLoading()` arm comes last, and every loading state that has a previous value
is caught higher up: by the error arms (`AsyncError` + `isLoading`) or by
`AsyncValue(:final value?, isLoading: true)`. A throwaway widget test checked the
whole checkpoint: cold-start spinner → rows → toggle failure (progress bar, rows
still visible, no full-screen spinner) → banner over rows at opacity 0.5 → Retry
(banner + progress bar, no full-screen spinner) → live rows again, no banner.

**`isRefreshing` vs `isReloading`:** `isRefreshing` means the provider was
recomputed manually with `ref.refresh`/`ref.invalidate` while its dependencies
stayed the same. `isReloading` means it was recomputed because something it
`ref.watch`es changed (here, `failAfterProvider`). Both need a previous
value or error.
