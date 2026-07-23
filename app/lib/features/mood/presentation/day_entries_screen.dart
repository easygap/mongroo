import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_formats.dart';
import '../../../core/error/api_exception.dart';
import 'mood_entry_tile.dart';
import 'mood_providers.dart';

class DayEntriesScreen extends ConsumerWidget {
  const DayEntriesScreen({super.key, required this.date});

  /// YYYY-MM-DD
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(dayEntriesProvider(date));
    final parsed = DateTime.tryParse(date);
    final title = parsed == null ? date : '${formatKoreanMonthDay(parsed)} 기록';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ApiException.from(error).message),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(dayEntriesProvider(date)),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (entries) => entries.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_note_outlined, size: 36),
                    SizedBox(height: 10),
                    Text('이날은 기록이 없어요.'),
                  ],
                ),
              )
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(dayEntriesProvider(date)),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final entry in entries)
                          MoodEntryTile(entry: entry),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
