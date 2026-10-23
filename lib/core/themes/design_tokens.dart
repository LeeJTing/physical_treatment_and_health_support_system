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
  static const primary = Color(
    0xFF0E3B35,
  ); // dark green cards, header band, outlined buttons
  static const onPrimaryMuted = Color(0xFF9FE1CB); // subtitle text on primary
  static const accent = Color(
    0xFF0F6E56,
  ); // screen subtitles, chip and badge text
  static const accentContainer = Color(0xFFE1F5EE); // chips, step badges
  static const highlight = Color(
    0xFF5DCAA5,
  ); // border of the best-matching plan
  static const progress = Color(0xFF1D9E75);

  // Text
  static const text = Color(0xFF1F2937);
  static const textBody = Color(0xFF444441);
  static const textMuted = Color(0xFF6B7280);

  // Actions and status
  // Select. Was the Figma #D85A30: white text on it is 3.9:1, below WCAG AA 4.5:1; now the
  // darker orange of "Log In" (5.1:1), Elwin, 23 Oct.
  static const action = Color(0xFFC34317);
  static const danger = Color(0xFFE24B4A); // Reject all plans
  static const dangerContainer = Color(
    0xFFFCE8E7,
  ); // urgent safety answer in the chat
  static const onDanger = Color(0xFF8E1F1E);
  static const good = Color(0xFF27500A);
  static const goodContainer = Color(0xFFEAF3DE);
  static const caution = Color(0xFF854F0B);
  static const cautionContainer = Color(0xFFFAEEDA);

  // Login and Profile screens. Their Figma frames use a slightly different
  // green, orange and background from the planning screens above.
  static const brandDeep = Color(
    0xFF054E4A,
  ); // header band, selected chips, avatar initials
  static const brandDeepAccent = Color(
    0xFF0C675F,
  ); // logo circle, "Forgot password?", "Edit"
  static const onBrandMuted = Color(0xFF80B5AE); // subtitle on the header band
  static const screenBackground = Color(0xFFF6F9F8);
  static const ink = Color(0xFF0C1A19); // headings
  static const inkMuted = Color(0xFF5A6B69); // field labels, secondary text
  static const outline = Color(
    0xFF6E8481,
  ); // text-field and outlined-button borders
  static const cta = Color(0xFFC34317); // "Log In", "Create account", "Log out"
  static const cardBorder = Color(0xFFDDE7E5);
  static const tint = Color(
    0xFFE3EFED,
  ); // health-profile stats card, avatar circle
  static const warnContainer = Color(
    0xFFFDF1DD,
  ); // risk pill, BMI pill, advisory banner
  static const onWarn = Color(0xFF8B5200);
  static const successContainer = Color(0xFFE5F4EB); // "Connected" pill
  static const radiusField = 14.0;
  static const radiusPill = 28.0; // Log In and Google buttons are fully rounded

  // Dimensions
  static const gutter = 16.0;
  static const gap = 12.0;
  static const radiusCard = 12.0;
  static const radiusButton = 8.0;
  static const minTarget = 48.0;
}
