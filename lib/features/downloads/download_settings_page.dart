import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../widgets/terra_header.dart';
import 'download_repository.dart';

class DownloadSettingsPage extends StatelessWidget {
  const DownloadSettingsPage({super.key, required this.downloads});

  final DownloadRepository downloads;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          const TerraHeader(title: Text('Download settings')),
          Expanded(
            child: ListenableBuilder(
              listenable: downloads,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Network',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  FSwitch(
                    label: const Text('Wi-Fi only'),
                    description: const Text(
                      'Queue downloads on mobile data and resume on Wi-Fi.',
                    ),
                    value: downloads.wifiOnly,
                    onChange: downloads.setWifiOnly,
                  ),
                  const SizedBox(height: 18),
                  FSelect<int>(
                    label: const Text('Concurrent downloads'),
                    description: const Text(
                      'More downloads can use more bandwidth and battery.',
                    ),
                    items: const {
                      '1 download': 1,
                      '2 downloads': 2,
                      '3 downloads': 3,
                      '4 downloads': 4,
                      '5 downloads': 5,
                    },
                    control: .lifted(
                      value: downloads.maxConcurrentDownloads,
                      onChange: (value) {
                        if (value != null) {
                          downloads.setMaxConcurrentDownloads(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Storage',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  FCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.storage_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${downloads.entries.length} items · ${_bytes(downloads.completedBytes)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          FButton(
                            variant: .destructive,
                            size: .sm,
                            mainAxisSize: .min,
                            onPress: downloads.entries.isEmpty
                                ? null
                                : () => _clear(context),
                            child: const Text('Clear all'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _clear(BuildContext context) async {
    final confirmed =
        await showFDialog<bool>(
          context: context,
          builder: (dialogContext, _, animation) => FDialog(
            animation: animation,
            semanticsLabel: 'Clear all downloads?',
            builder: (_, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clear all downloads?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'All downloaded files and queued items will be removed.',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FButton(
                        variant: .outline,
                        mainAxisSize: .min,
                        onPress: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FButton(
                        variant: .destructive,
                        mainAxisSize: .min,
                        onPress: () => Navigator.pop(dialogContext, true),
                        child: const Text('Clear all'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
    if (confirmed) await downloads.clearAll();
  }
}

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
