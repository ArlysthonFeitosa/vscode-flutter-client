import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/vscode_theme.dart';
import 'features/workspace/workspace_explorer.dart';
import 'features/editor/code_editor_view.dart';
import 'features/settings/settings_view.dart';
import 'state/app_controller.dart';
import 'core/websocket/ws_client.dart' show WSConnectionState;

void main() {
  runApp(
    const ProviderScope(
      child: VSCodeRemoteClientApp(),
    ),
  );
}

/// Main application widget
class VSCodeRemoteClientApp extends StatelessWidget {
  const VSCodeRemoteClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VS Code Remote Client',
      debugShowCheckedModeBanner: false,
      theme: vsCodeDarkTheme(),
      darkTheme: vsCodeDarkTheme(),
      themeMode: ThemeMode.dark,
      home: const MainScreen(),
    );
  }
}

/// Activity bar item enum
enum ActivityBarItem {
  explorer,
  search,
  settings,
}

/// Main screen with VS Code-like layout
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  ActivityBarItem _selectedActivity = ActivityBarItem.explorer;
  bool _sidebarVisible = true;
  bool _autoConnectAttempted = false;

  @override
  void initState() {
    super.initState();
    _initAutoConnect();
  }

  Future<void> _initAutoConnect() async {
    if (_autoConnectAttempted) return;
    _autoConnectAttempted = true;

    // Load saved settings and auto-connect
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString('ws_host') ?? 'localhost';
      final port = prefs.getInt('ws_port') ?? 8080;
      final token = prefs.getString('ws_token') ?? 'your-secret-token-here';

      // Update config
      ref.read(connectionConfigProvider.notifier).state = ConnectionConfig(
        host: host,
        port: port,
        token: token,
      );

      // Auto connect
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        ref.read(appControllerProvider).connect();
      }
    } catch (e) {
      debugPrint('Auto-connect failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider).value;
    final isConnected = connectionState == WSConnectionState.connected;
    final openFiles = ref.watch(openFilesProvider);
    final activeFilePath = ref.watch(activeFilePathProvider);

    // Determine if we're on mobile
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      drawer: isMobile ? _buildMobileDrawer() : null,
      body: Column(
        children: [
          // Tab bar (only show if files are open)
          if (openFiles.isNotEmpty) _buildTabBar(openFiles, activeFilePath),
          // Main content
          Expanded(
            child: Row(
              children: [
                // Activity Bar (left icon bar)
                if (!isMobile) _buildActivityBar(),
                // Sidebar
                if (!isMobile && _sidebarVisible) _buildSidebar(),
                // Editor area
                Expanded(
                  child: _buildEditorArea(),
                ),
              ],
            ),
          ),
          // Status bar
          _buildStatusBar(connectionState, isConnected),
        ],
      ),
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      backgroundColor: VSCodeColors.sideBarBackground,
      child: SafeArea(
        child: Column(
          children: [
            _buildSidebarHeader(),
            Expanded(child: _buildSidebarContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityBar() {
    return Container(
      width: 48,
      color: VSCodeColors.activityBarBackground,
      child: Column(
        children: [
          _buildActivityBarItem(
            icon: Icons.description_outlined,
            selectedIcon: Icons.folder,
            item: ActivityBarItem.explorer,
            tooltip: 'Explorer',
          ),
          _buildActivityBarItem(
            icon: Icons.search,
            selectedIcon: Icons.search,
            item: ActivityBarItem.search,
            tooltip: 'Search',
          ),
          const Spacer(),
          _buildActivityBarItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            item: ActivityBarItem.settings,
            tooltip: 'Settings',
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildActivityBarItem({
    required IconData icon,
    required IconData selectedIcon,
    required ActivityBarItem item,
    required String tooltip,
  }) {
    final isSelected = _selectedActivity == item;
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        onTap: () {
          if (item == ActivityBarItem.settings) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const SettingsView()),
            );
          } else {
            setState(() {
              if (_selectedActivity == item) {
                _sidebarVisible = !_sidebarVisible;
              } else {
                _selectedActivity = item;
                _sidebarVisible = true;
              }
            });
          }
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected ? VSCodeColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Icon(
            isSelected ? selectedIcon : icon,
            color: isSelected
                ? VSCodeColors.activityBarForeground
                : VSCodeColors.activityBarInactiveForeground,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: VSCodeColors.sideBarBackground,
      child: Column(
        children: [
          _buildSidebarHeader(),
          Expanded(child: _buildSidebarContent()),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    String title;
    switch (_selectedActivity) {
      case ActivityBarItem.explorer:
        title = 'EXPLORER';
        break;
      case ActivityBarItem.search:
        title = 'SEARCH';
        break;
      case ActivityBarItem.settings:
        title = 'SETTINGS';
        break;
    }

    return Container(
      height: 35,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          color: VSCodeColors.sideBarForeground,
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSidebarContent() {
    switch (_selectedActivity) {
      case ActivityBarItem.explorer:
        return const WorkspaceExplorer();
      case ActivityBarItem.search:
        return _buildSearchPanel();
      case ActivityBarItem.settings:
        return const SizedBox();
    }
  }

  Widget _buildSearchPanel() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search',
              hintStyle: TextStyle(
                  color: VSCodeColors.sideBarForeground.withOpacity(0.6)),
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          const Expanded(
            child: Center(
              child: Text(
                'Search functionality\ncoming soon',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: VSCodeColors.sideBarForeground,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(Map<String, OpenFile> openFiles, String? activeFilePath) {
    return Container(
      height: 35,
      color: VSCodeColors.tabInactiveBackground,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: openFiles.entries.map((entry) {
                final file = entry.value;
                final isActive = entry.key == activeFilePath;
                return _buildTab(file, isActive);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(OpenFile file, bool isActive) {
    final fileName = file.path.split('/').last.split('\\').last;

    return GestureDetector(
      onTap: () {
        ref.read(activeFilePathProvider.notifier).state = file.path;
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? VSCodeColors.tabActiveBackground
              : VSCodeColors.tabInactiveBackground,
          border: Border(
            top: BorderSide(
              color: isActive
                  ? VSCodeColors.tabActiveBorderTop
                  : Colors.transparent,
              width: 1,
            ),
            right: const BorderSide(
              color: VSCodeColors.tabBorder,
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getFileIcon(fileName),
              size: 16,
              color: _getFileIconColor(fileName),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                fileName,
                style: TextStyle(
                  color: isActive
                      ? VSCodeColors.tabActiveForeground
                      : VSCodeColors.tabInactiveForeground,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (file.isModified)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 6),
                decoration: const BoxDecoration(
                  color: VSCodeColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => _closeTab(file.path),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: isActive
                      ? VSCodeColors.tabActiveForeground
                      : VSCodeColors.tabInactiveForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _closeTab(String path) {
    final file = ref.read(openFilesProvider)[path];
    if (file?.isModified ?? false) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text('Do you want to save changes before closing?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(openFilesProvider.notifier).closeFile(path);
              },
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await ref.read(openFilesProvider.notifier).saveFile(path);
                ref.read(openFilesProvider.notifier).closeFile(path);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } else {
      ref.read(openFilesProvider.notifier).closeFile(path);
    }
  }

  Widget _buildEditorArea() {
    return const CodeEditorView();
  }

  Widget _buildStatusBar(WSConnectionState? state, bool isConnected) {
    Color bgColor;
    String statusText;
    IconData statusIcon;

    switch (state) {
      case WSConnectionState.connected:
        bgColor = VSCodeColors.statusBarBackground;
        statusText = 'Connected';
        statusIcon = Icons.cloud_done;
        break;
      case WSConnectionState.connecting:
      case WSConnectionState.authenticating:
        bgColor = VSCodeColors.warningForeground;
        statusText = 'Connecting...';
        statusIcon = Icons.cloud_sync;
        break;
      case WSConnectionState.reconnecting:
        bgColor = VSCodeColors.warningForeground;
        statusText = 'Reconnecting...';
        statusIcon = Icons.cloud_sync;
        break;
      case WSConnectionState.error:
        bgColor = VSCodeColors.errorForeground;
        statusText = 'Error';
        statusIcon = Icons.cloud_off;
        break;
      case WSConnectionState.disconnected:
      default:
        bgColor = VSCodeColors.statusBarDisconnected;
        statusText = 'Disconnected';
        statusIcon = Icons.cloud_off;
        break;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Container(
      height: 22,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (isMobile)
            Builder(
              builder: (context) => InkWell(
                onTap: () => Scaffold.of(context).openDrawer(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.menu, size: 16, color: Colors.white),
                ),
              ),
            ),
          Icon(statusIcon, size: 14, color: VSCodeColors.statusBarForeground),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: const TextStyle(
              color: VSCodeColors.statusBarForeground,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          if (!isConnected)
            InkWell(
              onTap: () => ref.read(appControllerProvider).connect(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Connect',
                  style: TextStyle(
                    color: VSCodeColors.statusBarForeground,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsView()),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.settings,
                  size: 14, color: VSCodeColors.statusBarForeground),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return Icons.code;
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
        return Icons.javascript;
      case 'json':
        return Icons.data_object;
      case 'yaml':
      case 'yml':
        return Icons.settings;
      case 'md':
        return Icons.article;
      case 'html':
      case 'css':
      case 'scss':
        return Icons.web;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return Colors.blue;
      case 'js':
      case 'ts':
        return Colors.yellow.shade700;
      case 'json':
        return Colors.orange;
      case 'md':
        return Colors.purple;
      case 'html':
        return Colors.red;
      case 'css':
      case 'scss':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
