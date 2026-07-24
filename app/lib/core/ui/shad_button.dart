import 'package:flutter/material.dart';

import '../theme/brand.dart';
import 'ui_tokens.dart';

/// shadcn Button 의 variant (React 의 `variant` prop 재해석).
enum ShadVariant { primary, secondary, outline, ghost, destructive, link }

/// shadcn Button 의 size (`size` prop).
enum ShadSize { sm, md, lg, icon }

/// shadcn `<Button>` 을 Flutter 로 재해석한 재사용 버튼.
///
/// ```dart
/// ShadButton(onPressed: ..., child: Text('저장'))                 // 기본(solid)
/// ShadButton.outline(onPressed: ..., child: Text('취소'))
/// ShadButton(variant: ShadVariant.ghost, icon: Icons.add, ...)
/// ShadButton(loading: true, ...)                                  // 스피너 + 비활성
/// ```
class ShadButton extends StatelessWidget {
  const ShadButton({
    super.key,
    required this.child,
    this.onPressed,
    this.variant = ShadVariant.primary,
    this.size = ShadSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
  });

  const ShadButton.outline({
    super.key,
    required this.child,
    this.onPressed,
    this.size = ShadSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
  }) : variant = ShadVariant.outline;

  const ShadButton.ghost({
    super.key,
    required this.child,
    this.onPressed,
    this.size = ShadSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
  }) : variant = ShadVariant.ghost;

  const ShadButton.destructive({
    super.key,
    required this.child,
    this.onPressed,
    this.size = ShadSize.md,
    this.icon,
    this.loading = false,
    this.expanded = false,
  }) : variant = ShadVariant.destructive;

  final Widget child;
  final VoidCallback? onPressed;
  final ShadVariant variant;
  final ShadSize size;
  final IconData? icon;
  final bool loading;
  final bool expanded;

  double get _height => switch (size) {
        ShadSize.sm => 36,
        ShadSize.md => 44,
        ShadSize.lg => 48,
        ShadSize.icon => 40,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null && !loading;

    final ({Color bg, Color fg, BorderSide? side}) style = switch (variant) {
      ShadVariant.primary => (bg: scheme.primary, fg: scheme.onPrimary, side: null),
      ShadVariant.secondary => (bg: scheme.surfaceContainerHighest, fg: scheme.onSurface, side: null),
      ShadVariant.outline => (bg: Colors.transparent, fg: scheme.onSurface, side: BorderSide(color: scheme.outline)),
      ShadVariant.ghost => (bg: Colors.transparent, fg: scheme.onSurface, side: null),
      ShadVariant.destructive => (bg: scheme.error, fg: scheme.onError, side: null),
      ShadVariant.link => (bg: Colors.transparent, fg: scheme.onSurface, side: null),
    };

    Widget content;
    if (loading) {
      content = SizedBox(
        height: 18, width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: style.fg),
      );
    } else {
      final label = DefaultTextStyle.merge(
        style: TextStyle(
          color: style.fg,
          fontWeight: FontWeight.w600,
          fontSize: size == ShadSize.sm ? 13 : 14,
          decoration: variant == ShadVariant.link ? TextDecoration.underline : null,
        ),
        child: IconTheme.merge(data: IconThemeData(color: style.fg, size: 18), child: child),
      );
      content = icon == null
          ? label
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(icon, size: 18, color: style.fg), const SizedBox(width: 8), label],
            );
    }

    // 메인 버튼은 보라 그라데이션 + 소프트 섀도로 강조한다.
    final useGradient = variant == ShadVariant.primary;
    final radius = BorderRadius.circular(UiTokens.radius);

    final button = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: useGradient && enabled ? Brand.softShadow(y: 6, blur: 18, opacity: 0.35) : null,
        ),
        child: Material(
          color: useGradient ? Colors.transparent : style.bg,
          shape: RoundedRectangleBorder(borderRadius: radius, side: style.side ?? BorderSide.none),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: useGradient ? BoxDecoration(gradient: Brand.gradient, borderRadius: radius) : null,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: Container(
                height: _height,
                padding: EdgeInsets.symmetric(horizontal: size == ShadSize.icon ? 0 : 16),
                width: size == ShadSize.icon ? _height : null,
                alignment: Alignment.center,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
