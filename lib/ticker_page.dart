import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/tick.dart';
import 'providers/ticker_providers.dart';
import 'widgets/tick_row.dart';

class TickerPage extends ConsumerWidget {
  const TickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticks = ref.watch(tickerProvider);
    final failAfter = ref.watch(failAfterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live ticker'),
        actions: [
          IconButton(
            tooltip: 'Simulate failure after 5 ticks',
            isSelected: failAfter != null,
            icon: const Icon(Icons.wifi_off),
            onPressed: () => ref.read(failAfterProvider.notifier).state = 5,
          ),
          IconButton(
            tooltip: 'Healthy feed',
            isSelected: failAfter == null,
            icon: const Icon(Icons.wifi),
            onPressed: () => ref.read(failAfterProvider.notifier).state = null,
          ),
        ],
      ),
      body: RefreshIndicator(
        // refresh(...future) completes when the new data arrives, so the pull
        // indicator stays visible for the whole reload.
        onRefresh: () => ref
            .refresh(tickerProvider.future)
            // A failed refresh is already rendered by the AsyncError arms below.
            .then<void>((_) {}, onError: (Object _) {}),
        child: switch (ticks) {
          // Error with stale data: show rows dimmed, banner on top.
          // Retry from here yields AsyncError(isLoading: true) in Riverpod 3,
          // so the banner stays and a progress bar shows the reconnect.
          AsyncError(:final error, :final value?, :final isLoading) => Column(children: [
            if (isLoading) const LinearProgressIndicator(),
            MaterialBanner(
              content: Text('Feed error: $error — showing last prices'),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => ref.invalidate(tickerProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
            Expanded(child: Opacity(opacity: 0.5, child: _rows(value))),
          ]),

          // Error with nothing to show
          AsyncError(:final error, :final isLoading) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Could not load ticker\n$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (isLoading)
                const CircularProgressIndicator()
              else
                FilledButton(onPressed: () => ref.invalidate(tickerProvider), child: const Text('Retry')),
            ]),
          ),

          // Refresh or reload in progress: keep rows, show thin progress bar
          AsyncValue(:final value?, isLoading: true) => Column(children: [
            const LinearProgressIndicator(),
            Expanded(child: _rows(value)),
          ]),

          AsyncData(value: []) => const Center(child: Text('No symbols subscribed')),
          AsyncData(value: [final only]) => Center(child: TickRow(only)),
          AsyncData(:final value) => _rows(value),

          // Only reachable on cold start: no value has ever been emitted
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _rows(List<Tick> ticks) => ListView(
    children: [for (final t in ticks) TickRow(t, key: ValueKey(t.symbol))],
  );
}
