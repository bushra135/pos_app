import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../app/app_spacing.dart';

/// The store's BenefitPay QR image from its Base64 data, or a placeholder when
/// there is none or the data cannot be shown.
class QrImageBox extends StatelessWidget {
  const QrImageBox({
    super.key,
    required this.base64,
    required this.size,
    required this.placeholderColor,
    required this.placeholderIcon,
  });

  final String base64;
  final double size;
  final Color placeholderColor;
  final IconData placeholderIcon;

  Widget _placeholder() => Container(
    height: size,
    width: size,
    decoration: BoxDecoration(
      color: placeholderColor,
      borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
    ),
    child: Icon(placeholderIcon, size: 70, color: AppColors.muted),
  );

  @override
  Widget build(BuildContext context) {
    if (base64.isEmpty) return _placeholder();
    try {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
        child: Image.memory(
          base64Decode(base64),
          height: size,
          width: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(),
        ),
      );
    } on FormatException {
      // Invalid Base64 data uses the same placeholder.
      return _placeholder();
    }
  }
}
