import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'features/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(Application(settings: settings));
}
