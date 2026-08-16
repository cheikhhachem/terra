import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:terra/features/settings/app_settings.dart';

void main() {
  test('new settings select default Taupe and Red aliases', () {
    final secrets = _MemorySecrets();
    final settings = AppSettings(secretStore: secrets);
    expect(settings.baseColor, AppBaseColor.defaultColor);
    expect(settings.primaryColor, AppPrimaryColor.defaultColor);
  });

  test('appearance settings persist and reload', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final secrets = _MemorySecrets();
    final settings = AppSettings(secretStore: secrets);
    await settings.setThemeMode(ThemeMode.dark);
    await settings.setBaseColor(AppBaseColor.mist);
    await settings.setPrimaryColor(AppPrimaryColor.sky);
    await settings.setLocale(const Locale('en'));
    await settings.setSubtitleLanguage('ara');
    await settings.setSubdlApiKey('secret');

    final restored = AppSettings(secretStore: secrets);
    await restored.load();

    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.baseColor, AppBaseColor.mist);
    expect(restored.primaryColor, AppPrimaryColor.sky);
    expect(restored.locale, const Locale('en'));
    expect(restored.subtitleLanguage, 'ara');
    expect(restored.subdlApiKey, 'secret');
  });
}

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
