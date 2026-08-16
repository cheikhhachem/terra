import 'package:flutter/material.dart';

bool _episodeOperationActive = false;

Future<T?> runEpisodeOperation<T>(
  BuildContext context,
  Future<T> Function() operation,
) async {
  if (_episodeOperationActive || !context.mounted) return null;
  _episodeOperationActive = true;
  final entry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Color(0x99000000)),
        Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Fetching episode...',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    return await operation();
  } finally {
    entry.remove();
    _episodeOperationActive = false;
  }
}
