class PlayerOpenRequest {
  const PlayerOpenRequest({
    required this.url,
    required this.headers,
    required this.position,
  });
  final String url;
  final Map<String, String> headers;
  final Duration position;
}

class PlayerControlState {
  const PlayerControlState({this.visible = true, this.settingsOpen = false});
  final bool visible;
  final bool settingsOpen;

  PlayerControlState reveal() =>
      PlayerControlState(visible: true, settingsOpen: settingsOpen);
  PlayerControlState hide() =>
      PlayerControlState(visible: false, settingsOpen: settingsOpen);
  PlayerControlState setSettings(bool value) =>
      PlayerControlState(visible: visible, settingsOpen: value);
}

Duration clampPlayerDuration(Duration value, Duration maximum) {
  if (value < Duration.zero) return Duration.zero;
  if (maximum > Duration.zero && value > maximum) return maximum;
  return value;
}
