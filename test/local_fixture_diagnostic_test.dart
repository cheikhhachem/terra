import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra/features/extensions/models.dart';
import 'package:terra/features/extensions/sora_runtime.dart';

void main() {
  final root = Platform.environment['SORA_FIXTURES'];
  final enabled = root != null && Directory(root).existsSync();

  test(
    'all local fixtures parse and load in QuickJS',
    () async {
      var loaded = 0;
      for (final directory in Directory(
        root!,
      ).listSync().whereType<Directory>()) {
        final name = directory.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last;
        final manifest = File('${directory.path}/$name.json');
        final script = File('${directory.path}/$name.js');
        if (!manifest.existsSync() || !script.existsSync()) continue;
        loaded++;
        final metadata = SoraMetadata.parse(await manifest.readAsString());
        expect(metadata.sourceName, isNotEmpty);
        final result = await SoraRuntime(timeout: const Duration(seconds: 3))
            .invoke(
              '${await script.readAsString()}\nasync function __diagnostic() { return "ok"; }',
              '__diagnostic',
              const [],
            );
        expect(result, 'ok', reason: name);
      }
      expect(loaded, 8);
    },
    skip: enabled
        ? false
        : 'Set SORA_FIXTURES to run local fixture diagnostics.',
  );

  test(
    'live IMDb.su search returns results',
    () async {
      final script = File('$root/imdb-su/imdb-su.js');
      final result = await SoraRuntime().invoke(
        await script.readAsString(),
        'searchResults',
        const ['Matrix'],
      );
      expect(soraList(result), isNotEmpty);
    },
    skip: enabled ? false : 'Set SORA_FIXTURES to run the live diagnostic.',
  );
}
