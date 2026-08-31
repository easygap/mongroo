import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/text/korean_particles.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../data/expedition_repository.dart';
import '../domain/expedition_models.dart';
import '../domain/joint_guard_models.dart';
import 'expedition_battle_dock.dart';
import 'expedition_combat_overlay.dart';
import 'expedition_scene.dart';
import 'joint_guard_controller.dart';

part 'joint_guard_entry_view.dart';
part 'joint_guard_formation_view.dart';
part 'joint_guard_battle_view.dart';

/// 합동 수호전 화면.
///
/// 세 장면이 한 화면 안에서 이어진다 — 입구(어떤 짐승의 꿈으로 갈지),
/// 편성(여섯 자리를 채운다), 그리고 판. 진행 중인 판이 있으면 입구를 건너뛰고
/// 바로 그 판으로 들어간다.
class JointGuardScreen extends ConsumerStatefulWidget {
  const JointGuardScreen({super.key});

  @override
  ConsumerState<JointGuardScreen> createState() => _JointGuardScreenState();
}

class _JointGuardScreenState extends ConsumerState<JointGuardScreen> {
  String? _beastCode;
  String? _difficulty;

  void _chooseBeast(String beastCode, String difficulty) {
    setState(() {
      _beastCode = beastCode;
      _difficulty = difficulty;
    });
  }

  void _backToEntry() {
    setState(() {
      _beastCode = null;
      _difficulty = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(jointGuardControllerProvider);

    ref.listen<String?>(
      jointGuardControllerProvider.select((value) => value.error),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(next)));
        ref.read(jointGuardControllerProvider.notifier).clearError();
      },
    );

    final run = state.run;
    final title = run != null ? run.state.beast.name : '합동 수호전';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(
          onPressed: () {
            if (run == null && _beastCode != null) {
              _backToEntry();
              return;
            }
            Navigator.of(context).maybePop();
          },
        ),
      ),
      body: SafeArea(
        child: switch ((state.loading, run, _beastCode)) {
          (true, _, _) => const Center(child: CircularProgressIndicator()),
          (_, final JointGuardRun active, _) => _JointGuardBattleView(run: active),
          (_, null, final String beast) => _JointGuardFormationView(
              beastCode: beast,
              difficulty: _difficulty ?? 'outer_walk',
              onBack: _backToEntry,
            ),
          _ => _JointGuardEntryView(onChoose: _chooseBeast),
        },
      ),
    );
  }
}
