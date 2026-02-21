import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_controller.dart';
import '../../core/websocket/ws_client.dart' show WSConnectionState;

/// Terminal view for executing commands and viewing output
class TerminalView extends ConsumerStatefulWidget {
  const TerminalView({super.key});

  @override
  ConsumerState<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends ConsumerState<TerminalView> {
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<String> _commandHistory = [];
  int _historyIndex = -1;

  @override
  void dispose() {
    _commandController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terminalLines = ref.watch(terminalOutputProvider);
    final isConnected = ref.watch(connectionStateProvider).value == WSConnectionState.connected;

    // Auto-scroll to bottom when new output is added
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });

    return Column(
      children: [
        _buildHeader(context),
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: terminalLines.length,
              itemBuilder: (context, index) {
                final line = terminalLines[index];
                return _buildTerminalLine(line);
              },
            ),
          ),
        ),
        _buildInputArea(context, isConnected),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Terminal',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            tooltip: 'Clear terminal',
            onPressed: () {
              ref.read(terminalOutputProvider.notifier).clear();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalLine(TerminalLine line) {
    Color textColor;
    FontWeight fontWeight = FontWeight.normal;

    switch (line.type) {
      case TerminalLineType.input:
        textColor = Colors.green.shade300;
        fontWeight = FontWeight.bold;
        break;
      case TerminalLineType.output:
        textColor = Colors.white;
        break;
      case TerminalLineType.error:
        textColor = Colors.red.shade300;
        break;
      case TerminalLineType.info:
        textColor = Colors.blue.shade300;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SelectableText(
        line.text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: textColor,
          fontWeight: fontWeight,
        ),
      ),
    );
  }

  Widget _buildInputArea(BuildContext context, bool isConnected) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          const Text(
            '\$',
            style: TextStyle(
              color: Colors.green,
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _commandController,
              enabled: isConnected,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                hintText: isConnected ? 'Enter command...' : 'Not connected',
                hintStyle: TextStyle(
                  color: Colors.grey.shade600,
                  fontFamily: 'monospace',
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: isConnected ? _executeCommand : null,
              onChanged: (value) {
                _historyIndex = -1;
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, size: 18),
            color: Colors.green.shade300,
            onPressed: isConnected && _commandController.text.isNotEmpty ? () => _executeCommand(_commandController.text) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _executeCommand(String command) async {
    if (command.trim().isEmpty) return;

    // Add to history
    _commandHistory.insert(0, command);
    if (_commandHistory.length > 100) {
      _commandHistory.removeLast();
    }
    _historyIndex = -1;

    // Clear input
    _commandController.clear();

    // Execute command
    try {
      await ref.read(appControllerProvider).executeCommand(command);
    } catch (e) {
      ref.read(terminalOutputProvider.notifier).addError('Error: $e');
    }
  }

  void _navigateHistory(bool up) {
    if (_commandHistory.isEmpty) return;

    if (up) {
      if (_historyIndex < _commandHistory.length - 1) {
        _historyIndex++;
        _commandController.text = _commandHistory[_historyIndex];
        _commandController.selection = TextSelection.fromPosition(
          TextPosition(offset: _commandController.text.length),
        );
      }
    } else {
      if (_historyIndex > 0) {
        _historyIndex--;
        _commandController.text = _commandHistory[_historyIndex];
        _commandController.selection = TextSelection.fromPosition(
          TextPosition(offset: _commandController.text.length),
        );
      } else if (_historyIndex == 0) {
        _historyIndex = -1;
        _commandController.clear();
      }
    }
  }
}
