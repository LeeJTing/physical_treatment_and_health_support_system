import 'package:flutter/material.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/app_colors.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/app_text_style.dart';

final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: AppColors.primaryLight,
      secondary: AppColors.secondaryLight,
      surface: AppColors.surfaceLight,
      onSurface: AppColors.onSurfaceLight,
      error: Colors.red,
    ),
    textTheme: AppTextStyle.lightTextStyle
);

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme.dark(
    primary: AppColors.primaryDark,
    secondary: AppColors.secondaryDark,
    surface: AppColors.surfaceDark,
    onSurface: AppColors.onSurfaceDark,
    error: Colors.red,
  ),
  textTheme: AppTextStyle.darkTextStyle,
);