// Derived from Mangayomi, Apache-2.0.
// https://github.com/kodjodevf/mangayomi

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderMode {
  vertical,
  ltr,
  rtl,
  verticalContinuous,
  webtoon,
  horizontalContinuous,
  horizontalContinuousRTL;

  bool get isContinuous => index >= verticalContinuous.index;
  bool get isVerticalContinuous =>
      this == verticalContinuous || this == webtoon;
  bool get isHorizontalContinuous =>
      this == horizontalContinuous || this == horizontalContinuousRTL;
  bool get isRTL => this == rtl || this == horizontalContinuousRTL;

  String get label => switch (this) {
    vertical => 'Vertical',
    ltr => 'Left to right',
    rtl => 'Right to left',
    verticalContinuous => 'Vertical continuous',
    webtoon => 'Webtoon',
    horizontalContinuous => 'Horizontal continuous',
    horizontalContinuousRTL => 'Horizontal continuous RTL',
  };
}

enum PageMode { onePage, doublePage }

enum ReaderScaleType {
  fitScreen,
  stretch,
  fitWidth,
  fitHeight,
  originalSize,
  smartFit;

  String get label => switch (this) {
    fitScreen => 'Fit screen',
    stretch => 'Stretch',
    fitWidth => 'Fit width',
    fitHeight => 'Fit height',
    originalSize => 'Original size',
    smartFit => 'Smart fit',
  };
}

enum ReaderBackground {
  black,
  grey,
  white,
  automatic;

  Color resolve(BuildContext context) => switch (this) {
    black => Colors.black,
    grey => const Color(0xff202020),
    white => Colors.white,
    automatic => Theme.of(context).scaffoldBackgroundColor,
  };
}

enum NovelTextAlign { left, center, right, justify }

class MangayomiReaderSettings {
  static const _key = 'terra.mangayomi.reader.settings.v1';

  ReaderMode mode = ReaderMode.vertical;
  PageMode pageMode = PageMode.onePage;
  ReaderScaleType scaleType = ReaderScaleType.fitScreen;
  ReaderBackground background = ReaderBackground.black;
  bool cropBorders = false;
  bool usePageTapZones = true;
  bool keepScreenOn = true;
  bool showPageGaps = true;
  bool showPageNumbers = true;
  bool animatePageTransitions = true;
  bool splitWidePages = false;
  bool dualPageInvert = false;
  bool rotateWidePages = false;
  bool navigateToPan = true;
  bool disableZoomOut = false;
  bool doubleTapZoom = true;
  bool autoScroll = false;
  double autoScrollSpeed = 10;
  int sidePadding = 0;
  int navigationLayout = 0;
  int tappingInversion = 0;
  bool invertColors = false;
  bool grayscale = false;
  double brightness = 0;
  double contrast = 1;
  double saturation = 1;

  int novelFontSize = 14;
  NovelTextAlign novelTextAlign = NovelTextAlign.left;
  Color novelBackground = const Color(0xff292832);
  Color novelTextColor = const Color(0xffcccccc);
  int novelPadding = 16;
  double novelLineHeight = 1.5;
  bool novelShowPercentage = true;
  bool novelCompactParagraphs = false;
  bool novelTapToScroll = false;
  bool novelAutoScroll = false;
  double novelAutoScrollSpeed = 10;
  double ttsRate = .5;
  double ttsPitch = 1;
  String? ttsLanguage;

  Future<void> load() async {
    try {
      final raw = await SharedPreferencesAsync().getString(_key);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      mode = _enum(ReaderMode.values, json['mode']) ?? mode;
      pageMode = _enum(PageMode.values, json['pageMode']) ?? pageMode;
      scaleType = _enum(ReaderScaleType.values, json['scaleType']) ?? scaleType;
      background =
          _enum(ReaderBackground.values, json['background']) ?? background;
      cropBorders = json['cropBorders'] as bool? ?? cropBorders;
      usePageTapZones = json['usePageTapZones'] as bool? ?? usePageTapZones;
      keepScreenOn = json['keepScreenOn'] as bool? ?? keepScreenOn;
      showPageGaps = json['showPageGaps'] as bool? ?? showPageGaps;
      showPageNumbers = json['showPageNumbers'] as bool? ?? showPageNumbers;
      animatePageTransitions =
          json['animatePageTransitions'] as bool? ?? animatePageTransitions;
      splitWidePages = json['splitWidePages'] as bool? ?? splitWidePages;
      dualPageInvert = json['dualPageInvert'] as bool? ?? dualPageInvert;
      rotateWidePages = json['rotateWidePages'] as bool? ?? rotateWidePages;
      navigateToPan = json['navigateToPan'] as bool? ?? navigateToPan;
      disableZoomOut = json['disableZoomOut'] as bool? ?? disableZoomOut;
      doubleTapZoom = json['doubleTapZoom'] as bool? ?? doubleTapZoom;
      autoScroll = json['autoScroll'] as bool? ?? autoScroll;
      autoScrollSpeed = _double(json['autoScrollSpeed'], autoScrollSpeed);
      sidePadding = (json['sidePadding'] as num?)?.toInt() ?? sidePadding;
      navigationLayout =
          (json['navigationLayout'] as num?)?.toInt() ?? navigationLayout;
      tappingInversion =
          (json['tappingInversion'] as num?)?.toInt() ?? tappingInversion;
      invertColors = json['invertColors'] as bool? ?? invertColors;
      grayscale = json['grayscale'] as bool? ?? grayscale;
      brightness = _double(json['brightness'], brightness);
      contrast = _double(json['contrast'], contrast);
      saturation = _double(json['saturation'], saturation);
      novelFontSize = (json['novelFontSize'] as num?)?.toInt() ?? novelFontSize;
      novelTextAlign =
          _enum(NovelTextAlign.values, json['novelTextAlign']) ??
          novelTextAlign;
      novelBackground = Color(
        (json['novelBackground'] as num?)?.toInt() ??
            novelBackground.toARGB32(),
      );
      novelTextColor = Color(
        (json['novelTextColor'] as num?)?.toInt() ?? novelTextColor.toARGB32(),
      );
      novelPadding = (json['novelPadding'] as num?)?.toInt() ?? novelPadding;
      novelLineHeight = _double(json['novelLineHeight'], novelLineHeight);
      novelShowPercentage =
          json['novelShowPercentage'] as bool? ?? novelShowPercentage;
      novelCompactParagraphs =
          json['novelCompactParagraphs'] as bool? ?? novelCompactParagraphs;
      novelTapToScroll = json['novelTapToScroll'] as bool? ?? novelTapToScroll;
      novelAutoScroll = json['novelAutoScroll'] as bool? ?? novelAutoScroll;
      novelAutoScrollSpeed = _double(
        json['novelAutoScrollSpeed'],
        novelAutoScrollSpeed,
      );
      ttsRate = _double(json['ttsRate'], ttsRate);
      ttsPitch = _double(json['ttsPitch'], ttsPitch);
      ttsLanguage = json['ttsLanguage'] as String?;
    } on Object {
      // Keep Mangayomi defaults when old settings are malformed.
    }
  }

  Future<void> save() => SharedPreferencesAsync().setString(
    _key,
    jsonEncode({
      'mode': mode.name,
      'pageMode': pageMode.name,
      'scaleType': scaleType.name,
      'background': background.name,
      'cropBorders': cropBorders,
      'usePageTapZones': usePageTapZones,
      'keepScreenOn': keepScreenOn,
      'showPageGaps': showPageGaps,
      'showPageNumbers': showPageNumbers,
      'animatePageTransitions': animatePageTransitions,
      'splitWidePages': splitWidePages,
      'dualPageInvert': dualPageInvert,
      'rotateWidePages': rotateWidePages,
      'navigateToPan': navigateToPan,
      'disableZoomOut': disableZoomOut,
      'doubleTapZoom': doubleTapZoom,
      'autoScroll': autoScroll,
      'autoScrollSpeed': autoScrollSpeed,
      'sidePadding': sidePadding,
      'navigationLayout': navigationLayout,
      'tappingInversion': tappingInversion,
      'invertColors': invertColors,
      'grayscale': grayscale,
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'novelFontSize': novelFontSize,
      'novelTextAlign': novelTextAlign.name,
      'novelBackground': novelBackground.toARGB32(),
      'novelTextColor': novelTextColor.toARGB32(),
      'novelPadding': novelPadding,
      'novelLineHeight': novelLineHeight,
      'novelShowPercentage': novelShowPercentage,
      'novelCompactParagraphs': novelCompactParagraphs,
      'novelTapToScroll': novelTapToScroll,
      'novelAutoScroll': novelAutoScroll,
      'novelAutoScrollSpeed': novelAutoScrollSpeed,
      'ttsRate': ttsRate,
      'ttsPitch': ttsPitch,
      'ttsLanguage': ttsLanguage,
    }),
  );
}

T? _enum<T extends Enum>(List<T> values, Object? name) =>
    values.where((value) => value.name == name).firstOrNull;

double _double(Object? value, double fallback) =>
    (value as num?)?.toDouble() ?? fallback;
