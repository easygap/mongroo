import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/branding/mongroo_brand.dart';
import '../../../core/theme/app_theme.dart';

/// 인증 폼을 코드로 그린 포켓 게임 타이틀 화면과 함께 배치한다.
///
/// 모바일은 타이틀 패널 아래에 폼을 이어 보여 주고, 넓은 화면은
/// 두 영역을 나란히 둔다. 둘 다 폼은 단일 세로 스크롤 안에 머물러
/// 키보드와 큰 글자 환경에서도 입력 필드가 가려지지 않는다.
class AuthScene extends StatelessWidget {
  const AuthScene({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.showBack = false,
    this.navigationLocked = false,
  });

  final String title;
  final String description;
  final Widget child;
  final bool showBack;
  final bool navigationLocked;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return PopScope(
      canPop: !navigationLocked,
      child: Scaffold(
        backgroundColor: palette.paper,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 880) {
                return Row(
                  children: [
                    const Expanded(flex: 5, child: _PocketTitlePanel()),
                    Expanded(
                      flex: 6,
                      child: _ScrollableForm(
                        title: title,
                        description: description,
                        showBack: showBack,
                        navigationLocked: navigationLocked,
                        child: child,
                      ),
                    ),
                  ],
                );
              }
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _PocketTitlePanel(compact: true),
                    _FormPanel(
                      title: title,
                      description: description,
                      showBack: showBack,
                      navigationLocked: navigationLocked,
                      padding: EdgeInsets.fromLTRB(
                        constraints.maxWidth < 360 ? 16 : 24,
                        28,
                        constraints.maxWidth < 360 ? 16 : 24,
                        36,
                      ),
                      child: child,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ScrollableForm extends StatelessWidget {
  const _ScrollableForm({
    required this.title,
    required this.description,
    required this.showBack,
    required this.navigationLocked,
    required this.child,
  });

  final String title;
  final String description;
  final bool showBack;
  final bool navigationLocked;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const padding = EdgeInsets.symmetric(horizontal: 48, vertical: 32);
          final minHeight = constraints.maxHeight > padding.vertical
              ? constraints.maxHeight - padding.vertical
              : 0.0;
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(
                child: _FormPanel(
                  title: title,
                  description: description,
                  showBack: showBack,
                  navigationLocked: navigationLocked,
                  child: child,
                ),
              ),
            ),
          );
        },
      );
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.title,
    required this.description,
    required this.showBack,
    required this.navigationLocked,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String description;
  final bool showBack;
  final bool navigationLocked;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBack) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: '로그인으로 돌아가기',
                  onPressed: navigationLocked
                      ? null
                      : () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/login');
                          }
                        },
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(48),
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Container(width: 36, height: 4, color: palette.coral),
                const SizedBox(width: 5),
                Container(width: 10, height: 4, color: palette.butter),
              ],
            ),
            const SizedBox(height: 14),
            Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: palette.ink,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: palette.inkMuted,
                  ),
            ),
            const SizedBox(height: 28),
            child,
          ],
        ),
      ),
    );
  }
}

class _PocketTitlePanel extends StatelessWidget {
  const _PocketTitlePanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.brightness == Brightness.dark
        ? scheme.onSurface
        : scheme.onInverseSurface;
    final backdrop = _PocketBackdropPainter(
      gridColor: foreground.withAlpha(16),
      coral: palette.coral.withAlpha(150),
      butter: palette.butter.withAlpha(135),
      leaf: palette.leaf.withAlpha(155),
    );

    Widget content({required bool horizontal}) {
      final markSize = compact ? 104.0 : 180.0;
      final copy = ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              horizontal ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Text(
              '몽그루',
              textAlign: horizontal ? TextAlign.start : TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: foreground,
                    fontFamily: AppTheme.pixelFont,
                    fontSize: compact ? 25 : 36,
                    letterSpacing: 0,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '감정 기록 · 식물 성장',
              textAlign: horizontal ? TextAlign.start : TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground.withAlpha(205),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment:
                  horizontal ? WrapAlignment.start : WrapAlignment.center,
              spacing: 7,
              runSpacing: 7,
              children: [
                _PocketFeature(label: '기록', color: palette.coral),
                _PocketFeature(label: '성장', color: palette.butter),
                _PocketFeature(label: '수집', color: palette.leaf),
              ],
            ),
          ],
        ),
      );
      if (horizontal) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            MongrooPocketMark(size: markSize),
            const SizedBox(width: 20),
            Expanded(child: copy),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MongrooPocketMark(size: markSize),
          SizedBox(height: compact ? 18 : 28),
          copy,
        ],
      );
    }

    final panel = ColoredBox(
      color: palette.night,
      child: CustomPaint(
        painter: backdrop,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final horizontal =
                compact && constraints.maxWidth >= 330 && textScale <= 1.25;
            final body = Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 22 : 48,
                vertical: compact ? 24 : 48,
              ),
              child: content(horizontal: horizontal),
            );
            if (compact) return body;
            final minHeight =
                constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Center(child: body),
              ),
            );
          },
        ),
      ),
    );

    return Semantics(
      header: true,
      label: '몽그루, 감정 기록과 식물 성장',
      child: panel,
    );
  }
}

class _PocketFeature extends StatelessWidget {
  const _PocketFeature({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.brightness == Brightness.dark
        ? scheme.onSurface
        : scheme.onInverseSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color.withAlpha(190)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontFamily: AppTheme.pixelFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

/// 기존 화면 API를 유지하면서 새 BI 심볼을 인증·스플래시에 공유합니다.
class MongrooPocketMark extends StatelessWidget {
  const MongrooPocketMark({super.key, this.size = 160});

  final double size;

  @override
  Widget build(BuildContext context) =>
      MongrooBrandMark(size: size, withPlate: true);
}

/// 서버 오류를 폼 안에서 즉시 읽을 수 있게 알린다.
/// 오류는 아니지만 왜 이 화면에 있는지 알려 주는 한 줄.
///
/// 붉은 경고 면을 쓰면 사용자가 뭘 잘못한 것처럼 읽힌다. 세션 만료는 잘못이
/// 아니라 그냥 시간이 지난 것이라 중립적인 면을 쓴다.
class AuthInlineNotice extends StatelessWidget {
  const AuthInlineNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_clock_outlined,
                    size: 20, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: scheme.onSecondaryContainer),
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

class AuthInlineError extends StatelessWidget {
  const AuthInlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '오류: $message',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 20, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: scheme.onErrorContainer),
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

class _PocketBackdropPainter extends CustomPainter {
  const _PocketBackdropPainter({
    required this.gridColor,
    required this.coral,
    required this.butter,
    required this.leaf,
  });

  final Color gridColor;
  final Color coral;
  final Color butter;
  final Color leaf;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..isAntiAlias = false
      ..color = gridColor
      ..strokeWidth = 1;
    for (var x = 24.0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 24.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    void pixel(double x, double y, Color color, [double side = 6]) {
      canvas.drawRect(
        Rect.fromLTWH(size.width * x, size.height * y, side, side),
        Paint()
          ..isAntiAlias = false
          ..color = color,
      );
    }

    pixel(.10, .15, butter);
    pixel(.82, .12, coral, 8);
    pixel(.88, .37, leaf);
    pixel(.13, .72, coral);
    pixel(.77, .82, butter, 8);
    pixel(.37, .08, leaf, 4);
  }

  @override
  bool shouldRepaint(covariant _PocketBackdropPainter oldDelegate) =>
      oldDelegate.gridColor != gridColor ||
      oldDelegate.coral != coral ||
      oldDelegate.butter != butter ||
      oldDelegate.leaf != leaf;
}
