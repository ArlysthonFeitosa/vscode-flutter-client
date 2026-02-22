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
    token: 'your-secret-token-here',
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
final workspaceTreeProvider =
    StateNotifierProvider<WorkspaceTreeNotifier, List<FileTreeNode>>((ref) {
  return WorkspaceTreeNotifier(ref);
});

/// Open files provider
final openFilesProvider =
    StateNotifierProvider<OpenFilesNotifier, Map<String, OpenFile>>((ref) {
  return OpenFilesNotifier(ref);
});

/// Active file path provider
final activeFilePathProvider = StateProvider<String?>((ref) => null);

/// Workspace folders provider
final workspaceFoldersProvider =
    StateNotifierProvider<WorkspaceFoldersNotifier, List<WorkspaceFolder>>(
        (ref) {
  return WorkspaceFoldersNotifier(ref);
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
    _messageSubscription =
        ref.read(wsClientProvider).messageStream.listen((message) {
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

/// Workspace folders state notifier
class WorkspaceFoldersNotifier extends StateNotifier<List<WorkspaceFolder>> {
  final Ref ref;
  StreamSubscription<ProtocolMessage>? _messageSubscription;

  WorkspaceFoldersNotifier(this.ref) : super([]) {
    _init();
  }

  void _init() {
    // Listen for workspace changed events
    _messageSubscription =
        ref.read(wsClientProvider).messageStream.listen((message) {
      if (message is WorkspaceChangedEvent) {
        state = message.workspaceFolders;
      }
    });
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
    _messageSubscription =
        ref.read(wsClientProvider).messageStream.listen((message) {
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
    if (!state.containsKey(event.fileName) ||
        !_locallyModifiedFiles.contains(event.fileName)) {
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
    if (!_locallyModifiedFiles.contains(event.fileName) &&
        event.contentAfterChange != null) {
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
}

/// App controller provider
final appControllerProvider = Provider<AppController>((ref) {
  return AppController(ref);
});
