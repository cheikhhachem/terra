import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.cheikhhachem.terra/downloads');

Future<void> updateDownloadForegroundService(bool active) async {
  if (!Platform.isAndroid) return;
  await _channel.invokeMethod<void>(active ? 'start' : 'stop');
}
