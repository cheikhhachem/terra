// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'extension_facets.dart';
import 'sora_network.dart';

typedef ExtensionDownload = Future<String> Function(String url, String label);
typedef ExtensionDirectory = Future<Directory> Function();

abstract interface class ExtensionStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

class SharedPreferencesExtensionStore implements ExtensionStore {
  SharedPreferencesExtensionStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _preferences.setString(key, value);
  }
}

class ExtensionManager extends ChangeNotifier {
  ExtensionManager({
    ExtensionStore? store,
    ExtensionDownload? download,
    ExtensionDirectory? directory,
  }) : _store = store,
       _downloadOverride = download,
       _directory = directory ?? getApplicationSupportDirectory;

  static const _legacyRegistryKey = 'sora.modules.v1';
  static const _sourcesKey = 'sora.sources.v2';
  static const _installedKey = 'sora.installed.v2';
  ExtensionStore? _store;
  final ExtensionDownload? _downloadOverride;
  final ExtensionDirectory _directory;
  final List<KnownSoraSource> _sources = [];
  final List<InstalledSoraModule> _installed = [];
  bool initialized = false;
  String? initializationError;

  List<KnownSoraSource> get knownSources => List.unmodifiable(_sources);
  List<InstalledSoraModule> get installed => List.unmodifiable(_installed);
  List<InstalledSoraModule> get activeInstalled =>
      List.unmodifiable(_installed.where((module) => module.active));
  List<InstalledSoraModule> get activeWatchInstalled => List.unmodifiable(
    _installed.where(
      (module) =>
          module.active &&
          extensionMediaModes(
            module.metadata.type,
            novel: module.metadata.novel,
          ).contains(ExtensionMediaMode.watch),
    ),
  );
  List<InstalledSoraModule> get activeReadInstalled => List.unmodifiable(
    _installed.where(
      (module) =>
          module.active &&
          extensionMediaModes(
            module.metadata.type,
            novel: module.metadata.novel,
          ).contains(ExtensionMediaMode.read),
    ),
  );
  List<InstalledSoraModule> get modules => installed;

  InstalledSoraModule? installationFor(KnownSoraSource source) => _installed
      .cast<InstalledSoraModule?>()
      .firstWhere((item) => item?.id == source.id, orElse: () => null);

  Future<void> initialize() async {
    try {
      _store ??= SharedPreferencesExtensionStore();
      final sourcesRegistry = await _store!.getString(_sourcesKey);
      final installedRegistry = await _store!.getString(_installedKey);
      if (sourcesRegistry != null) {
        _sources.addAll(
          (jsonDecode(sourcesRegistry) as List).map(
            (value) => KnownSoraSource.fromJson(value as Map),
          ),
        );
        if (installedRegistry != null)
          _installed.addAll(
            (jsonDecode(installedRegistry) as List).map(
              (value) => InstalledSoraModule.fromJson(value as Map),
            ),
          );
      } else {
        await _migrateLegacyRegistry();
      }
    } catch (error) {
      initializationError = 'Could not load modules: $error';
    } finally {
      initialized = true;
      notifyListeners();
    }
  }

  Future<void> _migrateLegacyRegistry() async {
    final registry = await _store!.getString(_legacyRegistryKey);
    if (registry == null) return;
    final modules = (jsonDecode(registry) as List)
        .map((value) => InstalledSoraModule.fromJson(value as Map))
        .toList();
    _installed.addAll(modules);
    _sources.addAll(
      modules.map(
        (module) => KnownSoraSource(
          id: module.id,
          metadata: module.metadata,
          metadataUrl: module.metadataUrl,
        ),
      ),
    );
    await _save();
  }

  Future<KnownSoraSource> addSource(String metadataUrl) async {
    final uri = Uri.tryParse(metadataUrl.trim());
    if (uri == null || !uri.hasScheme)
      throw const FormatException('Enter a valid metadata URL.');
    final downloaded = await _download(uri.toString(), 'manifest');
    final decoded = jsonDecode(downloaded);
    if (decoded is List) return _addMangayomiRepository(uri, decoded);
    if (_sources.any((source) => source.metadataUrl == uri.toString()))
      throw StateError('This metadata URL is already added.');
    final metadata = _resolveScriptUrl(SoraMetadata.parse(downloaded), uri);
    _checkDuplicate(metadata);
    final source = KnownSoraSource(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      metadata: metadata,
      metadataUrl: uri.toString(),
    );
    _sources.add(source);
    await _save();
    notifyListeners();
    return source;
  }

  Future<KnownSoraSource> _addMangayomiRepository(
    Uri repository,
    List<dynamic> entries,
  ) async {
    if (_sources.any((source) => source.metadataUrl == repository.toString()))
      throw StateError('This repository is already added.');
    final sources = <KnownSoraSource>[];
    for (final entry in entries) {
      if (entry is! Map || !_isSupportedMangayomiEntry(entry)) continue;
      final source = _mangayomiSource(entry, repository);
      if (source != null) sources.add(source);
    }
    if (sources.isEmpty)
      throw const FormatException(
        'No supported Mangayomi JavaScript sources were found.',
      );
    _sources.addAll(sources);
    await _save();
    notifyListeners();
    return sources.first;
  }

  String _repositorySourceId(Uri repository, String catalogId) =>
      '${base64Url.encode(utf8.encode(repository.toString())).replaceAll('=', '')}#$catalogId';

  Future<InstalledSoraModule> install(KnownSoraSource source) async {
    if (installationFor(source) != null)
      throw StateError('${source.metadata.sourceName} is already installed.');
    final script = await _download(source.metadata.scriptUrl, 'script');
    return _writeInstallation(source, script);
  }

  Future<InstalledSoraModule> _writeInstallation(
    KnownSoraSource source,
    String script,
  ) async {
    if (script.trim().isEmpty)
      throw const FormatException('Extension script is empty.');
    final directory = Directory('${(await _directory()).path}/sora_extensions');
    await directory.create(recursive: true);
    final file = File('${directory.path}/${source.id}.js');
    await file.writeAsString(script, flush: true);
    final module = InstalledSoraModule(
      id: source.id,
      metadata: source.metadata,
      scriptPath: file.path,
      metadataUrl: source.metadataUrl,
    );
    _installed.add(module);
    await _save();
    notifyListeners();
    return module;
  }

  Future<void> uninstall(KnownSoraSource source) async {
    final module = installationFor(source);
    if (module == null) return;
    _installed.removeWhere((item) => item.id == source.id);
    final file = File(module.scriptPath);
    if (await file.exists()) await file.delete();
    await _save();
    notifyListeners();
  }

  Future<void> remove(KnownSoraSource source) async {
    await removeSources([source]);
  }

  Future<void> removeSources(Iterable<KnownSoraSource> sources) async {
    final ids = sources.map((source) => source.id).toSet();
    for (final module
        in _installed.where((item) => ids.contains(item.id)).toList()) {
      final file = File(module.scriptPath);
      if (await file.exists()) await file.delete();
    }
    _installed.removeWhere((item) => ids.contains(item.id));
    _sources.removeWhere((item) => ids.contains(item.id));
    await _save();
    notifyListeners();
  }

  Future<void> removeAllSources() async {
    for (final source in List.of(_sources)) {
      await uninstall(source);
    }
    _sources.clear();
    await _save();
    notifyListeners();
  }

  Future<void> setActive(InstalledSoraModule module, bool active) async {
    final index = _installed.indexWhere((item) => item.id == module.id);
    if (index < 0) return;
    _installed[index] = InstalledSoraModule(
      id: module.id,
      metadata: module.metadata,
      scriptPath: module.scriptPath,
      metadataUrl: module.metadataUrl,
      active: active,
    );
    await _save();
    notifyListeners();
  }

  Future<void> refresh(KnownSoraSource source, [String? updatedUrl]) async {
    await refreshSources([source], updatedUrl);
  }

  Future<void> refreshAllSources({bool ignoreErrors = false}) async {
    final groups = <String, List<KnownSoraSource>>{};
    for (final source in _sources) {
      groups.putIfAbsent(source.metadataUrl, () => []).add(source);
    }
    for (final sources in groups.values) {
      try {
        await refreshSources(sources);
      } catch (_) {
        if (!ignoreErrors) rethrow;
      }
    }
  }

  Future<void> refreshSources(
    Iterable<KnownSoraSource> sources, [
    String? updatedUrl,
  ]) async {
    final values = sources.toList();
    if (values.isEmpty) return;
    final metadataUrl = updatedUrl?.trim() ?? values.first.metadataUrl;
    final uri = Uri.tryParse(metadataUrl);
    if (uri == null || !uri.hasScheme)
      throw StateError('Enter a valid metadata URL.');
    final downloaded = await _download(uri.toString(), 'manifest');
    final decoded = jsonDecode(downloaded);
    if (values.length > 1 && decoded is! List)
      throw const FormatException(
        'A repository source must contain a list of plugins.',
      );
    var changed = false;
    for (final source in values) {
      final metadata = decoded is List
          ? _mangayomiMetadataFor(source, decoded, uri)
          : _resolveScriptUrl(SoraMetadata.parse(downloaded), uri);
      final sourceIndex = _sources.indexWhere((item) => item.id == source.id);
      final metadataChanged = !_sameMetadata(source.metadata, metadata);
      final urlChanged = source.metadataUrl != uri.toString();
      if (!metadataChanged && !urlChanged) continue;
      _sources[sourceIndex] = KnownSoraSource(
        id: source.id,
        metadata: metadata,
        metadataUrl: uri.toString(),
      );
      changed = true;
      final installedIndex = _installed.indexWhere(
        (item) => item.id == source.id,
      );
      if (installedIndex >= 0) {
        final current = _installed[installedIndex];
        if (metadataChanged)
          await File(current.scriptPath).writeAsString(
            await _download(metadata.scriptUrl, 'script'),
            flush: true,
          );
        _installed[installedIndex] = InstalledSoraModule(
          id: current.id,
          metadata: metadata,
          scriptPath: current.scriptPath,
          metadataUrl: uri.toString(),
          active: current.active,
        );
      }
    }
    if (decoded is List) {
      final existingCatalogIds = values
          .map((source) => source.id.substring(source.id.lastIndexOf('#') + 1))
          .toSet();
      for (final entry in decoded) {
        if (entry is! Map || !_isSupportedMangayomiEntry(entry)) continue;
        if (existingCatalogIds.contains(entry['id']?.toString())) continue;
        final source = _mangayomiSource(entry, uri);
        if (source != null && !_sources.any((item) => item.id == source.id)) {
          _sources.add(source);
          changed = true;
        }
      }
    }
    if (!changed) return;
    await _save();
    notifyListeners();
  }

  bool _sameMetadata(SoraMetadata a, SoraMetadata b) =>
      _canonicalJson(a.toJson()) == _canonicalJson(b.toJson());

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
    }
    if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
    return jsonEncode(value);
  }

  SoraMetadata _mangayomiMetadataFor(
    KnownSoraSource source,
    List<dynamic> entries,
    Uri repository,
  ) {
    final catalogId = source.id.substring(source.id.lastIndexOf('#') + 1);
    Map? entry;
    for (final item in entries) {
      if (item is Map && item['id']?.toString() == catalogId) {
        entry = item;
        break;
      }
    }
    if (entry == null)
      throw StateError(
        '${source.metadata.sourceName} is no longer in this repository.',
      );
    return _resolveScriptUrl(SoraMetadata.fromMangayomi(entry), repository);
  }

  bool _isSupportedMangayomiEntry(Map entry) {
    final script = entry['sourceCodeUrl']?.toString().toLowerCase() ?? '';
    final language = entry['sourceCodeLanguage']?.toString().toLowerCase();
    if (language == null || language.isEmpty) return script.endsWith('.js');
    return language == '1' || language == 'javascript' || language == 'js';
  }

  KnownSoraSource? _mangayomiSource(Map entry, Uri repository) {
    final catalogId = entry['id']?.toString();
    if (catalogId == null || catalogId.isEmpty) return null;
    return KnownSoraSource(
      id: _repositorySourceId(repository, catalogId),
      metadata: _resolveScriptUrl(
        SoraMetadata.fromMangayomi(entry),
        repository,
      ),
      metadataUrl: repository.toString(),
    );
  }

  Future<void> repair(InstalledSoraModule module) async {
    if (await File(module.scriptPath).exists()) return;
    if (module.metadata.scriptUrl.isEmpty)
      throw StateError('No remote script URL is available for repair.');
    await File(module.scriptPath).parent.create(recursive: true);
    await File(module.scriptPath).writeAsString(
      await _download(module.metadata.scriptUrl, 'script'),
      flush: true,
    );
  }

  Future<String> readScript(InstalledSoraModule module) async {
    await repair(module);
    return File(module.scriptPath).readAsString();
  }

  void _checkDuplicate(SoraMetadata metadata) {
    if (_sources.any(
      (source) =>
          source.metadata.sourceName.toLowerCase() ==
              metadata.sourceName.toLowerCase() ||
          source.metadata.scriptUrl == metadata.scriptUrl,
    ))
      throw StateError('${metadata.sourceName} is already added.');
  }

  Future<void> _save() async {
    await _store!.setString(
      _sourcesKey,
      jsonEncode(_sources.map((source) => source.toJson()).toList()),
    );
    await _store!.setString(
      _installedKey,
      jsonEncode(_installed.map((module) => module.toJson()).toList()),
    );
  }

  SoraMetadata _resolveScriptUrl(SoraMetadata metadata, Uri manifestUri) {
    final script = manifestUri.resolve(metadata.scriptUrl).toString();
    if (script == metadata.scriptUrl) return metadata;
    final json = metadata.toJson()..['scriptUrl'] = script;
    return SoraMetadata.fromJson(json);
  }

  Future<String> _download(String url, String label) async {
    if (_downloadOverride != null) return _downloadOverride(url, label);
    final response = await soraRequest(url);
    if (response.status < 200 || response.status >= 300)
      throw HttpException(
        'Could not download extension $label (HTTP ${response.status}).',
      );
    return response.body;
  }
}
