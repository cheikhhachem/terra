import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra/features/settings/app_settings.dart';
import 'package:terra/theme/theme.dart';

void main() {
  test('Forui base and primary choices replace complete color tokens', () {
    final terra = lightThemeFor().colors;
    final explicitTerra = lightThemeFor(
      base: AppBaseColor.taupe,
      primary: AppPrimaryColor.red,
    ).colors;
    final mistBlue = lightThemeFor(
      base: AppBaseColor.mist,
      primary: AppPrimaryColor.blue,
    ).colors;
    final darkMistBlue = darkThemeFor(
      base: AppBaseColor.mist,
      primary: AppPrimaryColor.blue,
    ).colors;

    expect(mistBlue.primary, const Color(0xFF1447E6));
    expect(darkMistBlue.primary, const Color(0xFF193CB8));
    expect(mistBlue.secondary, const Color(0xFFF1F3F3));
    expect(darkMistBlue.background, const Color(0xFF090B0C));
    expect(mistBlue.mutedForeground, const Color(0xFF67787C));
    expect(mistBlue.secondary, isNot(terra.secondary));
    expect(terra.primary, explicitTerra.primary);
    expect(terra.secondary, explicitTerra.secondary);
  });
}
