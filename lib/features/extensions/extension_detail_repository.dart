import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'sora_extension_service.dart';

typedef ExtensionDetailLoader =
    Future<(SoraDetails, List<SoraEpisode>)> Function(
      InstalledSoraModule module,
      String href,
    );

abstract interface class ExtensionDetailStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

class SharedPreferencesExtensionDetailStore implements ExtensionDetailStore {
  final _preferences = SharedPreferencesAsync();

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
}

class CachedExtensionDetails {
  const CachedExtensionDetails({
    required this.details,
    required this.episodes,
    required this.updatedAt,
  });

  final SoraDetails details;
  final List<SoraEpisode> episodes;
  final DateTime updatedAt;
}

class ExtensionDetailRepository {
  ExtensionDetailRepository({
    ExtensionService? service,
    ExtensionDetailLoader? load,
    ExtensionDetailStore? store,
    DateTime Function()? now,
  }) : _load = load ?? service!.details,
       _store = store ?? SharedPreferencesExtensionDetailStore(),
       _now = now ?? DateTime.now;

  static const _cacheKey = 'terra.extension.details.v1';
  final ExtensionDetailLoader _load;
  final ExtensionDetailStore _store;
  final DateTime Function() _now;
  Map<String, dynamic>? _records;
  Future<void>? _loading;

  Future<CachedExtensionDetails?> read(
    InstalledSoraModule module,
    String href,
  ) async {
    await _ensureLoaded();
    final value = _records![_key(module, href)];
    if (value is! Map || value['version'] != module.metadata.version) {
      return null;
    }
    try {
      final episodes = (value['episodes'] as List).indexed
          .map((item) => SoraEpisode.fromJson(item.$2, item.$1))
          .where((episode) => episode.href.isNotEmpty)
          .toList();
      return CachedExtensionDetails(
        details: SoraDetails.fromJson(value['details']),
        episodes: episodes,
        updatedAt: DateTime.parse(value['updatedAt'].toString()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<CachedExtensionDetails> refresh(
    InstalledSoraModule module,
    String href,
  ) async {
    final value = await _load(module, href);
    final cached = CachedExtensionDetails(
      details: value.$1,
      episodes: List.unmodifiable(value.$2),
      updatedAt: _now().toUtc(),
    );
    await _ensureLoaded();
    _records![_key(module, href)] = {
      'version': module.metadata.version,
      'updatedAt': cached.updatedAt.toIso8601String(),
      'details': cached.details.toJson(),
      'episodes': cached.episodes.map((episode) => episode.toJson()).toList(),
    };
    if (_records!.length > 100) {
      final oldest = _records!.entries.reduce((a, b) {
        final aTime = DateTime.tryParse(a.value['updatedAt']?.toString() ?? '');
        final bTime = DateTime.tryParse(b.value['updatedAt']?.toString() ?? '');
        return (aTime ?? DateTime.fromMillisecondsSinceEpoch(0)).isBefore(
              bTime ?? DateTime.fromMillisecondsSinceEpoch(0),
            )
            ? a
            : b;
      });
      _records!.remove(oldest.key);
    }
    await _store.setString(_cacheKey, jsonEncode(_records));
    return cached;
  }

  Future<void> _ensureLoaded() => _loading ??= _loadRecords();

  Future<void> _loadRecords() async {
    try {
      final stored = await _store.getString(_cacheKey);
      final decoded = stored == null ? null : jsonDecode(stored);
      _records = decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
    } catch (_) {
      _records = <String, dynamic>{};
    }
  }

  String _key(InstalledSoraModule module, String href) =>
      base64Url.encode(utf8.encode('${module.id}\u0000$href'));
}
