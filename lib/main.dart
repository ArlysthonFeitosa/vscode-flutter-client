import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/workspace/workspace_explorer.dart';
import 'features/editor/code_editor_view.dart';
import 'features/settings/settings_view.dart';
import 'state/app_controller.dart';

// Import WSConnectionState
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.dark,
      home: const MainScreen(),
    );
  }
}

/// Main screen with navigation
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider).value;
    final isConnected = connectionState == WSConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VS Code Remote Client'),
        actions: [
          _buildConnectionIndicator(connectionState),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => _navigateToSettings(context),
          ),
        ],
      ),
      body: Row(
        children: [
          // Navigation rail
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: Text('Files'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.code),
                selectedIcon: Icon(Icons.code),
                label: Text('Editor'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Main content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
      floatingActionButton: !isConnected
          ? FloatingActionButton.extended(
              onPressed: () => _navigateToSettings(context),
              icon: const Icon(Icons.settings),
              label: const Text('Configure & Connect'),
            )
          : null,
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return const WorkspaceExplorer();
      case 1:
        return const CodeEditorView();
      default:
        return const SizedBox();
    }
  }

  Widget _buildConnectionIndicator(WSConnectionState? state) {
    Color color;
    IconData icon;
    String tooltip;

    switch (state) {
      case WSConnectionState.connected:
        color = Colors.green;
        icon = Icons.cloud_done;
        tooltip = 'Connected';
        break;
      case WSConnectionState.connecting:
      case WSConnectionState.authenticating:
        color = Colors.orange;
        icon = Icons.cloud_sync;
        tooltip = 'Connecting...';
        break;
      case WSConnectionState.reconnecting:
        color = Colors.orange;
        icon = Icons.cloud_sync;
        tooltip = 'Reconnecting...';
        break;
      case WSConnectionState.error:
        color = Colors.red;
        icon = Icons.cloud_off;
        tooltip = 'Connection Error';
        break;
      case WSConnectionState.disconnected:
      default:
        color = Colors.grey;
        icon = Icons.cloud_off;
        tooltip = 'Disconnected';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: tooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SettingsView(),
      ),
    );
  }
}

/// Split view for desktop layout
class SplitView extends StatelessWidget {
  final Widget left;
  final Widget right;
  final double leftWidth;

  const SplitView({
    super.key,
    required this.left,
    required this.right,
    this.leftWidth = 300,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: leftWidth,
          child: left,
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: right),
      ],
    );
  }
}
