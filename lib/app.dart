import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'features/home/terra_home.dart';
import 'features/settings/app_settings.dart';
import 'theme/theme.dart';

class Application extends StatelessWidget {
  Application({super.key, AppSettings? settings})
    : settings = settings ?? AppSettings();

  final AppSettings settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final light = lightThemeFor(
        base: settings.baseColor,
        primary: settings.primaryColor,
      );
      final dark = darkThemeFor(
        base: settings.baseColor,
        primary: settings.primaryColor,
      );
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        supportedLocales: FLocalizations.supportedLocales,
        localizationsDelegates: const [
          ...FLocalizations.localizationsDelegates,
        ],
        locale: settings.locale,
        themeMode: settings.themeMode,
        theme: light.toApproximateMaterialTheme(),
        darkTheme: dark.toApproximateMaterialTheme(),
        builder: (context, child) {
          final theme = Theme.of(context);
          final surface = theme.colorScheme.surface;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
              systemNavigationBarIconBrightness:
                  theme.brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: FTheme(
              data: Theme.brightnessOf(context) == .light ? light : dark,
              child: Material(
                color: surface,
                child: FToaster(child: FTooltipGroup(child: child!)),
              ),
            ),
          );
        },
        home: TerraHome(settings: settings),
      );
    },
  );
}
