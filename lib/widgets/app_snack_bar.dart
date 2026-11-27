import 'package:flutter/material.dart';
import '../app/app_colors.dart';

/// One consistent status card; callers retain the message, action and duration.
SnackBar appSnackBar({
  required Widget content,
  required Color backgroundColor,
  Duration duration = const Duration(seconds: 4),
  SnackBarAction? action,
}) {
  final icon = backgroundColor == AppColors.success
      ? Icons.check_circle_outline_rounded
      : backgroundColor == AppColors.danger
      ? Icons.error_outline_rounded
      : Icons.info_outline_rounded;
  return SnackBar(
    backgroundColor: backgroundColor,
    duration: duration,
    action: action,
    padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 14),
    content: Row(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: content),
      ],
    ),
  );
}
