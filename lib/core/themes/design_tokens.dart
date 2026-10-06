import 'package:flutter/material.dart';

/// Colours and sizes measured from the Figma screens in the report's UI
/// Design section (Treatment, AI-assisted planning, Recommended plans).
/// Used by the treatment and planning screens. The team theme in
/// app_colors.dart is not changed; move these into it once the team agrees
/// on one palette.
class AppTokens {
  AppTokens._();

  // Surfaces
  static const background = Color(0xFFF5F4EF);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE4E2D8);

  // Brand
  static const primary = Color(0xFF0E3B35); // dark green cards, header band, outlined buttons
  static const onPrimaryMuted = Color(0xFF9FE1CB); // subtitle text on primary
  static const accent = Color(0xFF0F6E56); // screen subtitles, chip and badge text
  static const accentContainer = Color(0xFFE1F5EE); // chips, step badges
  static const highlight = Color(0xFF5DCAA5); // border of the best-matching plan
  static const progress = Color(0xFF1D9E75);

  // Text
  static const text = Color(0xFF1F2937);
  static const textBody = Color(0xFF444441);
  static const textMuted = Color(0xFF6B7280);

  // Actions and status
  static const action = Color(0xFFD85A30); // Select
  static const danger = Color(0xFFE24B4A); // Reject all plans
  static const good = Color(0xFF27500A);
  static const goodContainer = Color(0xFFEAF3DE);
  static const caution = Color(0xFF854F0B);
  static const cautionContainer = Color(0xFFFAEEDA);

  // Dimensions
  static const gutter = 16.0;
  static const gap = 12.0;
  static const radiusCard = 12.0;
  static const radiusButton = 8.0;
  static const minTarget = 48.0;
}
