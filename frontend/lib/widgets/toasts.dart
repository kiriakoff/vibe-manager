import 'package:flutter/material.dart';

import '../theme.dart';

/// Dark glass toast with a neon left edge, matching the "vibe" styling.
void showVibeToast(
  BuildContext context,
  String message, {
  bool success = true,
}) {
  final color = success ? VibeColors.green : VibeColors.red;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: VibeColors.textPrimary),
              ),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.45)),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
}
