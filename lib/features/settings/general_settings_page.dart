import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../widgets/terra_header.dart';
import 'app_settings.dart';
import '../subtitles/open_subtitles.dart';

class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  late final TextEditingController _subdlKey = TextEditingController(
    text: widget.settings.subdlApiKey,
  );

  @override
  void dispose() {
    _subdlKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          const TerraHeader(title: Text('General'), nested: true),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.settings,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FSelect<String>(
                    label: const Text('Language'),
                    items: const {'System default': 'system', 'English': 'en'},
                    control: .lifted(
                      value: widget.settings.locale?.languageCode ?? 'system',
                      onChange: (value) => widget.settings.setLocale(
                        value == null || value == 'system'
                            ? null
                            : Locale(value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FSelect<ThemeMode>(
                    label: const Text('Appearance'),
                    items: const {
                      'System': ThemeMode.system,
                      'Light': ThemeMode.light,
                      'Dark': ThemeMode.dark,
                    },
                    control: .lifted(
                      value: widget.settings.themeMode,
                      onChange: (value) {
                        if (value != null) widget.settings.setThemeMode(value);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  FSelect<AppBaseColor>(
                    label: const Text('Base color'),
                    items: {
                      for (final color in AppBaseColor.values)
                        color.label: color,
                    },
                    control: .lifted(
                      value: widget.settings.baseColor,
                      onChange: (value) {
                        if (value != null) widget.settings.setBaseColor(value);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  FSelect<AppPrimaryColor>(
                    label: const Text('Primary color'),
                    items: {
                      for (final color in AppPrimaryColor.values)
                        color.label: color,
                    },
                    control: .lifted(
                      value: widget.settings.primaryColor,
                      onChange: (value) {
                        if (value != null) {
                          widget.settings.setPrimaryColor(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  FSelect<String>(
                    label: const Text('Online subtitle language'),
                    items: subtitleLanguages,
                    control: .lifted(
                      value: widget.settings.subtitleLanguage,
                      onChange: (value) {
                        if (value != null) {
                          widget.settings.setSubtitleLanguage(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FTextField(
                          control: FTextFieldControl.managed(
                            controller: _subdlKey,
                          ),
                          label: const Text('SubDL API key'),
                          hint: 'Optional',
                          obscureText: true,
                          autocorrect: false,
                          onSubmit: (_) =>
                              widget.settings.setSubdlApiKey(_subdlKey.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox.square(
                        dimension: 44,
                        child: IconButton.filled(
                          tooltip: 'Save API key',
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              widget.settings.setSubdlApiKey(_subdlKey.text),
                          icon: const Icon(Icons.save_outlined),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
