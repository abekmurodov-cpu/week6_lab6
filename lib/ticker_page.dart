import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/ticker_providers.dart';
import 'widgets/tick_row.dart';

class TickerPage extends ConsumerWidget {
  const TickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticks = ref.watch(tickerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Live ticker')),
      body: switch (ticks) {
        AsyncData(value: []) => const Center(child: Text('No symbols subscribed')),
        AsyncData(value: [final only]) => Center(child: TickRow(only)),
        AsyncData(:final value) => ListView(
          children: [for (final t in value) TickRow(t, key: ValueKey(t.symbol))],
        ),
        AsyncError(:final error) => Center(child: Text('Error: $error')),
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
