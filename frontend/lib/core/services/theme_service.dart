import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_theme.dart';
import '../values/app_constants.dart';
import 'device_integration_service.dart';

class ThemeService extends GetxService {
  final themeModeValue = 'system'.obs;
  final themeSeed = 'biostat'.obs;
  final useDynamicColor = false.obs;
  final amoledDark = false.obs;
  final dynamicAccentColor = Rxn<Color>();

  Future<ThemeService> init() async {
    await loadLocalSettings();
    return this;
  }

  ThemeMode get themeMode {
    switch (themeModeValue.value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  Color get effectiveSeedColor {
    if (useDynamicColor.value && dynamicAccentColor.value != null) {
      return dynamicAccentColor.value!;
    }
    return AppTheme.seedColorFor(themeSeed.value);
  }

  ThemeData get lightTheme =>
      AppTheme.buildLightTheme(seedColor: effectiveSeedColor);

  ThemeData get darkTheme => AppTheme.buildDarkTheme(
        seedColor: effectiveSeedColor,
        amoled: amoledDark.value,
      );

  Future<void> loadLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final rawTheme = prefs.get(AppConstants.themeKey);
    themeModeValue.value = _normalizeThemeMode(rawTheme);
    themeSeed.value = prefs.getString(AppConstants.themeSeedKey) ?? 'biostat';
    useDynamicColor.value =
        prefs.getBool(AppConstants.dynamicColorKey) ?? false;
    amoledDark.value = prefs.getBool(AppConstants.amoledDarkKey) ?? false;
    await _refreshDynamicAccent();
    await _saveLocalSettings();
  }

  Future<void> applySettings({
    String? themeMode,
    String? seed,
    bool? dynamicColor,
    bool? amoled,
    bool persist = true,
  }) async {
    if (themeMode != null) {
      themeModeValue.value = _normalizeThemeMode(themeMode);
    }
    if (seed != null) {
      themeSeed.value = _normalizeThemeSeed(seed);
    }
    if (dynamicColor != null) {
      useDynamicColor.value = dynamicColor;
    }
    if (amoled != null) {
      amoledDark.value = amoled;
    }
    await _refreshDynamicAccent();
    if (persist) await _saveLocalSettings();
  }

  Future<void> updateThemeMode(String value) async {
    await applySettings(themeMode: value);
  }

  Future<void> updateThemeSeed(String value) async {
    await applySettings(seed: value);
  }

  Future<void> toggleDynamicColor(bool value) async {
    await applySettings(dynamicColor: value);
  }

  Future<void> toggleAmoledDark(bool value) async {
    await applySettings(amoled: value);
  }

  Future<void> _refreshDynamicAccent() async {
    if (!useDynamicColor.value) {
      dynamicAccentColor.value = null;
      return;
    }
    final value = await DeviceIntegrationService.getDynamicAccentColor();
    dynamicAccentColor.value = value == null ? null : Color(value & 0xFFFFFFFF);
  }

  Future<void> _saveLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.themeKey, themeModeValue.value);
    await prefs.setString(AppConstants.themeSeedKey, themeSeed.value);
    await prefs.setBool(AppConstants.dynamicColorKey, useDynamicColor.value);
    await prefs.setBool(AppConstants.amoledDarkKey, amoledDark.value);
  }

  String _normalizeThemeMode(Object? value) {
    if (value is bool) return value ? 'dark' : 'light';
    if (value is String && {'system', 'light', 'dark'}.contains(value)) {
      return value;
    }
    return 'system';
  }

  String _normalizeThemeSeed(String value) {
    final exists = AppTheme.themeSeeds.any((seed) => seed.id == value);
    return exists ? value : 'biostat';
  }
}
