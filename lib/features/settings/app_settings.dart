import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../subtitles/open_subtitles.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureSecretStore implements SecretStore {
  const SecureSecretStore();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) => value == null
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);
}

enum AppBaseColor {
  defaultColor('Default', Color(0xFFF3F1F1)),
  neutral('Neutral', Color(0xFFF5F5F5)),
  stone('Stone', Color(0xFFF5F5F4)),
  zinc('Zinc', Color(0xFFF4F4F5)),
  mauve('Mauve', Color(0xFFF3F1F3)),
  olive('Olive', Color(0xFFF4F4F0)),
  mist('Mist', Color(0xFFF1F3F3)),
  taupe('Taupe', Color(0xFFF3F1F1));

  const AppBaseColor(this.label, this.color);
  final String label;
  final Color color;
}

enum AppPrimaryColor {
  defaultColor('Default', Color(0xFFC10007)),
  base('Base', Color(0xFF171717)),
  amber('Amber', Color(0xFFBB4D00)),
  blue('Blue', Color(0xFF1447E6)),
  cyan('Cyan', Color(0xFF007595)),
  emerald('Emerald', Color(0xFF007A55)),
  fuchsia('Fuchsia', Color(0xFFA800B7)),
  green('Green', Color(0xFF008236)),
  indigo('Indigo', Color(0xFF432DD7)),
  lime('Lime', Color(0xFF9AE600)),
  orange('Orange', Color(0xFFCA3500)),
  pink('Pink', Color(0xFFC6005C)),
  purple('Purple', Color(0xFF8200DB)),
  red('Red', Color(0xFFC10007)),
  rose('Rose', Color(0xFFC70036)),
  sky('Sky', Color(0xFF0069A8)),
  teal('Teal', Color(0xFF00786F)),
  violet('Violet', Color(0xFF7008E7)),
  yellow('Yellow', Color(0xFFFDC700));

  const AppPrimaryColor(this.label, this.color);
  final String label;
  final Color color;
}

class AppSettings extends ChangeNotifier {
  AppSettings({SecretStore secretStore = const SecureSecretStore()})
    : _secretStore = secretStore;

  final SecretStore _secretStore;
  static const _themeKey = 'terra.settings.theme.v1';
  static const _baseKey = 'terra.settings.base.v1';
  static const _primaryKey = 'terra.settings.primary.v1';
  static const _legacyPaletteKey = 'terra.settings.palette.v1';
  static const _languageKey = 'terra.settings.language.v1';
  static const subtitleLanguageKey = 'terra.subtitles.language.v1';
  static const subdlApiKeyName = 'terra.subtitles.subdl_key.v1';

  ThemeMode themeMode = ThemeMode.system;
  AppBaseColor baseColor = AppBaseColor.defaultColor;
  AppPrimaryColor primaryColor = AppPrimaryColor.defaultColor;
  Locale? locale;
  String subtitleLanguage = 'eng';
  String subdlApiKey = '';

  Future<void> load() async {
    final preferences = SharedPreferencesAsync();
    final storedTheme = await preferences.getString(_themeKey);
    final storedBase = await preferences.getString(_baseKey);
    final storedPrimary = await preferences.getString(_primaryKey);
    final legacyPalette = await preferences.getString(_legacyPaletteKey);
    themeMode = ThemeMode.values.firstWhere(
      (value) => value.name == storedTheme,
      orElse: () => ThemeMode.system,
    );
    baseColor = AppBaseColor.values.firstWhere(
      (value) => value.name == storedBase,
      orElse: () => AppBaseColor.defaultColor,
    );
    primaryColor = AppPrimaryColor.values.firstWhere(
      (value) => value.name == storedPrimary,
      orElse: () => switch (legacyPalette) {
        'ocean' => AppPrimaryColor.sky,
        'forest' => AppPrimaryColor.green,
        'violet' => AppPrimaryColor.violet,
        'amber' => AppPrimaryColor.amber,
        'terra' => AppPrimaryColor.defaultColor,
        _ => AppPrimaryColor.defaultColor,
      },
    );
    final language = await preferences.getString(_languageKey);
    locale = language == null || language == 'system' ? null : Locale(language);
    subtitleLanguage =
        await preferences.getString(subtitleLanguageKey) ?? 'eng';
    subdlApiKey = await _secretStore.read(subdlApiKeyName) ?? '';
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    notifyListeners();
    await SharedPreferencesAsync().setString(_themeKey, value.name);
  }

  Future<void> setBaseColor(AppBaseColor value) async {
    baseColor = value;
    notifyListeners();
    await SharedPreferencesAsync().setString(_baseKey, value.name);
  }

  Future<void> setPrimaryColor(AppPrimaryColor value) async {
    primaryColor = value;
    notifyListeners();
    await SharedPreferencesAsync().setString(_primaryKey, value.name);
  }

  Future<void> setLocale(Locale? value) async {
    locale = value;
    notifyListeners();
    await SharedPreferencesAsync().setString(
      _languageKey,
      value?.languageCode ?? 'system',
    );
  }

  Future<void> setSubtitleLanguage(String value) async {
    if (!subtitleLanguages.containsValue(value)) return;
    subtitleLanguage = value;
    notifyListeners();
    await SharedPreferencesAsync().setString(subtitleLanguageKey, value);
  }

  Future<void> setSubdlApiKey(String value) async {
    subdlApiKey = value.trim();
    notifyListeners();
    await _secretStore.write(
      subdlApiKeyName,
      subdlApiKey.isEmpty ? null : subdlApiKey,
    );
  }
}
