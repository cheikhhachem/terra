import 'dart:convert';

enum ReadMediaKind { manga, novel }

class ReadSearchResult {
  const ReadSearchResult({
    required this.title,
    required this.href,
    required this.imageUrl,
  });

  final String title;
  final String href;
  final String imageUrl;

  factory ReadSearchResult.fromJson(Object? value) {
    final json = _map(value);
    return ReadSearchResult(
      title: _string(json['title'] ?? json['name']),
      href: _string(json['href'] ?? json['url'] ?? json['link'] ?? json['id']),
      imageUrl: _string(
        json['image'] ?? json['imageUrl'] ?? json['imageURL'] ?? json['poster'],
      ),
    );
  }
}

class ReadMedia {
  const ReadMedia({
    required this.id,
    required this.moduleId,
    required this.sourceName,
    required this.title,
    required this.imageUrl,
    required this.detailHref,
    required this.kind,
    required this.addedAt,
  });

  final String id;
  final String moduleId;
  final String sourceName;
  final String title;
  final String imageUrl;
  final String detailHref;
  final ReadMediaKind kind;
  final DateTime addedAt;

  Map<String, Object> toJson() => {
    'id': id,
    'moduleId': moduleId,
    'sourceName': sourceName,
    'title': title,
    'imageUrl': imageUrl,
    'detailHref': detailHref,
    'kind': kind.name,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  static ReadMedia? tryFromJson(Object? value) {
    final json = _map(value);
    final addedAt = DateTime.tryParse(_string(json['addedAt']));
    final kind = ReadMediaKind.values
        .where((kind) => kind.name == json['kind'])
        .firstOrNull;
    if (addedAt == null || kind == null) return null;
    final media = ReadMedia(
      id: _string(json['id']),
      moduleId: _string(json['moduleId']),
      sourceName: _string(json['sourceName']),
      title: _string(json['title']),
      imageUrl: _string(json['imageUrl']),
      detailHref: _string(json['detailHref']),
      kind: kind,
      addedAt: addedAt,
    );
    return media.id.isEmpty ||
            media.moduleId.isEmpty ||
            media.title.isEmpty ||
            media.detailHref.isEmpty
        ? null
        : media;
  }
}

class ReadDetails {
  const ReadDetails({
    required this.description,
    required this.author,
    required this.artist,
    required this.status,
    required this.genres,
    required this.chapters,
  });

  final String description;
  final String author;
  final String artist;
  final String status;
  final List<String> genres;
  final List<ReadChapter> chapters;

  factory ReadDetails.fromJson(Object? value, List<ReadChapter> chapters) {
    final json = _map(value);
    final statusValue = json['status'];
    final statusIndex = statusValue is num
        ? statusValue.toInt()
        : int.tryParse(_string(statusValue));
    return ReadDetails(
      description: _string(
        json['description'] ?? json['synopsis'] ?? json['plot'],
      ),
      author: _string(json['author']),
      artist: _string(json['artist']),
      status: statusIndex != null
          ? const [
                  'Ongoing',
                  'Completed',
                  'On hiatus',
                  'Canceled',
                  'Publishing finished',
                ].elementAtOrNull(statusIndex) ??
                'Unknown'
          : _string(statusValue),
      genres: _strings(json['genre'] ?? json['genres'] ?? json['tags']),
      chapters: List.unmodifiable(chapters),
    );
  }
}

class ReadChapter {
  const ReadChapter({
    required this.href,
    required this.title,
    required this.number,
    this.dateUpload = '',
    this.scanlator = '',
  });

  final String href;
  final String title;
  final double number;
  final String dateUpload;
  final String scanlator;

  factory ReadChapter.fromJson(Object? value, int index) {
    final json = _map(value);
    final rawNumber = json['number'] ?? json['chapter'] ?? index + 1;
    final number = rawNumber is num
        ? rawNumber.toDouble()
        : double.tryParse(rawNumber.toString()) ?? index + 1.0;
    final href = _string(
      json['href'] ?? json['url'] ?? json['link'] ?? json['id'],
    );
    final title = _string(
      json['title'] ?? json['name'] ?? json['scanlation_group'],
    );
    return ReadChapter(
      href: href,
      title: title.isEmpty
          ? 'Chapter ${number == number.roundToDouble() ? number.toInt() : number}'
          : title,
      number: number,
      dateUpload: _string(json['dateUpload'] ?? json['date']),
      scanlator: _string(json['scanlator']),
    );
  }

  static List<ReadChapter> listFrom(Object? value) {
    final output = <ReadChapter>[];
    void collect(Object? item) {
      if (item is List) {
        if (item.length == 2 && item[1] is List) {
          for (final chapter in item[1] as List) {
            collect(chapter);
          }
        } else {
          for (final chapter in item) {
            collect(chapter);
          }
        }
      } else if (item is Map) {
        final json = _map(item);
        if (json.keys.any({'href', 'url', 'link', 'id'}.contains)) {
          final chapter = ReadChapter.fromJson(json, output.length);
          if (chapter.href.isNotEmpty) {
            output.add(chapter);
          }
        } else {
          for (final child in json.values) {
            collect(child);
          }
        }
      }
    }

    collect(value);
    return output;
  }
}

class ReadPage {
  const ReadPage({required this.url, this.headers = const {}});
  final String url;
  final Map<String, String> headers;

  factory ReadPage.fromJson(Object? value) {
    if (value is String) return ReadPage(url: value.trim());
    final json = _map(value);
    return ReadPage(
      url: _string(json['url'] ?? json['src']),
      headers: _map(
        json['headers'],
      ).map((key, value) => MapEntry(key, value.toString())),
    );
  }
}

class ContinueReadingEntry {
  const ContinueReadingEntry({
    required this.media,
    required this.chapterHref,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.position,
    required this.updatedAt,
  });

  final ReadMedia media;
  final String chapterHref;
  final String chapterTitle;
  final int chapterIndex;
  final double position;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
    'media': media.toJson(),
    'chapterHref': chapterHref,
    'chapterTitle': chapterTitle,
    'chapterIndex': chapterIndex,
    'position': position,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static ContinueReadingEntry? tryFromJson(Object? value) {
    final json = _map(value);
    final media = ReadMedia.tryFromJson(json['media']);
    final updatedAt = DateTime.tryParse(_string(json['updatedAt']));
    final position = double.tryParse(_string(json['position']));
    final chapterIndex = int.tryParse(_string(json['chapterIndex']));
    if (media == null ||
        updatedAt == null ||
        position == null ||
        chapterIndex == null) {
      return null;
    }
    return ContinueReadingEntry(
      media: media,
      chapterHref: _string(json['chapterHref']),
      chapterTitle: _string(json['chapterTitle']),
      chapterIndex: chapterIndex,
      position: position.clamp(0, 1),
      updatedAt: updatedAt,
    );
  }
}

Object? decodeReadValue(Object? value) {
  if (value is! String) return value;
  try {
    return jsonDecode(value);
  } catch (_) {
    return value;
  }
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

String _string(Object? value) => value?.toString().trim() ?? '';

List<String> _strings(Object? value) => value is List
    ? value.map(_string).where((item) => item.isNotEmpty).toList()
    : _string(value)
          .split(RegExp(r'\s*(?:,|/|\|)\s*'))
          .where((item) => item.isNotEmpty)
          .toList();
