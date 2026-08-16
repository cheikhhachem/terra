// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';

enum ExtensionKind {
  sora('Sora'),
  mangayomi('Mangayomi');

  const ExtensionKind(this.label);
  final String label;
}

class SoraAuthor {
  const SoraAuthor({
    required this.name,
    this.icon = '',
    this.url = '',
    this.extra = const {},
  });

  final String name;
  final String icon;
  final String url;
  final Map<String, dynamic> extra;

  factory SoraAuthor.fromJson(Object? value) {
    final json = _map(value);
    return SoraAuthor(
      name: _string(json['name']),
      icon: _string(json['icon']),
      url: _string(json['url']),
      extra: _extra(json, {'name', 'icon', 'url'}),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'icon': icon,
    'url': url,
    ...extra,
  };
}

class SoraMetadata {
  const SoraMetadata({
    required this.sourceName,
    required this.author,
    required this.scriptUrl,
    this.iconUrl = '',
    this.version = '',
    this.language = '',
    this.baseUrl = '',
    this.streamType = '',
    this.quality = '',
    this.searchBaseUrl = '',
    this.asyncJS = false,
    this.streamAsyncJS = false,
    this.softsub = false,
    this.multiStream = false,
    this.multiSubs = false,
    this.type,
    this.novel = false,
    this.kind = ExtensionKind.sora,
    this.extra = const {},
  });

  final String sourceName;
  final SoraAuthor author;
  final String iconUrl;
  final String version;
  final String language;
  final String baseUrl;
  final String streamType;
  final String quality;
  final String searchBaseUrl;
  final String scriptUrl;
  final bool asyncJS;
  final bool streamAsyncJS;
  final bool softsub;
  final bool multiStream;
  final bool multiSubs;
  final String? type;
  final bool novel;
  final ExtensionKind kind;
  final Map<String, dynamic> extra;

  factory SoraMetadata.parse(String text) {
    final value = jsonDecode(text);
    if (value is! Map)
      throw const FormatException('Manifest must be a JSON object.');
    return SoraMetadata.fromJson(value);
  }

  factory SoraMetadata.fromJson(Map<dynamic, dynamic> value) {
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    final sourceName = _string(json['sourceName']).trim();
    final scriptUrl = _string(json['scriptUrl'] ?? json['scriptURL']).trim();
    if (sourceName.isEmpty)
      throw const FormatException('Manifest is missing sourceName.');
    if (scriptUrl.isEmpty)
      throw const FormatException('Manifest is missing scriptUrl.');
    const known = {
      'sourceName',
      'author',
      'iconUrl',
      'iconURL',
      'version',
      'language',
      'baseUrl',
      'streamType',
      'quality',
      'searchBaseUrl',
      'scriptUrl',
      'scriptURL',
      'asyncJS',
      'streamAsyncJS',
      'softsub',
      'multiStream',
      'multiSubs',
      'type',
      'novel',
      'kind',
    };
    return SoraMetadata(
      sourceName: sourceName,
      author: SoraAuthor.fromJson(json['author']),
      iconUrl: _string(json['iconUrl'] ?? json['iconURL']),
      version: _string(json['version']),
      language: _string(json['language']),
      baseUrl: _string(json['baseUrl']),
      streamType: _string(json['streamType']),
      quality: _string(json['quality']),
      searchBaseUrl: _string(json['searchBaseUrl']),
      scriptUrl: scriptUrl,
      asyncJS: _string(json['searchBaseUrl']).isEmpty
          ? true
          : _bool(json['asyncJS']),
      streamAsyncJS: _bool(json['streamAsyncJS']),
      softsub: _bool(json['softsub']),
      multiStream: _bool(json['multiStream']),
      multiSubs: _bool(json['multiSubs']),
      type: json['type']?.toString(),
      novel: _bool(json['novel']),
      kind: json['kind'] == ExtensionKind.mangayomi.name
          ? ExtensionKind.mangayomi
          : ExtensionKind.sora,
      extra: _extra(json, known),
    );
  }

  factory SoraMetadata.fromMangayomi(Map<dynamic, dynamic> value) {
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    final name = _string(json['name']).trim();
    final scriptUrl = _string(json['sourceCodeUrl']).trim();
    if (name.isEmpty || scriptUrl.isEmpty)
      throw const FormatException(
        'Mangayomi source is missing a name or script URL.',
      );
    final itemType = int.tryParse(_string(json['itemType']));
    final type = switch (itemType) {
      0 => 'Manga',
      1 => 'Anime',
      2 => 'Novel',
      _ => _bool(json['isManga']) ? 'Manga' : 'Anime',
    };
    return SoraMetadata(
      sourceName: name,
      author: const SoraAuthor(name: 'Mangayomi'),
      iconUrl: _string(json['iconUrl']),
      version: _string(json['version']),
      language: _string(json['lang']),
      baseUrl: _string(json['baseUrl']),
      scriptUrl: scriptUrl,
      asyncJS: true,
      type: type,
      novel: itemType == 2,
      kind: ExtensionKind.mangayomi,
      extra: _extra(json, const {
        'name',
        'baseUrl',
        'lang',
        'iconUrl',
        'version',
        'sourceCodeUrl',
      }),
    );
  }

  Map<String, dynamic> toJson() => {
    'sourceName': sourceName,
    'author': author.toJson(),
    'iconUrl': iconUrl,
    'version': version,
    'language': language,
    'baseUrl': baseUrl,
    'streamType': streamType,
    'quality': quality,
    'searchBaseUrl': searchBaseUrl,
    'scriptUrl': scriptUrl,
    'asyncJS': asyncJS,
    'streamAsyncJS': streamAsyncJS,
    'softsub': softsub,
    'multiStream': multiStream,
    'multiSubs': multiSubs,
    if (type != null) 'type': type,
    'novel': novel,
    'kind': kind.name,
    ...extra,
  };
}

class InstalledSoraModule {
  const InstalledSoraModule({
    required this.id,
    required this.metadata,
    required this.scriptPath,
    required this.metadataUrl,
    this.active = true,
  });
  final String id;
  final SoraMetadata metadata;
  final String scriptPath;
  final String metadataUrl;
  final bool active;

  factory InstalledSoraModule.fromJson(Map<dynamic, dynamic> json) =>
      InstalledSoraModule(
        id: _string(json['id']),
        metadata: SoraMetadata.fromJson(_map(json['metadata'])),
        scriptPath: _string(json['scriptPath']),
        metadataUrl: _string(json['metadataUrl']),
        active: json['active'] == null || _bool(json['active']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'metadata': metadata.toJson(),
    'scriptPath': scriptPath,
    'metadataUrl': metadataUrl,
    'active': active,
  };
}

class KnownSoraSource {
  const KnownSoraSource({
    required this.id,
    required this.metadata,
    required this.metadataUrl,
  });

  final String id;
  final SoraMetadata metadata;
  final String metadataUrl;

  factory KnownSoraSource.fromJson(Map<dynamic, dynamic> json) =>
      KnownSoraSource(
        id: _string(json['id']),
        metadata: SoraMetadata.fromJson(_map(json['metadata'])),
        metadataUrl: _string(json['metadataUrl']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'metadata': metadata.toJson(),
    'metadataUrl': metadataUrl,
  };
}

class SoraSearchResult {
  const SoraSearchResult({
    required this.title,
    required this.imageUrl,
    required this.href,
    this.imdbId,
    this.mediaType,
  });
  final String title;
  final String imageUrl;
  final String href;
  final String? imdbId;
  final String? mediaType;

  factory SoraSearchResult.fromJson(Object? value) {
    final json = _map(value);
    final href = _string(json['href'] ?? json['url'] ?? json['link']);
    return SoraSearchResult(
      title: _string(json['title'] ?? json['name']),
      imageUrl: _string(json['image'] ?? json['imageUrl'] ?? json['poster']),
      href: href,
      imdbId: _imdbId(
        json['imdbId'] ?? json['imdb_id'] ?? json['imdb'] ?? href,
      ),
      mediaType: _mediaType(json['mediaType'] ?? json['type']),
    );
  }
}

String? _imdbId(Object? value) => RegExp(
  r'\btt\d{7,10}\b',
  caseSensitive: false,
).firstMatch(_string(value))?.group(0)?.toLowerCase();

String? _mediaType(Object? value) => switch (_string(value).toLowerCase()) {
  'movie' || 'movies' || 'film' || 'films' => 'movie',
  'series' || 'show' || 'shows' || 'tv' || 'anime' => 'series',
  _ => null,
};

class SoraDetails {
  const SoraDetails({
    this.description = '',
    this.aliases = '',
    this.airdate = '',
    this.imdbId,
    this.mediaType,
  });
  final String description;
  final String aliases;
  final String airdate;
  final String? imdbId;
  final String? mediaType;

  factory SoraDetails.fromJson(Object? value) {
    final json = _map(value);
    return SoraDetails(
      description: _string(
        json['description'] ?? json['synopsis'] ?? json['plot'],
      ),
      aliases: _join(json['aliases'] ?? json['genres']),
      airdate: _string(json['airdate'] ?? json['year'] ?? json['releaseDate']),
      imdbId: _imdbId(
        json['imdbId'] ?? json['imdb_id'] ?? json['imdb'] ?? json['url'],
      ),
      mediaType: _mediaType(json['mediaType'] ?? json['type']),
    );
  }

  Map<String, dynamic> toJson() => {
    'description': description,
    'aliases': aliases,
    'airdate': airdate,
    if (imdbId != null) 'imdbId': imdbId,
    if (mediaType != null) 'mediaType': mediaType,
  };
}

class SoraEpisode {
  const SoraEpisode({
    required this.href,
    required this.number,
    this.title = '',
    this.imageUrl = '',
    this.season,
  });
  final String href;
  final double number;
  final String title;
  final String imageUrl;
  final int? season;

  factory SoraEpisode.fromJson(Object? value, int index) {
    final json = _map(value);
    final rawNumber = json['number'] ?? json['episode'] ?? index + 1;
    final title = _string(json['title'] ?? json['name']);
    final href = _string(json['href'] ?? json['url'] ?? json['id']);
    return SoraEpisode(
      href: href,
      number: rawNumber is num
          ? rawNumber.toDouble()
          : double.tryParse(rawNumber.toString()) ?? index + 1.0,
      title: title,
      imageUrl: _string(json['image'] ?? json['thumbnail']),
      season: _episodeSeason(json['season'], title, href),
    );
  }

  Map<String, dynamic> toJson() => {
    'href': href,
    'number': number,
    'title': title,
    'image': imageUrl,
    if (season != null) 'season': season,
  };

  String get label => title.isNotEmpty
      ? title
      : 'Episode ${number == number.roundToDouble() ? number.toInt() : number}';
}

int? _episodeSeason(Object? value, String title, String href) {
  final explicit = value is num ? value.toInt() : int.tryParse(_string(value));
  if (explicit != null) return explicit;
  for (final pattern in [
    RegExp(r'\bS(?:eason\s*)?0*(\d+)\b', caseSensitive: false),
    RegExp(r'/embed/tv/tt\d+/(\d+)/\d+', caseSensitive: false),
    RegExp(r'/season[\/_-]?(\d+)', caseSensitive: false),
  ]) {
    final match = pattern.firstMatch('$title $href');
    if (match != null) return int.tryParse(match.group(1)!);
  }
  return null;
}

Map<int, List<SoraEpisode>> groupSoraEpisodesBySeason(
  List<SoraEpisode> episodes, {
  bool ascending = true,
}) {
  final sorted = episodes.indexed.toList()
    ..sort((a, b) {
      final season = (a.$2.season ?? 1).compareTo(b.$2.season ?? 1);
      if (season != 0) return season;
      final number = a.$2.number.compareTo(b.$2.number);
      if (number != 0) return ascending ? number : -number;
      return a.$1.compareTo(b.$1);
    });
  final grouped = <int, List<SoraEpisode>>{};
  for (final item in sorted) {
    grouped.putIfAbsent(item.$2.season ?? 1, () => []).add(item.$2);
  }
  return grouped;
}

class SoraStream {
  const SoraStream({
    required this.url,
    this.title = 'Auto',
    this.headers = const {},
  });
  final String url;
  final String title;
  final Map<String, String> headers;

  factory SoraStream.fromJson(Object? value, int index) {
    if (value is String)
      return SoraStream(url: value, title: 'Source ${index + 1}');
    final json = _map(value);
    return SoraStream(
      url: _string(
        json['streamUrl'] ?? json['url'] ?? json['file'] ?? json['src'],
      ),
      title:
          _string(
            json['title'] ?? json['quality'] ?? json['label'],
          ).trim().isEmpty
          ? 'Source ${index + 1}'
          : _string(json['title'] ?? json['quality'] ?? json['label']),
      headers: _stringMap(json['headers']),
    );
  }
}

class SoraSubtitle {
  const SoraSubtitle({
    required this.url,
    this.label = 'Subtitle',
    this.language,
  });
  final String url;
  final String label;
  final String? language;

  factory SoraSubtitle.fromJson(Object? value, int index) {
    if (value is String)
      return SoraSubtitle(url: value, label: 'Subtitle ${index + 1}');
    final json = _map(value);
    return SoraSubtitle(
      url: _string(json['url'] ?? json['file'] ?? json['src']),
      label:
          _string(json['label'] ?? json['title'] ?? json['lang']).trim().isEmpty
          ? 'Subtitle ${index + 1}'
          : _string(json['label'] ?? json['title'] ?? json['lang']),
      language: json['language']?.toString() ?? json['lang']?.toString(),
    );
  }
}

class SoraStreams {
  const SoraStreams({required this.streams, this.subtitles = const []});
  final List<SoraStream> streams;
  final List<SoraSubtitle> subtitles;

  factory SoraStreams.fromValue(Object? input) {
    final value = decodeSoraValue(input);
    if (value is String)
      return SoraStreams(
        streams: value.isEmpty ? [] : [SoraStream(url: value)],
      );
    if (value is List)
      return SoraStreams(
        streams: _list(value).indexed
            .map((item) => SoraStream.fromJson(item.$2, item.$1))
            .where((item) => item.url.isNotEmpty)
            .toList(),
      );
    final json = _map(value);
    final rawStreams = json['streams'] ?? json['stream'] ?? json['sources'];
    final rawSubtitles =
        json['subtitles'] ?? json['subtitle'] ?? json['tracks'];
    final streamValues = _list(rawStreams);
    final embeddedSubtitles = streamValues
        .map(_map)
        .map((stream) => stream['subtitle'])
        .where((subtitle) => subtitle != null && subtitle != '')
        .toList();
    return SoraStreams(
      streams: streamValues.indexed
          .map((item) => SoraStream.fromJson(item.$2, item.$1))
          .where((item) => item.url.isNotEmpty)
          .toList(),
      subtitles: _soraSubtitles([..._list(rawSubtitles), ...embeddedSubtitles]),
    );
  }
}

List<SoraSubtitle> _soraSubtitles(List<Object?> values) {
  final subtitles = <SoraSubtitle>[];
  for (var index = 0; index < values.length; index++) {
    final value = values[index];
    final next = index + 1 < values.length ? values[index + 1] : null;
    // Sora modules may return [label, url, label, url] instead of objects.
    if (value is String && next is String && !_isUrl(value) && _isUrl(next)) {
      subtitles.add(SoraSubtitle(url: next, label: value));
      index++;
      continue;
    }
    final subtitle = SoraSubtitle.fromJson(value, subtitles.length);
    if (subtitle.url.isNotEmpty) subtitles.add(subtitle);
  }
  return subtitles;
}

bool _isUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.hasScheme && uri.host.isNotEmpty;
}

Object? decodeSoraValue(Object? value) {
  var current = value;
  for (var i = 0; i < 2 && current is String; i++) {
    final text = current.trim();
    if (!(text.startsWith('{') || text.startsWith('[') || text.startsWith('"')))
      break;
    try {
      current = jsonDecode(text);
    } on FormatException {
      break;
    }
  }
  return current;
}

List<Object?> soraList(Object? value) => _list(decodeSoraValue(value));

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};
List<Object?> _list(Object? value) => value == null || value == ''
    ? []
    : value is List
    ? value
    : [value];
String _string(Object? value) => value?.toString() ?? '';
bool _bool(Object? value) =>
    value == true || value == 1 || value?.toString().toLowerCase() == 'true';
String _join(Object? value) =>
    value is List ? value.join(', ') : _string(value);
Map<String, String> _stringMap(Object? value) =>
    _map(value).map((key, value) => MapEntry(key, value.toString()));
Map<String, dynamic> _extra(Map<String, dynamic> json, Set<String> known) =>
    Map.fromEntries(json.entries.where((entry) => !known.contains(entry.key)));
