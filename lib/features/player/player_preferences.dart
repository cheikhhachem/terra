import 'package:shared_preferences/shared_preferences.dart';

class PlayerPreferences {
  PlayerPreferences([Future<SharedPreferences> Function()? preferences])
    : _load = preferences ?? SharedPreferences.getInstance;

  static const _rateKey = 'player_default_rate';
  static const _resumeEnabledKey = 'player_resume_enabled';
  static const _seekIncrementKey = 'player_seek_increment';
  static const _fitKey = 'player_fit';
  static const _autoplayKey = 'player_autoplay';
  static const _autoSkipKey = 'player_auto_skip';
  static const _subtitleSizeKey = 'player_subtitle_size';
  static const _subtitleBackgroundOpacityKey =
      'player_subtitle_background_opacity';
  final Future<SharedPreferences> Function() _load;

  Future<double> get defaultRate async =>
      (await _load()).getDouble(_rateKey) ?? 1.0;
  Future<bool> get resumeEnabled async =>
      (await _load()).getBool(_resumeEnabledKey) ?? true;
  Future<Duration> get seekIncrement async =>
      Duration(seconds: (await _load()).getInt(_seekIncrementKey) ?? 10);
  Future<String> get fit async =>
      (await _load()).getString(_fitKey) ?? 'contain';
  Future<bool> get autoplay async =>
      (await _load()).getBool(_autoplayKey) ?? true;
  Future<bool> get autoSkip async =>
      (await _load()).getBool(_autoSkipKey) ?? false;
  Future<double> get subtitleSize async =>
      (await _load()).getDouble(_subtitleSizeKey) ?? 36;
  Future<double> get subtitleBackgroundOpacity async =>
      (await _load()).getDouble(_subtitleBackgroundOpacityKey) ?? .5;

  Future<void> setDefaultRate(double value) async =>
      (await _load()).setDouble(_rateKey, value);
  Future<void> setResumeEnabled(bool value) async =>
      (await _load()).setBool(_resumeEnabledKey, value);
  Future<void> setSeekIncrement(Duration value) async =>
      (await _load()).setInt(_seekIncrementKey, value.inSeconds);
  Future<void> setFit(String value) async =>
      (await _load()).setString(_fitKey, value);
  Future<void> setAutoplay(bool value) async =>
      (await _load()).setBool(_autoplayKey, value);
  Future<void> setAutoSkip(bool value) async =>
      (await _load()).setBool(_autoSkipKey, value);
  Future<void> setSubtitleSize(double value) async =>
      (await _load()).setDouble(_subtitleSizeKey, value);
  Future<void> setSubtitleBackgroundOpacity(double value) async =>
      (await _load()).setDouble(_subtitleBackgroundOpacityKey, value);

  Future<Duration?> resumePosition(String key) async {
    final milliseconds = (await _load()).getInt('player_resume_$key');
    return milliseconds == null ? null : Duration(milliseconds: milliseconds);
  }

  Future<void> saveResumePosition(String key, Duration position) async =>
      (await _load()).setInt('player_resume_$key', position.inMilliseconds);
}
