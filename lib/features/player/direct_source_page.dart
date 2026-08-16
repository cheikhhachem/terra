import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/terra_header.dart';
import 'player_page.dart';
import 'player_source.dart';

class DirectSourcePage extends StatefulWidget {
  const DirectSourcePage({super.key});

  @override
  State<DirectSourcePage> createState() => _DirectSourcePageState();
}

class _DirectSourcePageState extends State<DirectSourcePage> {
  static const _sourceKey = 'last_direct_media_source';
  final _controller = TextEditingController();
  final _preferences = SharedPreferencesAsync();
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLastSource();
  }

  Future<void> _loadLastSource() async {
    final source = await _preferences.getString(_sourceKey);
    if (mounted && source != null) setState(() => _controller.text = source);
  }

  Future<void> _open() async {
    final source = _controller.text.trim();
    final uri = Uri.tryParse(source);
    if (uri == null ||
        !uri.hasScheme ||
        !['http', 'https'].contains(uri.scheme)) {
      setState(() => _error = 'Enter a valid http:// or https:// media URL.');
      return;
    }
    await _preferences.setString(_sourceKey, source);
    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerPage(
            source: PlayerSource(
              title: 'Direct media',
              episodeLabel: 'Direct source',
              resumeKey: source,
              qualities: [PlayerQuality(label: 'Direct', url: source)],
            ),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          const TerraHeader(title: Text('Direct media source')),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Play a URL you control. HLS (.m3u8) and MP4 are supported.',
                  ),
                  const SizedBox(height: 16),
                  FTextField(
                    control: FTextFieldControl.managed(controller: _controller),
                    keyboardType: TextInputType.url,
                    label: const Text('Media URL'),
                    error: _error == null ? null : Text(_error!),
                  ),
                  const SizedBox(height: 16),
                  FButton(
                    onPress: _open,
                    prefix: const Icon(Icons.play_arrow),
                    child: const Text('Open player'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
