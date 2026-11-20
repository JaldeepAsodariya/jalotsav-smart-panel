import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass.dart';

/// Frosted glass tile used by every card on the panel. [borderColor] tints
/// the pane (e.g. red while the alarm sounds).
class PanelCard extends StatelessWidget {
  const PanelCard({
    required this.child,
    this.title,
    this.borderColor,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final String? title;
  final Color? borderColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    return GlassSurface(
      tint: borderColor,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: context.text.labelLarge?.copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
