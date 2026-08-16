import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../downloads/download_repository.dart';
import '../downloads/download_settings_page.dart';
import '../downloads/downloads_page.dart';
import '../extensions/extension_manager.dart';
import '../extensions/extension_detail_repository.dart';
import '../extensions/extension_search_page.dart';
import '../extensions/modules_page.dart';
import '../extensions/sora_extension_service.dart';
import '../library/library_page.dart';
import '../library/library_repository.dart';
import '../player/direct_source_page.dart';
import '../reading/read_download_repository.dart';
import '../settings/about_page.dart';
import '../settings/app_settings.dart';
import '../settings/general_settings_page.dart';
import '../../widgets/terra_brand.dart';

class TerraHome extends StatefulWidget {
  const TerraHome({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<TerraHome> createState() => _TerraHomeState();
}

class _TerraHomeState extends State<TerraHome> {
  static const _labels = ['Library', 'Downloads', 'Search', 'Settings'];
  static const _icons = [
    FLucideIcons.library,
    FLucideIcons.download,
    FLucideIcons.search,
    FLucideIcons.settings,
  ];
  late final ExtensionManager _extensions = ExtensionManager();
  late final LibraryRepository _library = LibraryRepository();
  late final DownloadRepository _downloads = DownloadRepository();
  late final ReadDownloadRepository _readDownloads = ReadDownloadRepository();
  late final ExtensionService _extensionService = ExtensionService(_extensions);
  late final ExtensionDetailRepository _extensionDetails =
      ExtensionDetailRepository(service: _extensionService);
  int _index = 0;
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _extensions.initialize().then(
      (_) => _extensions.refreshAllSources(ignoreErrors: true),
    );
    _library.initialize();
    _downloads.initialize();
    _readDownloads.initialize();
  }

  @override
  void dispose() {
    _extensions.dispose();
    _library.dispose();
    _downloads.dispose();
    _readDownloads.dispose();
    _extensionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return FScaffold(
      sidebar: wide
          ? _Sidebar(
              index: _index,
              onSelect: _select,
              collapsed: _sidebarCollapsed,
              onToggle: _toggleSidebar,
            )
          : null,
      footer: wide
          ? null
          : FBottomNavigationBar(
              index: _index,
              onChange: _select,
              children: List.generate(
                _labels.length,
                (index) => FBottomNavigationBarItem(
                  icon: Icon(_icons[index]),
                  label: Text(_labels[index]),
                ),
              ),
            ),
      child: IndexedStack(
        index: _index,
        children: [
          LibraryPage(
            library: _library,
            extensions: _extensions,
            service: _extensionService,
            details: _extensionDetails,
            downloads: _downloads,
            readDownloads: _readDownloads,
          ),
          DownloadsPage(
            downloads: _downloads,
            readDownloads: _readDownloads,
            extensions: _extensions,
            service: _extensionService,
            library: _library,
          ),
          ExtensionSearchPage(
            manager: _extensions,
            service: _extensionService,
            details: _extensionDetails,
            library: _library,
            downloads: _downloads,
            readDownloads: _readDownloads,
          ),
          _SettingsPage(
            manager: _extensions,
            downloads: _downloads,
            settings: widget.settings,
          ),
        ],
      ),
    );
  }

  void _select(int value) => setState(() => _index = value);

  void _toggleSidebar() => setState(() => _sidebarCollapsed = !_sidebarCollapsed);
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.collapsed,
    required this.onToggle,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeInOut,
    width: collapsed ? 76 : 220,
    child: ClipRect(
      child: SafeArea(
        right: false,
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Row(
              mainAxisAlignment:
                  collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                if (!collapsed)
                  Expanded(
                    child: Text(
                      'Terra',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                FButton.icon(
                  onPress: onToggle,
                  variant: FButtonVariant.ghost,
                  child: Icon(
                    collapsed
                        ? FLucideIcons.panelLeftOpen
                        : FLucideIcons.panelLeftClose,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              itemCount: _TerraHomeState._labels.length,
              itemBuilder: (context, itemIndex) {
                final selected = itemIndex == index;
                final icon = _TerraHomeState._icons[itemIndex];
                final label = _TerraHomeState._labels[itemIndex];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: collapsed
                      ? Tooltip(
                          message: label,
                          child: FButton.icon(
                            onPress: () => onSelect(itemIndex),
                            variant: FButtonVariant.ghost,
                            selected: selected,
                            child: Icon(icon),
                          ),
                        )
                      : FSidebarItem(
                          selected: selected,
                          icon: Icon(icon),
                          label: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPress: () => onSelect(itemIndex),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  ),
);
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.manager,
    required this.downloads,
    required this.settings,
  });
  final ExtensionManager manager;
  final DownloadRepository downloads;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => _Page(
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: TerraBrandHero(),
        ),
        ListenableBuilder(
          listenable: settings,
          builder: (context, _) => _SettingRow(
            icon: Icons.tune,
            title: 'General',
            detail:
                '${settings.locale == null ? 'System language' : 'English'} · ${settings.themeMode.name} · ${settings.baseColor.label} + ${settings.primaryColor.label}',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GeneralSettingsPage(settings: settings),
              ),
            ),
          ),
        ),
        _SettingRow(
          icon: Icons.play_circle_outline,
          title: 'Direct media source',
          detail: 'Open your own HLS or MP4 URL',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DirectSourcePage()),
          ),
        ),
        ListenableBuilder(
          listenable: manager,
          builder: (context, _) => _SettingRow(
            icon: Icons.extension_outlined,
            title: 'Modules',
            detail:
                '${manager.knownSources.length} known · ${manager.installed.length} installed · ${manager.activeInstalled.length} active',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ModulesPage(manager: manager),
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: downloads,
          builder: (context, _) => _SettingRow(
            icon: Icons.download_outlined,
            title: 'Downloads',
            detail:
                '${downloads.maxConcurrentDownloads} concurrent · ${downloads.wifiOnly ? 'Wi-Fi only' : 'Wi-Fi and mobile'}',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DownloadSettingsPage(downloads: downloads),
              ),
            ),
          ),
        ),
        _SettingRow(
          icon: Icons.info_outline,
          title: 'About',
          detail: 'Version, developer, and license',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
        ),
        const SizedBox(height: 20),
        FutureBuilder(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) => Text(
            '${snapshot.hasData ? 'v${snapshot.data!.version}+${snapshot.data!.buildNumber}' : 'Version…'} · Cheik Hachem',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    ),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.all(compact ? 12 : 16),
        children: [child],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: FCard(
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          minTileHeight: 62,
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          leading: Icon(icon, size: 21),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          trailing: onTap == null
              ? null
              : const Icon(Icons.chevron_right, size: 20),
          onTap: onTap,
        ),
      ),
    ),
  );
}
