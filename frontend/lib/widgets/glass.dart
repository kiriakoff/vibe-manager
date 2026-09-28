import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Frosted-glass container used for cards, panels and the login box.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;
  final double blur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.blur = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: VibeColors.cardFill,
              borderRadius: borderRadius,
              border: Border.all(color: VibeColors.cardBorder),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
