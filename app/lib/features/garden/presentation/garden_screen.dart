import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_controller.dart';
import 'collection_tab.dart';
import 'farm_tab.dart';
import 'garden_item_visual.dart';
import 'shop_tab.dart';

class GardenScreen extends ConsumerWidget {
  const GardenScreen({
    super.key,
    this.initialTab = 0,
    this.initialSpeciesCode,
  });

  final int initialTab;
  final String? initialSpeciesCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seedBalance = ref.watch(
      authControllerProvider.select((state) => state.user?.seedBalance ?? 0),
    );
    final palette = MongrooPalette.of(context);
    return DefaultTabController(
      key: ValueKey((initialTab, initialSpeciesCode)),
      length: 3,
      initialIndex: initialTab.clamp(0, 2).toInt(),
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.yard_rounded, color: palette.leaf, size: 22),
              const SizedBox(width: 8),
              const Text(
                '나의 정원',
                style: TextStyle(
                  fontFamily: AppTheme.pixelFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '마음 식물 박물관',
              onPressed: () => context.go('/museum'),
              icon: const Icon(Icons.account_balance_outlined),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: SeedBalanceBadge(balance: seedBalance)),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(54),
            child: ColoredBox(
              color: palette.paper,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: palette.night,
                  unselectedLabelColor: palette.inkMuted,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  indicator: BoxDecoration(
                    color: AppTheme.seed,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0x263B1F06)),
                    ),
                  ),
                  tabs: const [
                    Tab(icon: Icon(Icons.home_outlined, size: 19), text: '방'),
                    Tab(
                      icon: Icon(Icons.storefront_outlined, size: 19),
                      text: '상점',
                    ),
                    Tab(
                      icon: Icon(Icons.auto_stories_outlined, size: 19),
                      text: '도감',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            const FarmTab(),
            ShopTab(initialSpeciesCode: initialSpeciesCode),
            const CollectionTab(),
          ],
        ),
      ),
    );
  }
}
