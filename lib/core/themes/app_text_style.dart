import 'package:flutter/material.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/app_colors.dart';

class AppTextStyle {
  static final lightTextStyle = TextTheme(
    headlineLarge: const TextStyle().copyWith(
      fontSize: 32,
      fontWeight: .bold,
      color: AppColors.onSurfaceLight,
    ),
    headlineMedium: const TextStyle().copyWith(
      fontSize: 24,
      fontWeight: .w600,
      color: AppColors.onSurfaceLight,
    ),
    headlineSmall: const TextStyle().copyWith(
      fontSize: 18,
      fontWeight: .w600,
      color: AppColors.onSurfaceLight,
    ),

    titleLarge: const TextStyle().copyWith(
      fontSize: 16,
      fontWeight: .w600,
      color: AppColors.onSurfaceLight,
    ),
    titleMedium: const TextStyle().copyWith(
      fontSize: 16,
      fontWeight: .w500,
      color: AppColors.onSurfaceLight,
    ),
    titleSmall: const TextStyle().copyWith(
      fontSize: 16,
      fontWeight: .w400,
      color: AppColors.onSurfaceLight,
    ),

    bodyLarge: const TextStyle().copyWith(
      fontSize: 14,
      fontWeight: .w500,
      color: AppColors.onSurfaceLight,
    ),
    bodyMedium: const TextStyle().copyWith(
      fontSize: 14,
      fontWeight: .normal,
      color: AppColors.onSurfaceLight,
    ),
    bodySmall: const TextStyle().copyWith(
      fontSize: 14,
      fontWeight: .w500,
      color: AppColors.onSurfaceLight.withValues(alpha: 0.5),
    ),

    labelLarge: const TextStyle().copyWith(
      fontSize: 12,
      fontWeight: .normal,
      color: AppColors.onSurfaceLight,
    ),
    labelMedium: const TextStyle().copyWith(
      fontSize: 12,
      fontWeight: .normal,
      color: AppColors.onSurfaceLight.withValues(alpha: 0.5),
    ),
  );

  static final darkTextStyle = TextTheme(
    headlineLarge: const TextStyle().copyWith(
      fontSize: 32,
      fontWeight: .bold,
      color: AppColors.onSurfaceDark,
    ),
    headlineMedium: const TextStyle().copyWith(
      fontSize: 24,
      fontWeight: .w600,
      color: AppColors.onSurfaceDark,
    ),
    headlineSmall: const TextStyle().copyWith(
      fontSize: 18,
      fontWeight: .w600,
      color: AppColors.onSurfaceDark,
    ),

    titleLarge: const TextStyle().copyWith(
      fontSize: 16,
      fontWeight: .w600,
      color: AppColors.onSurfaceDark,
    ),
    titleMedium: const TextStyle().copyWith(
      fontSize: 16,
      fontWeight: .w500,
      color: AppColors.onSurfaceDark,
    ),
    titleSmall: const TextStyle().copyWith(
      fontSize: 16,
      fontWeight: .w400,
      color: AppColors.onSurfaceDark,
    ),

    bodyLarge: const TextStyle().copyWith(
      fontSize: 14,
      fontWeight: .w500,
      color: AppColors.onSurfaceDark,
    ),
    bodyMedium: const TextStyle().copyWith(
      fontSize: 14,
      fontWeight: .normal,
      color: AppColors.onSurfaceDark,
    ),
    bodySmall: const TextStyle().copyWith(
      fontSize: 14,
      fontWeight: .w500,
      color: AppColors.onSurfaceDark.withValues(alpha: 0.5),
    ),

    labelLarge: const TextStyle().copyWith(
      fontSize: 12,
      fontWeight: .normal,
      color: AppColors.onSurfaceDark,
    ),
    labelMedium: const TextStyle().copyWith(
      fontSize: 12,
      fontWeight: .normal,
      color: AppColors.onSurfaceDark.withValues(alpha: 0.5),
    ),
  );
}