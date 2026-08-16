const allLanguages = 'All languages';

enum ExtensionMediaMode {
  watch('Watch'),
  read('Read');

  const ExtensionMediaMode(this.label);
  final String label;
}

const _readFormats = {
  'Manga',
  'Manhwa',
  'Manhua',
  'Webtoon',
  'Comics',
  'Novel',
  'Light Novel',
  'Web Novel',
  'Book',
  'eBook',
  'PDF',
};

Set<String> extensionLanguages(String value) {
  final languages = <String>{};
  for (final item in _parts(value)) {
    final normalized = _normalized(item);
    final base = normalized.split(' ').first;
    languages.add(switch (normalized) {
      'all' || 'any' || 'multi' || 'multilingual' => allLanguages,
      'ar' || 'ara' || 'arabic' || 'العربية' => 'Arabic',
      'en' || 'eng' || 'english' => 'English',
      'fr' || 'fra' || 'fre' || 'french' || 'frnsh' => 'French',
      'es' || 'spa' || 'spanish' => 'Spanish',
      'de' || 'deu' || 'ger' || 'german' => 'German',
      'it' || 'ita' || 'italian' => 'Italian',
      'pt' || 'por' || 'portuguese' || 'brazilian portuguese' => 'Portuguese',
      'ja' || 'jp' || 'jpn' || 'japanese' => 'Japanese',
      'ko' || 'kor' || 'korean' => 'Korean',
      'zh' || 'zho' || 'chi' || 'chinese' => 'Chinese',
      'ru' || 'rus' || 'russian' => 'Russian',
      'tr' || 'tur' || 'turkish' => 'Turkish',
      'hi' || 'hin' || 'hindi' => 'Hindi',
      'id' || 'ind' || 'indonesian' => 'Indonesian',
      'th' || 'tha' || 'thai' => 'Thai',
      'vi' || 'vie' || 'vietnamese' => 'Vietnamese',
      'pl' || 'pol' || 'polish' => 'Polish',
      'nl' || 'nld' || 'dut' || 'dutch' => 'Dutch',
      _ => switch (base) {
        'pt' => 'Portuguese',
        'es' => 'Spanish',
        'zh' => 'Chinese',
        _ => _titleCase(item),
      },
    });
  }
  return languages;
}

Set<String> extensionMediaTypes(String? value) {
  final types = <String>{};
  for (final item in _parts(value ?? '')) {
    final normalized = _normalized(item);
    types.add(switch (normalized) {
      'show' ||
      'shows' ||
      'series' ||
      'serie' ||
      'tv' ||
      'tv show' ||
      'tv shows' ||
      'television' => 'Shows',
      'movie' || 'movies' || 'film' || 'films' || 'cinema' => 'Movies',
      'anime' || 'animes' => 'Anime',
      'cartoon' || 'cartoons' || 'animation' || 'animations' => 'Animation',
      'documentary' || 'documentaries' || 'docs' => 'Documentaries',
      'manga' || 'mangas' => 'Manga',
      'manhwa' || 'manhwas' => 'Manhwa',
      'manhua' || 'manhuas' => 'Manhua',
      'webtoon' || 'webtoons' => 'Webtoon',
      'comic' || 'comics' => 'Comics',
      'novel' || 'novels' => 'Novel',
      'light novel' || 'light novels' || 'ln' => 'Light Novel',
      'web novel' || 'web novels' || 'wn' => 'Web Novel',
      'book' || 'books' => 'Book',
      'ebook' || 'ebooks' || 'e book' || 'e books' => 'eBook',
      'pdf' || 'pdfs' => 'PDF',
      _ => _titleCase(item),
    });
  }
  return types;
}

Set<ExtensionMediaMode> extensionMediaModes(
  String? value, {
  bool novel = false,
}) {
  final types = extensionMediaTypes(value);
  final modes = <ExtensionMediaMode>{
    if (types.any(_readFormats.contains) || novel) ExtensionMediaMode.read,
    if (types.any((type) => !_readFormats.contains(type)))
      ExtensionMediaMode.watch,
  };
  return modes.isEmpty ? {ExtensionMediaMode.watch} : modes;
}

List<String> _parts(String value) => value
    .split(RegExp(r'\s*(?:/|,|;|\||\+|&)\s*'))
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toList();

String _normalized(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[._-]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

String _titleCase(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .map(
      (word) => word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
    )
    .join(' ');
