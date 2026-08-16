import 'package:flutter_test/flutter_test.dart';
import 'package:terra/features/reading/reading_models.dart';

void main() {
  test('read search accepts Sora manga result fields', () {
    final result = ReadSearchResult.fromJson({
      'title': 'Example',
      'id': '/manga/example',
      'imageURL': 'https://example.test/cover.jpg',
    });

    expect(result.title, 'Example');
    expect(result.href, '/manga/example');
    expect(result.imageUrl, 'https://example.test/cover.jpg');
  });

  test('nested Sora scanlation maps normalize into chapters', () {
    final chapters = ReadChapter.listFrom({
      'en': [
        [
          12,
          [
            {
              'id': '/chapter/12',
              'chapter': '12',
              'scanlation_group': 'Chapter 12',
            },
          ],
        ],
      ],
      'fr': [
        {'href': '/fr/chapter/1', 'title': 'Chapitre 1'},
      ],
    });

    expect(chapters.map((chapter) => chapter.href), [
      '/chapter/12',
      '/fr/chapter/1',
    ]);
    expect(chapters.first.number, 12);
    expect(chapters.first.title, 'Chapter 12');
  });

  test('Mangayomi page headers normalize', () {
    final page = ReadPage.fromJson({
      'url': 'https://example.test/page.jpg',
      'headers': {'Referer': 'https://example.test/'},
    });

    expect(page.url, 'https://example.test/page.jpg');
    expect(page.headers['Referer'], 'https://example.test/');
  });
}
