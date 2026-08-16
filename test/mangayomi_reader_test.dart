import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:terra/features/reading/mangayomi_reader_gesture_handler.dart';
import 'package:terra/features/reading/mangayomi_reader_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Mangayomi reader settings persist all reader families', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final settings = MangayomiReaderSettings()
      ..mode = ReaderMode.horizontalContinuousRTL
      ..pageMode = PageMode.doublePage
      ..navigationLayout = 4
      ..brightness = -.4
      ..novelTextAlign = NovelTextAlign.justify
      ..novelFontSize = 23
      ..novelAutoScroll = true;
    await settings.save();

    final restored = MangayomiReaderSettings();
    await restored.load();

    expect(restored.mode, ReaderMode.horizontalContinuousRTL);
    expect(restored.pageMode, PageMode.doublePage);
    expect(restored.navigationLayout, 4);
    expect(restored.brightness, -.4);
    expect(restored.novelTextAlign, NovelTextAlign.justify);
    expect(restored.novelFontSize, 23);
    expect(restored.novelAutoScroll, isTrue);
  });

  testWidgets('right-left tap layout follows RTL direction', (tester) async {
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: MangayomiReaderGestureHandler(
            usePageTapZones: true,
            isRTL: true,
            isContinuousMode: false,
            navigationLayout: 4,
            tappingInversion: 0,
            onToggleUI: () {},
            onPreviousPage: () => previous++,
            onNextPage: () => next++,
          ),
        ),
      ),
    );

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width * .2, size.height * .5));
    await tester.pump();
    await tester.tapAt(Offset(size.width * .8, size.height * .5));
    await tester.pump();

    expect(next, 1);
    expect(previous, 1);
  });
}
