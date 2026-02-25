import 'package:flutter/material.dart';

import '../services/theme_mode_service.dart';

const Color _lightTextColor = Color(0xFF0D0106);
const Color _darkTextColor = Color(0xFFF5F5F5);
const Color accentGold = Color(0xFFFFB20F);
const Color accentRed = Color(0xFFFF331F);
const Color _lightBackground = Color(0xFFEBEBEB);
const Color _darkBackground = Color(0xFF111418);
const Color _lightSurface = Color(0xFFFFFFFF);
const Color _darkSurface = Color(0xFF1D232B);

Color get textColor =>
    ThemeModeService.isDarkActive ? _darkTextColor : _lightTextColor;

Color get appBackground =>
    ThemeModeService.isDarkActive ? _darkBackground : _lightBackground;

Color get surfaceColor =>
    ThemeModeService.isDarkActive ? _darkSurface : _lightSurface;

Color get inputFillColor => ThemeModeService.isDarkActive
    ? _darkSurface.withValues(alpha: 0.94)
    : _lightSurface.withValues(alpha: 0.92);
