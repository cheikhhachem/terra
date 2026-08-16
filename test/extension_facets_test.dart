import 'package:flutter_test/flutter_test.dart';
import 'package:terra/features/extensions/extension_facets.dart';

void main() {
  test('normalizes language names, codes, and aliases', () {
    expect(extensionLanguages('Arabic'), {'Arabic'});
    expect(extensionLanguages('ar'), {'Arabic'});
    expect(extensionLanguages('frnsh'), {'French'});
    expect(extensionLanguages('en/fr'), {'English', 'French'});
    expect(extensionLanguages('all'), {allLanguages});
    expect(extensionLanguages('pt-BR'), {'Portuguese'});
    expect(extensionLanguages('es-419'), {'Spanish'});
    expect(extensionLanguages('zh-HK'), {'Chinese'});
  });

  test('splits and normalizes media type aliases independent of order', () {
    expect(extensionMediaTypes('shows/movies/anime'), {
      'Shows',
      'Movies',
      'Anime',
    });
    expect(extensionMediaTypes('Anime / Films / TV'), {
      'Anime',
      'Movies',
      'Shows',
    });
    expect(extensionMediaTypes('series, movie'), {'Shows', 'Movies'});
  });

  test('normalizes readable formats and derives watch/read modes', () {
    expect(extensionMediaTypes('mangas/manhwa/webtoons'), {
      'Manga',
      'Manhwa',
      'Webtoon',
    });
    expect(extensionMediaTypes('light-novel, web novel, books, PDF'), {
      'Light Novel',
      'Web Novel',
      'Book',
      'PDF',
    });
    expect(extensionMediaModes('anime/manga'), {
      ExtensionMediaMode.watch,
      ExtensionMediaMode.read,
    });
    expect(extensionMediaModes('novels'), {ExtensionMediaMode.read});
    expect(extensionMediaModes(null, novel: true), {ExtensionMediaMode.read});
    expect(extensionMediaModes(null), {ExtensionMediaMode.watch});
  });
}
