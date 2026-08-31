import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/mongroo_ui.dart';
import '../domain/skill_book_models.dart';
import 'skill_book_controller.dart';

/// 마음결 기록서 서고와 장착 화면.
///
/// 두 가지를 한 화면에서 본다. 지금 두 칸에 무엇이 들어 있는지, 그리고 서고에
/// 무엇이 있고 없는지다. 아직 없는 책도 숨기지 않고 어디서 얻는지 보여 준다 —
/// 획득 경로에 확률이 없어서 숨길 이유가 없다.
class SkillBookScreen extends ConsumerWidget {
  const SkillBookScreen({super.key, required this.plantId, this.plantName});

  final int plantId;
  final String? plantName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(skillBookControllerProvider(plantId));
    final notifier = ref.read(skillBookControllerProvider(plantId).notifier);

    return Scaffold(
      appBar: AppBar(title: Text(plantName == null ? '마음결 기록서' : '$plantName의 기록서')),
      body: SafeArea(
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : !state.ready
                ? _ErrorView(
                    message: state.error ?? '기록서를 불러오지 못했어요.',
                    onRetry: notifier.load,
                  )
                : _LoadoutBody(
                    state: state,
                    onEquip: (slot, code) =>
                        notifier.equip(slot: slot, code: code),
                    onPreset: notifier.selectPreset,
                  ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
}

class _LoadoutBody extends StatelessWidget {
  const _LoadoutBody({
    required this.state,
    required this.onEquip,
    required this.onPreset,
  });

  final SkillBookState state;
  final Future<bool> Function(String slot, String? code) onEquip;
  final Future<void> Function(String preset) onPreset;

  @override
  Widget build(BuildContext context) {
    final loadout = state.loadout!;
    final library = state.library!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _PresetRow(
          presets: library.presets,
          selected: state.presetCode,
          onSelected: onPreset,
        ),
        const SizedBox(height: 12),
        // 저장한 선택이 그대로 쓰이지 못했으면 조용히 넘어가지 않는다.
        if (state.notice != null)
          _Banner(text: state.notice!, tone: _BannerTone.notice),
        if (state.error != null)
          _Banner(text: state.error!, tone: _BannerTone.error),
        for (final slot in const ['B1', 'B2']) ...[
          _SlotCard(
            slot: slot,
            loadout: loadout,
            library: library,
            saving: state.saving,
            onEquip: onEquip,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        Text('서고', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '아직 없는 기록서도 어디서 얻는지 함께 보여 줘요.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final book in library.catalog)
          _BookRow(
            book: book,
            progress: library.progressFor(book.code),
            key: ValueKey('book-${book.code}'),
          ),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.presets,
    required this.selected,
    required this.onSelected,
  });

  final List<String> presets;
  final String selected;
  final Future<void> Function(String preset) onSelected;

  static const _labels = {
    'explore': '탐험',
    'guard': '수호',
    'personal': '나만의',
  };

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        children: [
          for (final preset in presets)
            ChoiceChip(
              key: ValueKey('preset-$preset'),
              label: Text(_labels[preset] ?? preset),
              selected: preset == selected,
              onSelected: (_) => onSelected(preset),
            ),
        ],
      );
}

enum _BannerTone { notice, error }

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.tone});

  final String text;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = tone == _BannerTone.error
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = tone == _BannerTone.error
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, style: TextStyle(color: foreground)),
        ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.loadout,
    required this.library,
    required this.saving,
    required this.onEquip,
  });

  final String slot;
  final SkillLoadout loadout;
  final SkillBookLibrary library;
  final bool saving;
  final Future<bool> Function(String slot, String? code) onEquip;

  @override
  Widget build(BuildContext context) {
    final decision = loadout.slot(slot);
    final open = loadout.isSlotOpen(slot);
    final unlockLevel = loadout.slotUnlockLevel[slot] ?? 0;
    final title = slot == 'B1' ? '선택 I' : '선택 II';

    return MongrooPanel(
      key: ValueKey('slot-$slot'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (!open)
                  Text(
                    'Lv$unlockLevel부터',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              decision?.label ?? '아직 열리지 않음',
              key: ValueKey('slot-$slot-label'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            // 왜 못 누르는지, 왜 다른 게 들어갔는지를 항상 문장으로 남긴다.
            if (decision?.lockReason != null) ...[
              const SizedBox(height: 4),
              Text(
                decision!.lockReason!,
                key: ValueKey('slot-$slot-reason'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _EquipButton(
                  label: '성장결 기본',
                  slot: slot,
                  code: 'emotion.primary',
                  enabled: open && !saving,
                  selected: loadout.storedFor(slot) == 'emotion.primary',
                  onEquip: onEquip,
                ),
                for (final book in library.catalog)
                  if (book.owned)
                    _EquipButton(
                      label: book.name,
                      slot: slot,
                      code: book.code,
                      enabled: open && !saving && library.canEquip(book, slot),
                      selected: loadout.storedFor(slot) == book.code,
                      // 3등급이 B1에 못 들어가는 이유를 누르기 전에 알려 준다.
                      disabledReason: book.isGradeThree && slot == 'B1'
                          ? '3등급은 두 번째 칸에서만 펼쳐져요'
                          : null,
                      onEquip: onEquip,
                    ),
                if (loadout.storedFor(slot) != null)
                  _EquipButton(
                    label: '비우기',
                    slot: slot,
                    code: null,
                    enabled: open && !saving,
                    selected: false,
                    onEquip: onEquip,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EquipButton extends StatelessWidget {
  const _EquipButton({
    required this.label,
    required this.slot,
    required this.code,
    required this.enabled,
    required this.selected,
    required this.onEquip,
    this.disabledReason,
  });

  final String label;
  final String slot;
  final String? code;
  final bool enabled;
  final bool selected;
  final String? disabledReason;
  final Future<bool> Function(String slot, String? code) onEquip;

  @override
  Widget build(BuildContext context) {
    final semantics = disabledReason == null
        ? '$label ${selected ? '장착됨' : '장착하기'}'
        : '$label, $disabledReason';
    return Semantics(
      label: semantics,
      button: true,
      child: SizedBox(
        // 기록서를 갈아 끼우는 자리다. Android 핵심 앱 품질 지침의 48dp를
        // 따른다 - 44는 Apple 기준만 만족한다.
        height: 48,
        child: FilterChip(
          key: ValueKey('equip-$slot-${code ?? 'clear'}'),
          selected: selected,
          onSelected: enabled
              ? (_) {
                  HapticFeedback.selectionClick();
                  onEquip(slot, code);
                }
              : null,
          label: Text(label),
          tooltip: disabledReason,
        ),
      ),
    );
  }
}

/// 발동 방식을 한 글자 그림으로.
///
/// 서고에서 가장 먼저 알아야 할 것은 효과가 아니라 **`내가 눌러야 하나, 저절로
/// 되나`**다. 그게 편성 판단을 바꾼다 — 명령형은 대원 행동 한 번을 먹으므로
/// 두 권을 다 명령형으로 채우면 정작 때릴 사람이 없다. 글로만 적혀 있으면
/// 스무 권을 다 읽어야 알 수 있어서 그림으로 갈라 둔다.
///
/// 래스터 아이콘을 새로 만들지 않는다. 장면 테마가 이미 Material 아이콘을 쓰고
/// 있어 화풍이 어긋나지 않고, 스무 권 × 등급 조합을 그림으로 그리면 관리할
/// 자산만 늘어난다.
IconData skillBookActivationIcon(String activationMode) => switch (activationMode) {
      // 전투가 시작되면 저절로 — 해가 뜨듯이.
      'opening' => Icons.wb_twilight_rounded,
      // 조건이 맞으면 저절로 — 튀는 순간.
      'trigger' => Icons.bolt_rounded,
      // 내가 눌러야 한다 — 대원 행동 한 번을 쓴다.
      _ => Icons.touch_app_rounded,
    };

String skillBookActivationLabel(String activationMode) => switch (activationMode) {
      'opening' => '전투 시작에 저절로',
      'trigger' => '조건이 맞으면 저절로',
      _ => '눌러서 사용 · 행동 1회',
    };

/// 등급 색. 3등급은 예산 2를 쓰는 대신 반드시 대가를 지므로 가장 눈에 띈다.
Color skillBookGradeColor(int grade, ColorScheme scheme) => switch (grade) {
      3 => scheme.tertiary,
      2 => scheme.primary,
      _ => scheme.outline,
    };

class _BookRow extends StatelessWidget {
  const _BookRow({super.key, required this.book, this.progress});

  final SkillBook book;

  /// 조건이 얼마나 찼는지. 서버가 세어 준 값이며 조건 없는 책에는 없다.
  final SkillBookUnlockProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Opacity(
        // 없는 책도 지우지 않고 흐리게 둔다. 무엇을 모으면 되는지가 목표가 된다.
        //
        // .58에서는 본문이 3.77:1이라 정작 `무엇을 모으면 되는지`가 안 읽혔다.
        // 흐리게 두는 뜻은 살리되 AA(4.5:1)를 넘기는 .7로 올린다.
        opacity: book.owned ? 1 : .7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 발동 방식과 등급을 한 덩어리로 읽는다. 테두리 색이 등급이고
                // 안의 그림이 발동 방식이다.
                Semantics(
                  label:
                      '${book.grade}등급, ${skillBookActivationLabel(book.activationMode)}',
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: skillBookGradeColor(
                          book.grade,
                          theme.colorScheme,
                        ),
                        width: book.grade >= 3 ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      skillBookActivationIcon(book.activationMode),
                      size: 16,
                      color: skillBookGradeColor(book.grade, theme.colorScheme),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.name, style: theme.textTheme.titleSmall),
                      Text(
                        '${book.grade}등급 · '
                        '${skillBookActivationLabel(book.activationMode)}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                if (!book.owned)
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          book.acquireLabel,
                          style: theme.textTheme.labelSmall,
                          textAlign: TextAlign.end,
                        ),
                        // 조건만 적고 얼마나 왔는지 안 적으면 `30회`가
                        // 시작인지 끝인지 알 수 없다. 서버가 세어 보내는
                        // 값을 그대로 보여 준다.
                        if (progress case final counter?)
                          Text(
                            '${counter.current} / ${counter.goal}',
                            key: ValueKey('book-progress-${book.code}'),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: counter.complete
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            // 아래 설명은 위 이름과 같은 줄에서 시작해야 한다. 그냥 두면
            // 등급 아이콘보다 왼쪽에서 시작해 한 항목이 두 덩어리로 보인다.
            // 30(아이콘) + 8(간격)만큼 들여쓴다.
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.effectSummary, style: theme.textTheme.bodySmall),
                  if (book.tradeoff != null)
                    Text(
                      '대가 · ${book.tradeoff}',
                      style: theme.textTheme.bodySmall,
                    ),
                  // 효과가 아직 판정에 없으면 그렇다고 밝힌다. 있는 척하지 않는다.
                  if (!book.combatEffect)
                    Text(
                      '효과를 준비하고 있어요',
                      key: ValueKey('pending-${book.code}'),
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
