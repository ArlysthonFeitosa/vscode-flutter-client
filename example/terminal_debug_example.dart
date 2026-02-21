import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../lib/state/app_controller.dart';

/// Simple example to test terminal event reception
/// This will help debug why terminal.output and terminal.completed events are not being received
void main() {
  runApp(
    ProviderScope(
      child: MaterialApp(
        home: TerminalDebugScreen(),
      ),
    ),
  );
}

class TerminalDebugScreen extends ConsumerStatefulWidget {
  const TerminalDebugScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<TerminalDebugScreen> createState() => _TerminalDebugScreenState();
}

class _TerminalDebugScreenState extends ConsumerState<TerminalDebugScreen> {
  final _logger = Logger();

  @override
  void initState() {
    super.initState();
    _setupDebugLogging();
  }

  void _setupDebugLogging() {
    // Listen to ALL messages from WebSocket to see what's coming in
    ref.listen(messageStreamProvider, (previous, next) {
      next.whenData((message) {
        _logger.w('🔔 MESSAGE RECEIVED: type=${message.type}, requestId=${message.requestId}');
        _logger.d('   Payload: ${message.payload}');
      });
    });

    // Listen specifically to terminal output
    ref.listen(terminalOutputProvider, (previous, next) {
      _logger.i('📺 Terminal output updated: ${next.length} lines');
      if (next.isNotEmpty) {
        _logger.d('   Last line: ${next.last.text}');
      }
    });
  }

  Future<void> _testTerminalCommand() async {
    _logger.i('🚀 Starting terminal test...');

    try {
      final controller = ref.read(appControllerProvider);

      // Test with a simple command that will produce output
      await controller.executeCommand('echo "Hello from terminal test"');

      _logger.i('✅ Command executed successfully');
    } catch (e) {
      _logger.e('❌ Command failed: $e');
    }
  }

  Future<void> _testTerminalCommandLongRunning() async {
    _logger.i('🚀 Starting long-running terminal test...');

    try {
      final controller = ref.read(appControllerProvider);

      // Test with a command that takes time
      await controller.executeCommand('sleep 2 && echo "Completed after 2 seconds"');

      _logger.i('✅ Long-running command started');
    } catch (e) {
      _logger.e('❌ Command failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final terminalLines = ref.watch(terminalOutputProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Terminal Event Debug'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          // Connection Status
          Container(
            padding: EdgeInsets.all(16),
            color: connectionState.value == WSConnectionState.connected ? Colors.green[100] : Colors.red[100],
            child: Row(
              children: [
                Icon(
                  connectionState.value == WSConnectionState.connected ? Icons.check_circle : Icons.error,
                  color: connectionState.value == WSConnectionState.connected ? Colors.green : Colors.red,
                ),
                SizedBox(width: 8),
                Text(
                  'Status: ${connectionState.value}',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Test Buttons
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    await ref.read(appControllerProvider).connect();
                  },
                  icon: Icon(Icons.connect_without_contact),
                  label: Text('Connect to VS Code Bridge'),
                ),
                SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _testTerminalCommand,
                  icon: Icon(Icons.terminal),
                  label: Text('Test Terminal (echo)'),
                ),
                SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _testTerminalCommandLongRunning,
                  icon: Icon(Icons.timer),
                  label: Text('Test Long-Running Command'),
                ),
                SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(terminalOutputProvider.notifier).clear();
                  },
                  icon: Icon(Icons.clear),
                  label: Text('Clear Terminal'),
                ),
              ],
            ),
          ),

          Divider(),

          // Terminal Output
          Expanded(
            child: Container(
              color: Colors.black,
              padding: EdgeInsets.all(8),
              child: terminalLines.isEmpty
                  ? Center(
                      child: Text(
                        'No terminal output yet.\nRun a command to see output here.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: terminalLines.length,
                      itemBuilder: (context, index) {
                        final line = terminalLines[index];
                        Color textColor;

                        switch (line.type) {
                          case TerminalLineType.input:
                            textColor = Colors.cyan;
                            break;
                          case TerminalLineType.output:
                            textColor = Colors.white;
                            break;
                          case TerminalLineType.error:
                            textColor = Colors.red;
                            break;
                          case TerminalLineType.info:
                            textColor = Colors.yellow;
                            break;
                        }

                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            line.text,
                            style: TextStyle(
                              color: textColor,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),

          // Debug Info
          Container(
            padding: EdgeInsets.all(8),
            color: Colors.grey[300],
            child: Text(
              'Debug: ${terminalLines.length} lines in terminal buffer',
              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }
}
