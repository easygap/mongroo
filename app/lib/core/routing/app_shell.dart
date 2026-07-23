import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../branding/mongroo_brand.dart';
import '../theme/app_theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 840) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  right: false,
                  child: _GameRail(
                    selectedIndex: navigationShell.currentIndex,
                    extended: constraints.maxWidth >= 1160,
                    onSelected: _goBranch,
                  ),
                ),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: _GameDock(
            selectedIndex: navigationShell.currentIndex,
            onSelected: _goBranch,
          ),
        );
      },
    );
  }

  void _goBranch(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _items = [
  _NavItem('오늘', Icons.wb_sunny_outlined, Icons.wb_sunny_rounded),
  _NavItem('기록', Icons.menu_book_outlined, Icons.menu_book_rounded),
  _NavItem('정원', Icons.cottage_outlined, Icons.cottage_rounded),
  _NavItem(
    '박물관',
    Icons.account_balance_outlined,
    Icons.account_balance_rounded,
  ),
  _NavItem('회고', Icons.insights_outlined, Icons.insights_rounded),
];

class _GameDock extends StatelessWidget {
  const _GameDock({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Material(
      color: palette.paper,
      elevation: 12,
      shadowColor: palette.night.withAlpha(42),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: palette.ink.withAlpha(28)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 70,
            child: Row(
              children: [
                for (var index = 0; index < _items.length; index++)
                  Expanded(
                    child: _DockDestination(
                      item: _items[index],
                      selected: selectedIndex == index,
                      onTap: () => onSelected(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockDestination extends StatelessWidget {
  const _DockDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final foreground = selected ? palette.ink : palette.inkMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: ExcludeSemantics(
        child: Tooltip(
          message: item.label,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 7, 4, 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration:
                        reduceMotion ? Duration.zero : MongrooMotion.standard,
                    curve: MongrooMotion.enter,
                    width: 38,
                    height: 30,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.seed : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: selected
                          ? Border.all(color: palette.ink.withAlpha(28))
                          : null,
                    ),
                    child: Icon(
                      selected ? item.selectedIcon : item.icon,
                      size: 21,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    maxLines: 1,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameRail extends StatelessWidget {
  const _GameRail({
    required this.selectedIndex,
    required this.extended,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Container(
      width: extended ? 188 : 76,
      color: palette.night,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(extended ? 16 : 10, 18, 10, 24),
            child: _BrandMark(extended: extended),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 7),
              itemBuilder: (context, index) => _RailDestination(
                item: _items[index],
                selected: selectedIndex == index,
                extended: extended,
                onTap: () => onSelected(index),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              extended ? '마음은 저마다 자라요' : '·',
              style: TextStyle(
                color: AppTheme.onNightMuted,
                fontFamily: AppTheme.pixelFont,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailDestination extends StatelessWidget {
  const _RailDestination({
    required this.item,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final foreground = selected ? palette.night : AppTheme.onNightMuted;
    final destination = Material(
      color: selected ? AppTheme.seed : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment:
                extended ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              if (extended) const SizedBox(width: 13),
              Icon(selected ? item.selectedIcon : item.icon,
                  color: foreground, size: 22),
              if (extended) ...[
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: ExcludeSemantics(
        child: extended
            ? destination
            : Tooltip(message: item.label, child: destination),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: '몽그루',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment:
              extended ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            const MongrooBrandMark(size: 44, withPlate: true),
            if (extended) ...[
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '몽그루',
                    style: TextStyle(
                      color: AppTheme.onNight,
                      fontFamily: AppTheme.pixelFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '마음 식물 키우기',
                    style: TextStyle(
                      color: AppTheme.onNightMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
