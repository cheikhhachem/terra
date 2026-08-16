import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra/widgets/media_detail_layout.dart';

void main() {
  testWidgets('detail description expands beyond three lines', (tester) async {
    const description =
        'First line of details.\nSecond line of details.\nThird line of details.\nFourth line of details.';
    await tester.pumpWidget(
      MaterialApp(
        home: MediaDetailContent<int>(
          title: 'Title',
          posterUrl: '',
          posterFallbackIcon: Icons.movie,
          metadata: const [],
          description: description,
          sectionTitle: 'Episodes',
          groups: const [],
          selectedGroup: null,
          onGroupChanged: (_) {},
          ascending: true,
          onSort: () {},
          emptyMessage: 'Empty',
          itemBuilder: (_, _, _) => const SizedBox(),
          sortAscendingTooltip: 'Ascending',
          sortDescendingTooltip: 'Descending',
        ),
      ),
    );

    expect(tester.widget<Text>(find.text(description)).maxLines, 3);
    await tester.tap(find.text('More'));
    await tester.pump();
    expect(tester.widget<Text>(find.text(description)).maxLines, isNull);
    expect(find.text('Less'), findsOneWidget);
  });
}
