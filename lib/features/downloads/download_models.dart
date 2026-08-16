enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class DownloadEntry {
  const DownloadEntry({
    required this.id,
    required this.mediaId,
    required this.title,
    required this.episodeLabel,
    required this.imageUrl,
    this.posterPath = '',
    required this.sourceName,
    required this.sourceIconUrl,
    required this.sourceType,
    required this.qualityLabel,
    required this.url,
    required this.headers,
    required this.localPath,
    required this.status,
    required this.createdAt,
    this.season = 1,
    this.episodeNumber = 0,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes,
    this.error,
  });

  final String id;
  final String mediaId;
  final String title;
  final String episodeLabel;
  final String imageUrl;
  final String posterPath;
  final String sourceName;
  final String sourceIconUrl;
  final String sourceType;
  final String qualityLabel;
  final String url;
  final Map<String, String> headers;
  final String localPath;
  final DownloadStatus status;
  final DateTime createdAt;
  final int season;
  final double episodeNumber;
  final double progress;
  final int receivedBytes;
  final int? totalBytes;
  final String? error;

  DownloadEntry copyWith({
    String? localPath,
    String? posterPath,
    DownloadStatus? status,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? error,
    bool clearError = false,
  }) => DownloadEntry(
    id: id,
    mediaId: mediaId,
    title: title,
    episodeLabel: episodeLabel,
    imageUrl: imageUrl,
    posterPath: posterPath ?? this.posterPath,
    sourceName: sourceName,
    sourceIconUrl: sourceIconUrl,
    sourceType: sourceType,
    qualityLabel: qualityLabel,
    url: url,
    headers: headers,
    localPath: localPath ?? this.localPath,
    status: status ?? this.status,
    createdAt: createdAt,
    season: season,
    episodeNumber: episodeNumber,
    progress: progress ?? this.progress,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    error: clearError ? null : error ?? this.error,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'mediaId': mediaId,
    'title': title,
    'episodeLabel': episodeLabel,
    'imageUrl': imageUrl,
    'posterPath': posterPath,
    'sourceName': sourceName,
    'sourceIconUrl': sourceIconUrl,
    'sourceType': sourceType,
    'qualityLabel': qualityLabel,
    'url': url,
    'headers': headers,
    'localPath': localPath,
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'season': season,
    'episodeNumber': episodeNumber,
    'progress': progress,
    'receivedBytes': receivedBytes,
    'totalBytes': totalBytes,
    'error': error,
  };

  static DownloadEntry? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final status = DownloadStatus.values.cast<DownloadStatus?>().firstWhere(
      (item) => item?.name == json['status'],
      orElse: () => null,
    );
    final id = json['id']?.toString() ?? '';
    final url = json['url']?.toString() ?? '';
    if (id.isEmpty || url.isEmpty || createdAt == null || status == null) {
      return null;
    }
    return DownloadEntry(
      id: id,
      mediaId: json['mediaId']?.toString().isNotEmpty == true
          ? json['mediaId'].toString()
          : id,
      title: json['title']?.toString() ?? '',
      episodeLabel: json['episodeLabel']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      posterPath: json['posterPath']?.toString() ?? '',
      sourceName: json['sourceName']?.toString() ?? '',
      sourceIconUrl: json['sourceIconUrl']?.toString().isNotEmpty == true
          ? json['sourceIconUrl'].toString()
          : json['imageUrl']?.toString() ?? '',
      sourceType: json['sourceType']?.toString() ?? 'Source',
      qualityLabel: json['qualityLabel']?.toString() ?? '',
      url: url,
      headers: value['headers'] is Map
          ? (value['headers'] as Map).map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
      localPath: json['localPath']?.toString() ?? '',
      status: status,
      createdAt: createdAt,
      season: (json['season'] as num?)?.toInt() ?? 1,
      episodeNumber: (json['episodeNumber'] as num?)?.toDouble() ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt(),
      error: json['error']?.toString(),
    );
  }
}

class DownloadRequest {
  const DownloadRequest({
    required this.id,
    required this.mediaId,
    required this.title,
    required this.episodeLabel,
    required this.imageUrl,
    required this.sourceName,
    required this.sourceIconUrl,
    required this.sourceType,
    required this.qualityLabel,
    required this.url,
    this.season = 1,
    this.episodeNumber = 0,
    this.headers = const {},
  });

  final String id;
  final String mediaId;
  final String title;
  final String episodeLabel;
  final String imageUrl;
  final String sourceName;
  final String sourceIconUrl;
  final String sourceType;
  final String qualityLabel;
  final String url;
  final int season;
  final double episodeNumber;
  final Map<String, String> headers;
}
