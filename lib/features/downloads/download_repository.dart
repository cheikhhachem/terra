import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_models.dart';
import 'download_foreground_service.dart';

abstract interface class DownloadStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

class SharedPreferencesDownloadStore implements DownloadStore {
  SharedPreferencesDownloadStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
}

typedef DownloadDirectory = Future<Directory> Function();
typedef DownloadWifiCheck = Future<bool> Function();
typedef DownloadActivityCallback = Future<void> Function(bool active);

class DownloadRepository extends ChangeNotifier {
  DownloadRepository({
    DownloadStore? store,
    DownloadDirectory? directory,
    DownloadWifiCheck? wifiCheck,
    Stream<void>? networkChanges,
    DownloadActivityCallback? onActivity,
  }) : _store = store ?? SharedPreferencesDownloadStore(),
       _directory = directory ?? getApplicationSupportDirectory,
       _wifiCheck = wifiCheck ?? _hasWifi,
       _networkChanges =
           networkChanges ?? Connectivity().onConnectivityChanged.map((_) {}),
       _onActivity = onActivity ?? updateDownloadForegroundService;

  static const registryKey = 'terra.downloads.v1';
  static const settingsKey = 'terra.download.settings.v1';
  final DownloadStore _store;
  final DownloadDirectory _directory;
  final DownloadWifiCheck _wifiCheck;
  final Stream<void> _networkChanges;
  final DownloadActivityCallback _onActivity;
  final List<DownloadEntry> _entries = [];
  final Set<String> _cancelled = {};
  final List<String> _queue = [];
  final Map<String, Completer<void>> _completion = {};
  StreamSubscription<void>? _networkSubscription;
  int _active = 0;
  bool _pumping = false;
  int maxConcurrentDownloads = 2;
  bool wifiOnly = false;
  bool initialized = false;

  List<DownloadEntry> get entries => List.unmodifiable(_entries);
  int get completedBytes => _entries
      .where((entry) => entry.status == DownloadStatus.completed)
      .fold(0, (total, entry) => total + entry.receivedBytes);

  Future<void> initialize() async {
    if (initialized) return;
    try {
      final decoded = jsonDecode(await _store.getString(registryKey) ?? '[]');
      if (decoded is List) {
        for (final value in decoded) {
          final entry = DownloadEntry.tryFromJson(value);
          if (entry == null) continue;
          _entries.add(
            entry.status == DownloadStatus.downloading
                ? entry.copyWith(
                    status: DownloadStatus.queued,
                    error: 'Waiting to resume.',
                  )
                : entry,
          );
        }
      }
      _sort();
    } on FormatException {
      _entries.clear();
    }
    try {
      final settings = jsonDecode(await _store.getString(settingsKey) ?? '{}');
      if (settings is Map) {
        maxConcurrentDownloads =
            (settings['maxConcurrentDownloads'] as num?)?.toInt().clamp(1, 5) ??
            2;
        wifiOnly = settings['wifiOnly'] == true;
      }
    } on FormatException {
      // Keep defaults when persisted settings are malformed.
    }
    _queue.addAll(
      _entries
          .where((entry) => entry.status == DownloadStatus.queued)
          .map((entry) => entry.id),
    );
    _networkSubscription = _networkChanges.listen((_) => _pump());
    initialized = true;
    notifyListeners();
    await _save();
    for (final entry in _entries.where(
      (entry) =>
          entry.status == DownloadStatus.completed && entry.posterPath.isEmpty,
    )) {
      await _cachePoster(entry);
    }
    _pump();
  }

  bool contains(String id) => _entries.any(
    (entry) => entry.id == id && entry.status != DownloadStatus.cancelled,
  );

  Future<void> add(DownloadRequest request) async {
    if (contains(request.id)) {
      throw StateError('This episode is already saved.');
    }
    _entries.removeWhere(
      (entry) =>
          entry.id == request.id && entry.status == DownloadStatus.cancelled,
    );
    final entry = DownloadEntry(
      id: request.id,
      mediaId: request.mediaId,
      title: request.title,
      episodeLabel: request.episodeLabel,
      imageUrl: request.imageUrl,
      sourceName: request.sourceName,
      sourceIconUrl: request.sourceIconUrl,
      sourceType: request.sourceType,
      qualityLabel: request.qualityLabel,
      url: request.url,
      headers: request.headers,
      localPath: '',
      status: DownloadStatus.queued,
      createdAt: DateTime.now(),
      season: request.season,
      episodeNumber: request.episodeNumber,
    );
    _entries.add(entry);
    _sort();
    notifyListeners();
    await _save();
    await _cachePoster(entry);
    final completion = _completion[entry.id] = Completer<void>();
    _queue.add(entry.id);
    _pump();
    await completion.future;
  }

  Future<void> retry(DownloadEntry entry) async {
    await delete(entry, removeRecord: false);
    _replace(
      entry.copyWith(
        localPath: '',
        status: DownloadStatus.queued,
        progress: 0,
        receivedBytes: 0,
        clearError: true,
      ),
    );
    await _save();
    final completion = _completion[entry.id] = Completer<void>();
    _queue.add(entry.id);
    _pump();
    await completion.future;
  }

  Future<void> cancel(String id) async {
    _cancelled.add(id);
    _queue.remove(id);
    final entry = _entry(id);
    if (entry != null) {
      _replace(entry.copyWith(status: DownloadStatus.cancelled));
      notifyListeners();
      await _save();
    }
    _complete(id);
  }

  Future<void> delete(DownloadEntry entry, {bool removeRecord = true}) async {
    _cancelled.add(entry.id);
    _queue.remove(entry.id);
    if (entry.localPath.isNotEmpty) {
      final file = File(entry.localPath);
      if (await file.exists()) await file.delete();
    }
    final partial = await _fileFor(entry, partial: true);
    if (await partial.exists()) await partial.delete();
    if (removeRecord) _entries.removeWhere((item) => item.id == entry.id);
    if (removeRecord &&
        entry.posterPath.isNotEmpty &&
        !_entries.any((item) => item.mediaId == entry.mediaId)) {
      final poster = File(entry.posterPath);
      if (await poster.exists()) await poster.delete();
    }
    notifyListeners();
    await _save();
    _complete(entry.id);
  }

  Future<void> deleteAll(Iterable<DownloadEntry> entries) async {
    for (final entry in entries.toList()) {
      await delete(entry);
    }
  }

  Future<void> clearAll() => deleteAll(_entries);

  Future<void> setMaxConcurrentDownloads(int value) async {
    maxConcurrentDownloads = value.clamp(1, 5);
    notifyListeners();
    await _saveSettings();
    _pump();
  }

  Future<void> setWifiOnly(bool value) async {
    wifiOnly = value;
    notifyListeners();
    await _saveSettings();
    _pump();
  }

  Future<void> _pump() async {
    if (_pumping || _active >= maxConcurrentDownloads || _queue.isEmpty) return;
    _pumping = true;
    try {
      if (wifiOnly && !await _wifiCheck()) return;
      while (_active < maxConcurrentDownloads && _queue.isNotEmpty) {
        final id = _queue.removeAt(0);
        final entry = _entry(id);
        if (entry == null || entry.status != DownloadStatus.queued) continue;
        _active++;
        if (_active == 1) await _setActivity(true);
        _replace(
          entry.copyWith(status: DownloadStatus.downloading, clearError: true),
        );
        notifyListeners();
        unawaited(
          _download(_entry(id)!).whenComplete(() {
            _active--;
            if (_active == 0) _setActivity(false);
            _complete(id);
            _pump();
          }),
        );
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _setActivity(bool active) async {
    try {
      await _onActivity(active);
    } on PlatformException {
      // Downloading still works if the platform service is unavailable.
    }
  }

  Future<void> _download(DownloadEntry entry) async {
    _cancelled.remove(entry.id);
    try {
      final uri = Uri.parse(entry.url);
      if (!['http', 'https'].contains(uri.scheme)) {
        throw const FormatException('Only HTTP downloads are supported.');
      }
      final hls = uri.path.toLowerCase().endsWith('.m3u8');
      final partial = await _fileFor(entry, partial: true);
      await partial.parent.create(recursive: true);
      var extension = _extension(entry.url);
      if (hls) {
        extension = await _downloadHls(entry, uri, partial) ? 'mp4' : 'ts';
      } else {
        await _downloadFile(entry, uri, partial);
      }
      _checkCancelled(entry.id);
      final completed = await _fileFor(entry, extension: extension);
      await partial.rename(completed.path);
      final size = await completed.length();
      _replace(
        _entry(entry.id)!.copyWith(
          localPath: completed.path,
          status: DownloadStatus.completed,
          progress: 1,
          receivedBytes: size,
          totalBytes: size,
          clearError: true,
        ),
      );
    } catch (error) {
      final current = _entry(entry.id);
      if (current != null && current.status != DownloadStatus.cancelled) {
        _replace(
          current.copyWith(
            status: DownloadStatus.failed,
            error: error.toString().replaceFirst(
              RegExp(r'^(Bad state|FormatException):\s*'),
              '',
            ),
          ),
        );
      }
    } finally {
      _cancelled.remove(entry.id);
      notifyListeners();
      await _save();
    }
  }

  Future<void> _cachePoster(DownloadEntry entry) async {
    if (entry.imageUrl.isEmpty) return;
    final uri = Uri.tryParse(entry.imageUrl);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    final directory = Directory(
      '${(await _directory()).path}/downloads/posters',
    );
    final file = File('${directory.path}/${_safeId(entry.mediaId)}.img');
    if (await file.exists()) {
      _replace(entry.copyWith(posterPath: file.path));
      notifyListeners();
      await _save();
      return;
    }
    final client = HttpClient();
    IOSink? sink;
    try {
      final response = await _get(client, uri, entry.headers);
      await directory.create(recursive: true);
      sink = file.openWrite();
      await response.pipe(sink);
      sink = null;
      final current = _entry(entry.id);
      if (current != null) {
        _replace(current.copyWith(posterPath: file.path));
        notifyListeners();
        await _save();
      }
    } catch (_) {
      if (await file.exists()) await file.delete();
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<void> _downloadFile(DownloadEntry entry, Uri uri, File target) async {
    final client = HttpClient();
    IOSink? sink;
    try {
      final response = await _get(client, uri, entry.headers);
      sink = target.openWrite();
      var received = 0;
      await for (final chunk in response) {
        _checkCancelled(entry.id);
        sink.add(chunk);
        received += chunk.length;
        _progress(entry.id, received, response.contentLength);
      }
      await sink.flush();
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<bool> _downloadHls(DownloadEntry entry, Uri uri, File target) async {
    final client = HttpClient();
    IOSink? sink;
    try {
      var playlistUri = uri;
      var playlist = await _text(client, playlistUri, entry.headers);
      final variant = _highestBandwidthVariant(playlist, playlistUri);
      if (variant != null) {
        playlistUri = variant;
        playlist = await _text(client, playlistUri, entry.headers);
      }
      final parsed = _parseMediaPlaylist(playlist, playlistUri);
      final segments = parsed.segments;
      if (segments.isEmpty) {
        throw const FormatException('HLS playlist has no segments.');
      }
      sink = target.openWrite();
      var received = 0;
      String? writtenMap;
      for (var index = 0; index < segments.length; index++) {
        _checkCancelled(entry.id);
        final segment = segments[index];
        if (segment.map != null && segment.map!.identity != writtenMap) {
          var bytes = await _bytes(
            client,
            segment.map!.uri,
            entry.headers,
            range: segment.map!.range,
          );
          if (segment.map!.key != null) {
            final key = await _bytes(client, segment.map!.key!, entry.headers);
            final iv = segment.map!.iv;
            if (key.length != 16 || iv == null) {
              throw const FormatException(
                'Encrypted HLS initialization maps require a 16-byte key and explicit IV.',
              );
            }
            bytes = _decryptAes128(bytes, key, iv);
          }
          sink.add(bytes);
          received += bytes.length;
          writtenMap = segment.map!.identity;
        }
        var bytes = await _bytes(
          client,
          segment.uri,
          entry.headers,
          range: segment.range,
        );
        if (segment.key != null) {
          final key = await _bytes(client, segment.key!, entry.headers);
          if (key.length != 16) {
            throw const FormatException('HLS AES-128 key must be 16 bytes.');
          }
          bytes = _decryptAes128(
            bytes,
            key,
            segment.iv ?? _sequenceIv(segment.sequence),
          );
        }
        sink.add(bytes);
        received += bytes.length;
        _progress(entry.id, received, null, (index + 1) / segments.length);
      }
      await sink.flush();
      return segments.any((segment) => segment.map != null);
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Uri? _highestBandwidthVariant(String playlist, Uri base) {
    final lines = playlist.split('\n');
    (int, Uri)? selected;
    for (var index = 0; index < lines.length - 1; index++) {
      final line = lines[index].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final bandwidth =
          int.tryParse(
            RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '',
          ) ??
          0;
      final path = lines[index + 1].trim();
      if (path.isEmpty || path.startsWith('#')) continue;
      if (selected == null || bandwidth > selected.$1) {
        selected = (bandwidth, base.resolve(path));
      }
    }
    return selected?.$2;
  }

  Future<HttpClientResponse> _get(
    HttpClient client,
    Uri uri,
    Map<String, String> headers, {
    String? range,
  }) async {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    if (range != null) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$range');
    }
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return response;
  }

  Future<String> _text(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
  ) async => utf8.decode(
    await (await _get(
      client,
      uri,
      headers,
    )).fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk)),
  );

  Future<Uint8List> _bytes(
    HttpClient client,
    Uri uri,
    Map<String, String> headers, {
    String? range,
  }) async => Uint8List.fromList(
    await (await _get(
      client,
      uri,
      headers,
      range: range,
    )).fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk)),
  );

  void _progress(String id, int received, int? total, [double? progress]) {
    final current = _entry(id);
    if (current == null) return;
    final value =
        progress ?? (total != null && total > 0 ? received / total : 0);
    _replace(
      current.copyWith(
        receivedBytes: received,
        totalBytes: total,
        progress: value.clamp(0, 1),
      ),
    );
    notifyListeners();
  }

  void _checkCancelled(String id) {
    if (_cancelled.contains(id)) throw StateError('Download cancelled.');
  }

  Future<File> _fileFor(
    DownloadEntry entry, {
    bool partial = false,
    String? extension,
  }) async {
    final directory = Directory('${(await _directory()).path}/downloads');
    final ext = extension ?? _extension(entry.url);
    return File(
      '${directory.path}/${_safeId(entry.id)}.$ext${partial ? '.part' : ''}',
    );
  }

  String _extension(String url) {
    final segment = Uri.tryParse(url)?.pathSegments.lastOrNull;
    final value = segment?.split('.').last.toLowerCase();
    return value != null && RegExp(r'^[a-z0-9]{2,5}$').hasMatch(value)
        ? value
        : 'mp4';
  }

  String _safeId(String id) =>
      base64Url.encode(utf8.encode(id)).replaceAll('=', '');

  DownloadEntry? _entry(String id) => _entries
      .cast<DownloadEntry?>()
      .firstWhere((entry) => entry?.id == id, orElse: () => null);

  void _replace(DownloadEntry entry) {
    final index = _entries.indexWhere((item) => item.id == entry.id);
    if (index >= 0) _entries[index] = entry;
  }

  void _sort() => _entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> _save() => _store.setString(
    registryKey,
    jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
  );

  Future<void> _saveSettings() => _store.setString(
    settingsKey,
    jsonEncode({
      'maxConcurrentDownloads': maxConcurrentDownloads,
      'wifiOnly': wifiOnly,
    }),
  );

  void _complete(String id) {
    final completion = _completion.remove(id);
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    if (_active == 0) _setActivity(false);
    super.dispose();
  }
}

Future<bool> _hasWifi() async {
  final values = await Connectivity().checkConnectivity();
  return values.contains(ConnectivityResult.wifi) ||
      values.contains(ConnectivityResult.ethernet);
}

class _HlsPlaylist {
  const _HlsPlaylist(this.segments);
  final List<_HlsSegment> segments;
}

class _HlsSegment {
  const _HlsSegment({
    required this.uri,
    required this.sequence,
    this.range,
    this.key,
    this.iv,
    this.map,
  });

  final Uri uri;
  final int sequence;
  final String? range;
  final Uri? key;
  final Uint8List? iv;
  final _HlsMap? map;
}

class _HlsMap {
  const _HlsMap({required this.uri, this.range, this.key, this.iv});
  final Uri uri;
  final String? range;
  final Uri? key;
  final Uint8List? iv;

  String get identity =>
      '$uri|$range|$key|${iv == null ? '' : base64Encode(iv!)}';
}

_HlsPlaylist _parseMediaPlaylist(String playlist, Uri base) {
  final lines = playlist.split('\n').map((line) => line.trim()).toList();
  var sequence =
      int.tryParse(
        lines
                .cast<String?>()
                .firstWhere(
                  (line) => line?.startsWith('#EXT-X-MEDIA-SEQUENCE:') == true,
                  orElse: () => null,
                )
                ?.split(':')
                .last ??
            '',
      ) ??
      0;
  Uri? key;
  Uint8List? iv;
  _HlsMap? map;
  String? range;
  int? previousRangeEnd;
  final segments = <_HlsSegment>[];
  for (final line in lines) {
    if (line.startsWith('#EXT-X-KEY:')) {
      final attributes = _attributes(line.substring(line.indexOf(':') + 1));
      final method = attributes['METHOD'];
      if (method == 'NONE') {
        key = null;
        iv = null;
      } else if (method == 'AES-128') {
        final keyUri = attributes['URI'];
        if (keyUri == null) {
          throw const FormatException('HLS AES-128 key URI is missing.');
        }
        key = base.resolve(keyUri);
        iv = _parseIv(attributes['IV']);
      } else {
        throw FormatException('Unsupported HLS encryption method: $method.');
      }
    } else if (line.startsWith('#EXT-X-MAP:')) {
      final attributes = _attributes(line.substring(line.indexOf(':') + 1));
      final mapUri = attributes['URI'];
      if (mapUri == null) {
        throw const FormatException('HLS initialization map URI is missing.');
      }
      map = _HlsMap(
        uri: base.resolve(mapUri),
        range: _normalizeRange(attributes['BYTERANGE'], null),
        key: key,
        iv: iv,
      );
    } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
      final raw = line.substring(line.indexOf(':') + 1);
      range = _normalizeRange(raw, previousRangeEnd);
      if (range != null) {
        previousRangeEnd = int.parse(range.split('-').last) + 1;
      }
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      segments.add(
        _HlsSegment(
          uri: base.resolve(line),
          sequence: sequence++,
          range: range,
          key: key,
          iv: iv,
          map: map,
        ),
      );
      range = null;
    }
  }
  return _HlsPlaylist(segments);
}

Map<String, String> _attributes(String input) {
  final values = <String, String>{};
  for (final match in RegExp(
    r'([A-Z0-9-]+)=("[^"]*"|[^,]*)',
  ).allMatches(input)) {
    final value = match.group(2)!;
    values[match.group(1)!] = value.startsWith('"')
        ? value.substring(1, value.length - 1)
        : value;
  }
  return values;
}

String? _normalizeRange(String? value, int? defaultStart) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split('@');
  final length = int.tryParse(parts.first);
  final start = parts.length > 1 ? int.tryParse(parts[1]) : defaultStart;
  if (length == null || start == null || length <= 0 || start < 0) {
    throw const FormatException('Invalid HLS byte range.');
  }
  return '$start-${start + length - 1}';
}

Uint8List? _parseIv(String? value) {
  if (value == null || value.isEmpty) return null;
  final hex = value.replaceFirst(RegExp(r'^0[xX]'), '').padLeft(32, '0');
  if (hex.length != 32) throw const FormatException('HLS IV must be 16 bytes.');
  return Uint8List.fromList([
    for (var index = 0; index < hex.length; index += 2)
      int.parse(hex.substring(index, index + 2), radix: 16),
  ]);
}

Uint8List _sequenceIv(int sequence) {
  final iv = Uint8List(16);
  var value = sequence;
  for (var index = 15; index >= 0 && value > 0; index--) {
    iv[index] = value & 0xff;
    value >>= 8;
  }
  return iv;
}

Uint8List _decryptAes128(Uint8List input, Uint8List key, Uint8List iv) {
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        false,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV(KeyParameter(key), iv),
          null,
        ),
      );
  return cipher.process(input);
}
