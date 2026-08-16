import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:terra/theme/theme.dart';

void main() {
  testWidgets('ListTiles paint above Forui dialog decoration', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: darkTheme,
          child: Material(child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFDialog<void>(
                context: context,
                builder: (_, _, animation) => FDialog(
                  animation: animation,
                  builder: (_, _) => const Material(
                    type: MaterialType.transparency,
                    child: ListTile(title: Text('Result')),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
