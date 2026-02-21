import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../core/websocket/ws_client.dart';
import '../core/models/protocol_message.dart';

// Re-export WSConnectionState for convenience
export '../core/websocket/ws_client.dart' show WSConnectionState;

// ============================================================================
// Providers
// ============================================================================

/// Logger provider
final loggerProvider = Provider<Logger>((ref) => Logger());

/// WebSocket client provider
final wsClientProvider = Provider<VSCodeWebSocketClient>((ref) {
  final config = ref.watch(connectionConfigProvider);
  final logger = ref.watch(loggerProvider);

  final client = VSCodeWebSocketClient(
    host: config.host,
    port: config.port,
    token: config.token,
    logger: logger,
  );

  ref.onDispose(() {
    client.dispose();
  });

  return client;
});

/// Connection config provider
final connectionConfigProvider = StateProvider<ConnectionConfig>((ref) {
  return ConnectionConfig(
    host: 'localhost',
    port: 8080,
    token: '',
  );
});

/// Connection state provider
final connectionStateProvider = StreamProvider<WSConnectionState>((ref) {
  final client = ref.watch(wsClientProvider);
  return client.stateStream;
});

/// Message stream provider
final messageStreamProvider = StreamProvider<ProtocolMessage>((ref) {
  final client = ref.watch(wsClientProvider);
  return client.messageStream;
});

/// Error stream provider
final errorStreamProvider = StreamProvider<String>((ref) {
  final client = ref.watch(wsClientProvider);
  return client.errorStream;
});

/// Workspace tree provider
final workspaceTreeProvider = StateNotifierProvider<WorkspaceTreeNotifier, List<FileTreeNode>>((ref) {
  return WorkspaceTreeNotifier(ref);
});

/// Open files provider
final openFilesProvider = StateNotifierProvider<OpenFilesNotifier, Map<String, OpenFile>>((ref) {
  return OpenFilesNotifier(ref);
});

/// Active file path provider
final activeFilePathProvider = StateProvider<String?>((ref) => null);

/// Terminal output provider
final terminalOutputProvider = StateNotifierProvider<TerminalOutputNotifier, List<TerminalLine>>((ref) {
  return TerminalOutputNotifier(ref);
});

// ============================================================================
// Models
// ============================================================================

/// Connection configuration
class ConnectionConfig {
  final String host;
  final int port;
  final String token;

  ConnectionConfig({
    required this.host,
    required this.port,
    required this.token,
  });

  ConnectionConfig copyWith({
    String? host,
    int? port,
    String? token,
  }) {
    return ConnectionConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
    );
  }
}

/// Open file representation
class OpenFile {
  final String path;
  final String content;
  final String languageId;
  final bool isModified;
  final DateTime lastSync;

  OpenFile({
    required this.path,
    required this.content,
    required this.languageId,
    this.isModified = false,
    DateTime? lastSync,
  }) : lastSync = lastSync ?? DateTime.now();

  OpenFile copyWith({
    String? path,
    String? content,
    String? languageId,
    bool? isModified,
    DateTime? lastSync,
  }) {
    return OpenFile(
      path: path ?? this.path,
      content: content ?? this.content,
      languageId: languageId ?? this.languageId,
      isModified: isModified ?? this.isModified,
      lastSync: lastSync ?? this.lastSync,
    );
  }
}

/// Terminal line
class TerminalLine {
  final String text;
  final TerminalLineType type;
  final DateTime timestamp;

  TerminalLine({
    required this.text,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Terminal line type
enum TerminalLineType {
  input,
  output,
  error,
  info,
}

// ============================================================================
// State Notifiers
// ============================================================================

/// Workspace tree state notifier
class WorkspaceTreeNotifier extends StateNotifier<List<FileTreeNode>> {
  final Ref ref;
  StreamSubscription<ProtocolMessage>? _messageSubscription;

  WorkspaceTreeNotifier(this.ref) : super([]) {
    _init();
  }

  void _init() {
    // Listen for workspace tree events
    _messageSubscription = ref.read(wsClientProvider).messageStream.listen((message) {
      if (message is WorkspaceTreeEvent) {
        state = message.tree;
      }
    });
  }

  /// Request workspace tree from server
  Future<void> refresh() async {
    try {
      final client = ref.read(wsClientProvider);
      final tree = await client.requestWorkspaceTree();
      state = tree;
    } catch (e) {
      ref.read(loggerProvider).e('Failed to refresh workspace tree: $e');
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}

/// Open files state notifier
class OpenFilesNotifier extends StateNotifier<Map<String, OpenFile>> {
  final Ref ref;
  StreamSubscription<ProtocolMessage>? _messageSubscription;

  // Track changes from local edits to prevent loops
  final Set<String> _locallyModifiedFiles = {};

  OpenFilesNotifier(this.ref) : super({}) {
    _init();
  }

  void _init() {
    // Listen for document events
    _messageSubscription = ref.read(wsClientProvider).messageStream.listen((message) {
      if (message is DocumentOpenedEvent) {
        _handleDocumentOpened(message);
      } else if (message is DocumentChangedEvent) {
        _handleDocumentChanged(message);
      } else if (message is DocumentSavedEvent) {
        _handleDocumentSaved(message);
      } else if (message is DocumentClosedEvent) {
        _handleDocumentClosed(message);
      }
    });
  }

  void _handleDocumentOpened(DocumentOpenedEvent event) {
    // Only update if we don't already have this file or if it's not locally modified
    if (!state.containsKey(event.fileName) || !_locallyModifiedFiles.contains(event.fileName)) {
      state = {
        ...state,
        event.fileName: OpenFile(
          path: event.fileName,
          content: event.content,
          languageId: event.languageId,
        ),
      };
    }
  }

  void _handleDocumentChanged(DocumentChangedEvent event) {
    // Only update if the change came from VS Code (not from us)
    if (!_locallyModifiedFiles.contains(event.fileName) && event.contentAfterChange != null) {
      final existing = state[event.fileName];
      if (existing != null) {
        state = {
          ...state,
          event.fileName: existing.copyWith(
            content: event.contentAfterChange,
            lastSync: DateTime.now(),
          ),
        };
      }
    }
  }

  void _handleDocumentSaved(DocumentSavedEvent event) {
    final existing = state[event.fileName];
    if (existing != null) {
      state = {
        ...state,
        event.fileName: existing.copyWith(
          content: event.content,
          isModified: false,
          lastSync: DateTime.now(),
        ),
      };
      _locallyModifiedFiles.remove(event.fileName);
    }
  }

  void _handleDocumentClosed(DocumentClosedEvent event) {
    final newState = Map<String, OpenFile>.from(state);
    newState.remove(event.fileName);
    state = newState;
    _locallyModifiedFiles.remove(event.fileName);
  }

  /// Open a file
  Future<void> openFile(String path) async {
    try {
      final client = ref.read(wsClientProvider);

      // Request to open file in VS Code
      await client.openFile(path, preview: false);

      // Read file content
      final content = await client.readFile(path);

      // Determine language ID from extension
      final languageId = _getLanguageIdFromPath(path);

      state = {
        ...state,
        path: OpenFile(
          path: path,
          content: content,
          languageId: languageId,
        ),
      };

      // Set as active file
      ref.read(activeFilePathProvider.notifier).state = path;
    } catch (e) {
      ref.read(loggerProvider).e('Failed to open file: $e');
      rethrow;
    }
  }

  /// Update file content locally
  void updateContent(String path, String content) {
    final existing = state[path];
    if (existing != null) {
      _locallyModifiedFiles.add(path);
      state = {
        ...state,
        path: existing.copyWith(
          content: content,
          isModified: true,
        ),
      };
    }
  }

  /// Save file to VS Code
  Future<void> saveFile(String path) async {
    try {
      final file = state[path];
      if (file == null) return;

      final client = ref.read(wsClientProvider);
      await client.writeFile(path, file.content);

      // Mark as not modified
      state = {
        ...state,
        path: file.copyWith(
          isModified: false,
          lastSync: DateTime.now(),
        ),
      };
      _locallyModifiedFiles.remove(path);
    } catch (e) {
      ref.read(loggerProvider).e('Failed to save file: $e');
      rethrow;
    }
  }

  /// Close a file
  void closeFile(String path) {
    final newState = Map<String, OpenFile>.from(state);
    newState.remove(path);
    state = newState;
    _locallyModifiedFiles.remove(path);

    // Clear active file if it was this one
    if (ref.read(activeFilePathProvider) == path) {
      ref.read(activeFilePathProvider.notifier).state = null;
    }
  }

  String _getLanguageIdFromPath(String path) {
    final ext = path.split('.').last.toLowerCase();

    const extensionMap = {
      'dart': 'dart',
      'js': 'javascript',
      'ts': 'typescript',
      'jsx': 'javascriptreact',
      'tsx': 'typescriptreact',
      'py': 'python',
      'java': 'java',
      'kt': 'kotlin',
      'swift': 'swift',
      'go': 'go',
      'rs': 'rust',
      'c': 'c',
      'cpp': 'cpp',
      'h': 'c',
      'hpp': 'cpp',
      'cs': 'csharp',
      'rb': 'ruby',
      'php': 'php',
      'html': 'html',
      'css': 'css',
      'scss': 'scss',
      'json': 'json',
      'xml': 'xml',
      'yaml': 'yaml',
      'yml': 'yaml',
      'md': 'markdown',
      'sh': 'shellscript',
      'sql': 'sql',
    };

    return extensionMap[ext] ?? 'plaintext';
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}

/// Terminal output state notifier
class TerminalOutputNotifier extends StateNotifier<List<TerminalLine>> {
  final Ref ref;
  StreamSubscription<ProtocolMessage>? _messageSubscription;

  TerminalOutputNotifier(this.ref) : super([]) {
    _init();
  }

  void _init() {
    // Listen for terminal events from WebSocket
    final logger = ref.read(loggerProvider);
    logger.i('TerminalOutputNotifier: Initializing terminal event listener');

    _messageSubscription = ref.read(wsClientProvider).messageStream.listen((message) {
      logger.d('TerminalOutputNotifier: Received message type: ${message.type}');

      if (message is TerminalOutputEvent) {
        logger.i('TerminalOutputNotifier: Processing TerminalOutputEvent');
        _handleTerminalOutput(message);
      } else if (message is TerminalCompletedEvent) {
        logger.i('TerminalOutputNotifier: Processing TerminalCompletedEvent');
        _handleTerminalCompleted(message);
      }
    });
  }

  void _handleTerminalOutput(TerminalOutputEvent event) {
    // Handle real-time terminal output
    final logger = ref.read(loggerProvider);
    final text = event.data;

    logger.d('Terminal output from ${event.terminalName}: $text');

    // Check if it's stderr output
    if (text.startsWith('[STDERR]')) {
      addError(text.substring(8)); // Remove [STDERR] prefix
    } else {
      addOutput(text);
    }
  }

  void _handleTerminalCompleted(TerminalCompletedEvent event) {
    // Add completion info
    final logger = ref.read(loggerProvider);
    logger.i('Terminal completed: ${event.terminalName} with exit code ${event.exitCode}');

    if (event.exitCode == 0) {
      addInfo('Process completed successfully (exit code: ${event.exitCode})');
    } else {
      addError('Process failed with exit code: ${event.exitCode}');
    }

    // Optionally add accumulated output if not already shown via terminal.output events
    // This is useful as a fallback or summary
  }

  /// Add output line
  void addOutput(String text) {
    if (text.isEmpty) return;
    state = [
      ...state,
      TerminalLine(text: text, type: TerminalLineType.output),
    ];
  }

  /// Add error line
  void addError(String text) {
    if (text.isEmpty) return;
    state = [
      ...state,
      TerminalLine(text: text, type: TerminalLineType.error),
    ];
  }

  /// Add input line
  void addInput(String text) {
    if (text.isEmpty) return;
    state = [
      ...state,
      TerminalLine(text: text, type: TerminalLineType.input),
    ];
  }

  /// Add info line
  void addInfo(String text) {
    if (text.isEmpty) return;
    state = [
      ...state,
      TerminalLine(text: text, type: TerminalLineType.info),
    ];
  }

  /// Clear terminal
  void clear() {
    state = [];
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}

// ============================================================================
// Controller Actions
// ============================================================================

/// App controller for global actions
class AppController {
  final Ref ref;

  AppController(this.ref);

  /// Connect to WebSocket server
  Future<void> connect() async {
    final client = ref.read(wsClientProvider);
    await client.connect();
  }

  /// Disconnect from WebSocket server
  Future<void> disconnect() async {
    final client = ref.read(wsClientProvider);
    await client.disconnect();
  }

  /// Update connection configuration
  void updateConfig(ConnectionConfig config) {
    ref.read(connectionConfigProvider.notifier).state = config;
  }

  /// Execute shell command
  Future<void> executeCommand(String command, {String? cwd}) async {
    try {
      final client = ref.read(wsClientProvider);
      final terminalNotifier = ref.read(terminalOutputProvider.notifier);

      // Add input to terminal
      terminalNotifier.addInput('\$ $command');

      // Execute command with visible terminal for real-time output
      // When useVisibleTerminal is true, output will be received via
      // terminal.output and terminal.completed events
      final result = await client.runShellCommand(
        command,
        cwd: cwd,
        captureOutput: true,
        useVisibleTerminal: true,
        terminalName: 'VS Code Remote Client Terminal',
        reuseTerminal: true,
      );

      // The response when using visible terminal only confirms execution started
      // Actual output comes through terminal.output events (handled by TerminalOutputNotifier)
      // and completion info comes through terminal.completed events

      // Handle immediate response (for visible terminal, this is just confirmation)
      final message = result['message'] as String?;
      if (message != null && message.isNotEmpty) {
        terminalNotifier.addInfo(message);
      }

      // For background commands (when useVisibleTerminal: false), handle output here
      if (result.containsKey('stdout') || result.containsKey('stderr')) {
        final stdout = result['stdout'] as String? ?? '';
        final stderr = result['stderr'] as String? ?? '';
        final exitCode = result['exitCode'] as int?;

        if (stdout.isNotEmpty) {
          terminalNotifier.addOutput(stdout);
        }

        if (stderr.isNotEmpty) {
          terminalNotifier.addError(stderr);
        }

        if (exitCode != null && exitCode != 0) {
          terminalNotifier.addError('Exit code: $exitCode');
        }
      }
    } catch (e) {
      ref.read(terminalOutputProvider.notifier).addError('Error: $e');
      rethrow;
    }
  }
}

/// App controller provider
final appControllerProvider = Provider<AppController>((ref) {
  return AppController(ref);
});
