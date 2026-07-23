import 'package:flutter/material.dart';

import 'ui_tokens.dart';

/// shadcn `<Card>` 재해석 — 카드색 배경 + 1px 테두리 + 라운드, 그림자 없음.
///
/// shadcn 은 Card > CardHeader(CardTitle/CardDescription) > CardContent > CardFooter
/// 구조다. 아래처럼 슬롯으로 조립하거나, [child] 하나만 넘겨도 된다.
/// ```dart
/// ShadCard(
///   title: '앨범',
///   description: '사진 3 · 멤버 2',
///   child: ...,
///   footer: ShadButton(...),
/// )
/// ```
class ShadCard extends StatelessWidget {
  const ShadCard({
    super.key,
    this.child,
    this.title,
    this.description,
    this.leading,
    this.trailing,
    this.footer,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget? child;
  final String? title;
  final String? description;
  final Widget? leading;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasHeader = title != null || description != null || leading != null || trailing != null;

    final body = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader) _header(context, scheme),
          if (hasHeader && (child != null || footer != null)) const SizedBox(height: 12),
          ?child,
          if (footer != null) ...[const SizedBox(height: 16), footer!],
        ],
      ),
    );

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiTokens.radiusLg),
        side: BorderSide(color: scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme) {
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Text(title!, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        if (description != null) ...[
          if (title != null) const SizedBox(height: 2),
          Text(description!, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        ],
      ],
    );
    if (leading == null && trailing == null) return texts;
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(child: texts),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}
