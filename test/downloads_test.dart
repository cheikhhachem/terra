import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:terra/features/downloads/download_models.dart';
import 'package:terra/features/downloads/download_repository.dart';

void main() {
  test('downloads direct files and HLS playlists', () async {
    final directory = await Directory.systemTemp.createTemp('terra_downloads_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      switch (request.uri.path) {
        case '/video.mp4':
          request.response
            ..contentLength = 5
            ..add([1, 2, 3, 4, 5]);
        case '/poster.jpg':
          request.response.add([0xff, 0xd8, 0xff, 0xd9]);
        case '/playlist.m3u8':
          request.response.write(
            '#EXTM3U\n#EXTINF:1,\nsegment-1.ts\n#EXTINF:1,\nsegment-2.ts\n',
          );
        case '/segment-1.ts':
          request.response.add([1, 2]);
        case '/segment-2.ts':
          request.response.add([3, 4]);
        case '/encrypted.m3u8':
          request.response.write(
            '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:7\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:1,\nencrypted.ts\n',
          );
        case '/key.bin':
          request.response.add(List<int>.generate(16, (index) => index));
        case '/encrypted.ts':
          request.response.add(
            _encrypt(
              [9, 8, 7, 6],
              List<int>.generate(16, (index) => index),
              [...List<int>.filled(15, 0), 7],
            ),
          );
        case '/fragmented.m3u8':
          request.response.write(
            '#EXTM3U\n#EXT-X-MAP:URI="fragments.mp4",BYTERANGE="4@0"\n#EXT-X-BYTERANGE:3@4\nfragments.mp4\n#EXT-X-BYTERANGE:3\nfragments.mp4\n',
          );
        case '/fragments.mp4':
          final range = request.headers.value(HttpHeaders.rangeHeader);
          final values = List<int>.generate(10, (index) => index);
          if (range != null) {
            final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
            request.response
              ..statusCode = HttpStatus.partialContent
              ..add(
                values.sublist(
                  int.parse(match.group(1)!),
                  int.parse(match.group(2)!) + 1,
                ),
              );
          } else {
            request.response.add(values);
          }
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final store = _MemoryDownloadStore();
    final repository = DownloadRepository(
      store: store,
      directory: () async => directory,
      wifiCheck: () async => true,
      networkChanges: const Stream.empty(),
      onActivity: (_) async {},
    );
    await repository.initialize();
    final base = 'http://${server.address.host}:${server.port}';

    await repository.add(_request('direct', '$base/video.mp4'));
    await repository.add(_request('hls', '$base/playlist.m3u8'));
    await repository.add(_request('encrypted', '$base/encrypted.m3u8'));
    await repository.add(_request('fragmented', '$base/fragmented.m3u8'));

    expect(
      repository.entries.map((entry) => entry.status),
      everyElement(DownloadStatus.completed),
    );
    expect(repository.entries.map((entry) => entry.mediaId).toSet(), {'media'});
    expect(repository.completedBytes, 23);
    expect(
      repository.entries.map((entry) => entry.posterPath),
      everyElement(isNotEmpty),
    );
    expect(await File(repository.entries.first.posterPath).readAsBytes(), [
      0xff,
      0xd8,
      0xff,
      0xd9,
    ]);
    expect(
      await File(
        repository.entries
            .firstWhere((entry) => entry.id == 'direct')
            .localPath,
      ).readAsBytes(),
      [1, 2, 3, 4, 5],
    );
    expect(
      await File(
        repository.entries.firstWhere((entry) => entry.id == 'hls').localPath,
      ).readAsBytes(),
      [1, 2, 3, 4],
    );
    expect(
      await File(
        repository.entries
            .firstWhere((entry) => entry.id == 'encrypted')
            .localPath,
      ).readAsBytes(),
      [9, 8, 7, 6],
    );
    expect(
      await File(
        repository.entries
            .firstWhere((entry) => entry.id == 'fragmented')
            .localPath,
      ).readAsBytes(),
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    );

    final restored = DownloadRepository(
      store: store,
      directory: () async => directory,
      wifiCheck: () async => true,
      networkChanges: const Stream.empty(),
      onActivity: (_) async {},
    );
    await restored.initialize();
    expect(restored.entries, hasLength(4));
    await restored.setMaxConcurrentDownloads(4);
    await restored.setWifiOnly(true);
    final settingsRestored = DownloadRepository(
      store: store,
      directory: () async => directory,
      wifiCheck: () async => true,
      networkChanges: const Stream.empty(),
      onActivity: (_) async {},
    );
    await settingsRestored.initialize();
    expect(settingsRestored.maxConcurrentDownloads, 4);
    expect(settingsRestored.wifiOnly, isTrue);
    await restored.deleteAll(restored.entries);
    expect(restored.entries, isEmpty);

    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('Wi-Fi-only downloads wait and resume on a network change', () async {
    final directory = await Directory.systemTemp.createTemp('terra_wifi_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add([1, 2, 3]);
      await request.response.close();
    });
    var wifi = false;
    final changes = StreamController<void>();
    final repository = DownloadRepository(
      store: _MemoryDownloadStore(),
      directory: () async => directory,
      wifiCheck: () async => wifi,
      networkChanges: changes.stream,
      onActivity: (_) async {},
    );
    await repository.initialize();
    await repository.setWifiOnly(true);
    final future = repository.add(
      _request(
        'queued',
        'http://${server.address.host}:${server.port}/video.mp4',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(repository.entries.single.status, DownloadStatus.queued);

    wifi = true;
    changes.add(null);
    await future;
    expect(repository.entries.single.status, DownloadStatus.completed);

    await changes.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
}

List<int> _encrypt(List<int> input, List<int> key, List<int> iv) {
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        true,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV(
            KeyParameter(Uint8List.fromList(key)),
            Uint8List.fromList(iv),
          ),
          null,
        ),
      );
  return cipher.process(Uint8List.fromList(input));
}

DownloadRequest _request(String id, String url) => DownloadRequest(
  id: id,
  mediaId: 'media',
  title: 'Title',
  episodeLabel: 'Episode 1',
  imageUrl: '${Uri.parse(url).resolve('/poster.jpg')}',
  sourceName: 'Source',
  sourceIconUrl: 'https://example.test/icon.png',
  sourceType: 'Mangayomi',
  qualityLabel: 'Auto',
  url: url,
);

class _MemoryDownloadStore implements DownloadStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}
