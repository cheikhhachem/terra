class LibraryMedia {
  const LibraryMedia({
    required this.id,
    required this.moduleId,
    required this.sourceName,
    required this.title,
    required this.imageUrl,
    required this.detailHref,
    required this.addedAt,
  });

  final String id;
  final String moduleId;
  final String sourceName;
  final String title;
  final String imageUrl;
  final String detailHref;
  final DateTime addedAt;

  Map<String, Object> toJson() => {
    'id': id,
    'moduleId': moduleId,
    'sourceName': sourceName,
    'title': title,
    'imageUrl': imageUrl,
    'detailHref': detailHref,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  static LibraryMedia? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    final addedAt = DateTime.tryParse(json['addedAt']?.toString() ?? '');
    final media = LibraryMedia(
      id: json['id']?.toString() ?? '',
      moduleId: json['moduleId']?.toString() ?? '',
      sourceName: json['sourceName']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      detailHref: json['detailHref']?.toString() ?? '',
      addedAt: addedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    if (media.id.isEmpty ||
        media.moduleId.isEmpty ||
        media.sourceName.isEmpty ||
        media.title.isEmpty ||
        media.detailHref.isEmpty ||
        addedAt == null) {
      return null;
    }
    return media;
  }
}

class ContinueWatchingEntry {
  const ContinueWatchingEntry({
    required this.media,
    required this.episodeHref,
    required this.episodeLabel,
    required this.episodeNumber,
    required this.season,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final LibraryMedia media;
  final String episodeHref;
  final String episodeLabel;
  final double episodeNumber;
  final int season;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  double get progress => duration.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  Map<String, Object> toJson() => {
    ...media.toJson(),
    'episodeHref': episodeHref,
    'episodeLabel': episodeLabel,
    'episodeNumber': episodeNumber,
    'season': season,
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static ContinueWatchingEntry? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    final media = LibraryMedia.tryFromJson(json);
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    final episodeNumber = _number(json['episodeNumber']);
    final season = _integer(json['season']);
    final positionMs = _integer(json['positionMs']);
    final durationMs = _integer(json['durationMs']);
    final episodeHref = json['episodeHref']?.toString() ?? '';
    final episodeLabel = json['episodeLabel']?.toString() ?? '';
    if (media == null ||
        updatedAt == null ||
        episodeNumber == null ||
        season == null ||
        positionMs == null ||
        durationMs == null ||
        episodeHref.isEmpty ||
        episodeLabel.isEmpty ||
        positionMs < 0 ||
        durationMs <= 0) {
      return null;
    }
    return ContinueWatchingEntry(
      media: media,
      episodeHref: episodeHref,
      episodeLabel: episodeLabel,
      episodeNumber: episodeNumber,
      season: season,
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: durationMs),
      updatedAt: updatedAt,
    );
  }
}

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

int? _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
