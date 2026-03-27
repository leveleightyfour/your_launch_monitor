import 'package:flutter/material.dart';
import 'package:omni_sniffer/shared/theme.dart';

class ErrorBanner extends StatelessWidget {
  final String message;

  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.errorBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: AppTextStyles.sans(size: 12, color: AppColors.errorText),
      ),
    );
  }
}
