import 'package:flutter/material.dart';

import '../../../core/theme/mongroo_ui.dart';
import '../../home/presentation/reward_feedback.dart';
import '../domain/garden_models.dart';
import 'garden_item_visual.dart';

Future<bool?> showGardenUnlock(
  BuildContext context, {
  required ShopItem item,
  required int seedBalance,
  String? actionLabel,
}) =>
    showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Expanded(
                      child: Text('해금 완료',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  MongrooSeedToken(value: seedBalance),
                ]),
                const SizedBox(height: 12),
                MilestoneReveal(
                  child: SizedBox(
                    height: 190,
                    child: GardenItemVisual(
                        item: item, animateIdle: false, cacheWidth: 512),
                  ),
                ),
                const SizedBox(height: 16),
                Text(item.name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  item.isGrowthCharacter
                      ? '새 씨앗이 도감에 들어왔어요. 함께 키워 보세요.'
                      : item.isRoomTheme
                          ? '이제 내 방에 이 테마를 쓸 수 있어요.'
                          : '내 아이템에 추가했어요. 방에서 꺼내 쓸 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(actionLabel != null),
                  child: Text(actionLabel ?? '확인'),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('나중에 할게요')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
