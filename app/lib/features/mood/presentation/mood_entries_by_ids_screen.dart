import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../data/mood_repository.dart';
import '../domain/mood_entry.dart';
import 'mood_entry_tile.dart';

/// 리포트 차트·키워드에서 집계에 포함된 원 기록으로 내려갈 때 쓰는 목록 화면.
class MoodEntriesByIdsArgs {
  const MoodEntriesByIdsArgs({required this.title, required this.entryIds});

  final String title;
  final List<int> entryIds;
}

class MoodEntriesByIdsScreen extends ConsumerStatefulWidget {
  const MoodEntriesByIdsScreen({super.key, required this.args});

  final MoodEntriesByIdsArgs args;

  @override
  ConsumerState<MoodEntriesByIdsScreen> createState() =>
      _MoodEntriesByIdsScreenState();
}

class _MoodEntriesByIdsScreenState
    extends ConsumerState<MoodEntriesByIdsScreen> {
  late Future<List<MoodEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(moodRepositoryProvider).getByIds(widget.args.entryIds);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.args.title)),
      body: FutureBuilder<List<MoodEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ApiException.from(snapshot.error!).message),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _future = ref
                          .read(moodRepositoryProvider)
                          .getByIds(widget.args.entryIds);
                    }),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            );
          }
          final entries = snapshot.data ?? const <MoodEntry>[];
          if (entries.isEmpty) {
            return const Center(child: Text('연결된 기록을 찾지 못했어요.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final entry in entries)
                MoodEntryTile(entry: entry, showDate: true),
            ],
          );
        },
      ),
    );
  }
}
