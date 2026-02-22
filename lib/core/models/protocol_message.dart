/// Base protocol message structure
/// All WebSocket messages follow this format
abstract class ProtocolMessage {
  final String type;
  final String? requestId;
  final Map<String, dynamic>? payload;

  const ProtocolMessage({
    required this.type,
    this.requestId,
    this.payload,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        if (requestId != null) 'requestId': requestId,
        if (payload != null) 'payload': payload,
      };

  factory ProtocolMessage.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final requestId = json['requestId'] as String?;
    final payload = json['payload'] as Map<String, dynamic>?;

    // Route to specific message types
    switch (type) {
      case 'response':
        return ResponseMessage.fromJson(json);
      case 'pong':
        return PongMessage.fromJson(json);
      case 'document.opened':
        return DocumentOpenedEvent.fromJson(json);
      case 'document.changed':
        return DocumentChangedEvent.fromJson(json);
      case 'document.saved':
        return DocumentSavedEvent.fromJson(json);
      case 'document.closed':
        return DocumentClosedEvent.fromJson(json);
      case 'workspace.changed':
        return WorkspaceChangedEvent.fromJson(json);
      case 'workspace.tree':
        return WorkspaceTreeEvent.fromJson(json);
      default:
        return UnknownMessage(
            type: type, requestId: requestId, payload: payload);
    }
  }
}

/// Unknown message type for graceful degradation
class UnknownMessage extends ProtocolMessage {
  const UnknownMessage({
    required super.type,
    super.requestId,
    super.payload,
  });
}

/// Generic response message
class ResponseMessage extends ProtocolMessage {
  final bool success;
  final String? error;

  const ResponseMessage({
    required this.success,
    required String super.requestId,
    super.payload,
    this.error,
  }) : super(type: 'response');

  factory ResponseMessage.fromJson(Map<String, dynamic> json) {
    return ResponseMessage(
      success: json['success'] as bool,
      requestId: json['requestId'] as String,
      payload: json['payload'] as Map<String, dynamic>?,
      error: json['error'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'requestId': requestId,
        'success': success,
        if (payload != null) 'payload': payload,
        if (error != null) 'error': error,
      };
}

/// Pong response to ping
class PongMessage extends ProtocolMessage {
  final int timestamp;

  const PongMessage({
    required String super.requestId,
    required this.timestamp,
  }) : super(type: 'pong');

  factory PongMessage.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>;
    return PongMessage(
      requestId: json['requestId'] as String,
      timestamp: payload['timestamp'] as int,
    );
  }
}

// ============================================================================
// REQUEST MESSAGES (Client → VS Code)
// ============================================================================

/// Authentication request
class AuthRequest extends ProtocolMessage {
  AuthRequest({
    required String requestId,
    required String token,
  }) : super(
          type: 'auth',
          requestId: requestId,
          payload: {'token': token},
        );
}

/// Ping request
class PingRequest extends ProtocolMessage {
  PingRequest({required String requestId})
      : super(type: 'ping', requestId: requestId);
}

/// Execute VS Code command
class ExecuteCommandRequest extends ProtocolMessage {
  ExecuteCommandRequest({
    required String requestId,
    required String command,
    List<dynamic>? args,
  }) : super(
          type: 'executeCommand',
          requestId: requestId,
          payload: {
            'command': command,
            if (args != null) 'args': args,
          },
        );
}

/// Write file request
class WriteFileRequest extends ProtocolMessage {
  WriteFileRequest({
    required String requestId,
    required String path,
    required String content,
    bool? createDirectories,
  }) : super(
          type: 'writeFile',
          requestId: requestId,
          payload: {
            'path': path,
            'content': content,
            if (createDirectories != null)
              'createDirectories': createDirectories,
          },
        );
}

/// Read file request
class ReadFileRequest extends ProtocolMessage {
  ReadFileRequest({
    required String requestId,
    required String path,
  }) : super(
          type: 'readFile',
          requestId: requestId,
          payload: {'path': path},
        );
}

/// Open file request
class OpenFileRequest extends ProtocolMessage {
  OpenFileRequest({
    required String requestId,
    required String path,
    bool? preview,
    int? viewColumn,
  }) : super(
          type: 'openFile',
          requestId: requestId,
          payload: {
            'path': path,
            if (preview != null) 'preview': preview,
            if (viewColumn != null) 'viewColumn': viewColumn,
          },
        );
}

/// Save file request
class SaveFileRequest extends ProtocolMessage {
  SaveFileRequest({
    required String requestId,
    String? path,
  }) : super(
          type: 'saveFile',
          requestId: requestId,
          payload: path != null ? {'path': path} : null,
        );
}

/// Delete file request
class DeleteFileRequest extends ProtocolMessage {
  DeleteFileRequest({
    required String requestId,
    required String path,
    bool? recursive,
  }) : super(
          type: 'deleteFile',
          requestId: requestId,
          payload: {
            'path': path,
            if (recursive != null) 'recursive': recursive,
          },
        );
}

/// Create directory request
class CreateDirectoryRequest extends ProtocolMessage {
  CreateDirectoryRequest({
    required String requestId,
    required String path,
  }) : super(
          type: 'createDirectory',
          requestId: requestId,
          payload: {'path': path},
        );
}

/// Run shell command request
class RunShellCommandRequest extends ProtocolMessage {
  RunShellCommandRequest({
    required String requestId,
    required String command,
    String? cwd,
    bool? captureOutput,
  }) : super(
          type: 'runShellCommand',
          requestId: requestId,
          payload: {
            'command': command,
            if (cwd != null) 'cwd': cwd,
            if (captureOutput != null) 'captureOutput': captureOutput,
          },
        );
}

/// Request workspace tree
class RequestWorkspaceTreeRequest extends ProtocolMessage {
  RequestWorkspaceTreeRequest({
    required String requestId,
    bool? includeHidden,
    int? maxDepth,
  }) : super(
          type: 'requestWorkspaceTree',
          requestId: requestId,
          payload: {
            if (includeHidden != null) 'includeHidden': includeHidden,
            if (maxDepth != null) 'maxDepth': maxDepth,
          },
        );
}

// ============================================================================
// EVENT MESSAGES (VS Code → Client)
// ============================================================================

/// Document opened event
class DocumentOpenedEvent extends ProtocolMessage {
  final String uri;
  final String fileName;
  final String languageId;
  final int lineCount;
  final String content;

  const DocumentOpenedEvent({
    required this.uri,
    required this.fileName,
    required this.languageId,
    required this.lineCount,
    required this.content,
  }) : super(type: 'document.opened');

  factory DocumentOpenedEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>;
    return DocumentOpenedEvent(
      uri: payload['uri'] as String,
      fileName: payload['fileName'] as String,
      languageId: payload['languageId'] as String,
      lineCount: payload['lineCount'] as int,
      content: payload['content'] as String,
    );
  }
}

/// Document changed event
class DocumentChangedEvent extends ProtocolMessage {
  final String uri;
  final String fileName;
  final List<TextChange> changes;
  final String? contentAfterChange;

  const DocumentChangedEvent({
    required this.uri,
    required this.fileName,
    required this.changes,
    this.contentAfterChange,
  }) : super(type: 'document.changed');

  factory DocumentChangedEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>;
    final changesJson = payload['changes'] as List<dynamic>;

    return DocumentChangedEvent(
      uri: payload['uri'] as String,
      fileName: payload['fileName'] as String,
      changes: changesJson
          .map((c) => TextChange.fromJson(c as Map<String, dynamic>))
          .toList(),
      contentAfterChange: payload['contentAfterChange'] as String?,
    );
  }
}

/// Document saved event
class DocumentSavedEvent extends ProtocolMessage {
  final String uri;
  final String fileName;
  final String content;

  const DocumentSavedEvent({
    required this.uri,
    required this.fileName,
    required this.content,
  }) : super(type: 'document.saved');

  factory DocumentSavedEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>;
    return DocumentSavedEvent(
      uri: payload['uri'] as String,
      fileName: payload['fileName'] as String,
      content: payload['content'] as String,
    );
  }
}

/// Document closed event
class DocumentClosedEvent extends ProtocolMessage {
  final String uri;
  final String fileName;

  const DocumentClosedEvent({
    required this.uri,
    required this.fileName,
  }) : super(type: 'document.closed');

  factory DocumentClosedEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>;
    return DocumentClosedEvent(
      uri: payload['uri'] as String,
      fileName: payload['fileName'] as String,
    );
  }
}

/// Workspace changed event
class WorkspaceChangedEvent extends ProtocolMessage {
  final List<WorkspaceFolder> workspaceFolders;

  const WorkspaceChangedEvent({
    required this.workspaceFolders,
  }) : super(type: 'workspace.changed');

  factory WorkspaceChangedEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>;
    final foldersJson = payload['workspaceFolders'] as List<dynamic>;

    return WorkspaceChangedEvent(
      workspaceFolders: foldersJson
          .map((f) => WorkspaceFolder.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Workspace tree event
class WorkspaceTreeEvent extends ProtocolMessage {
  final List<FileTreeNode> tree;

  const WorkspaceTreeEvent({
    required this.tree,
  }) : super(type: 'workspace.tree');

  factory WorkspaceTreeEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>;
    final treeJson = payload['tree'] as List<dynamic>;

    return WorkspaceTreeEvent(
      tree: treeJson
          .map((n) => FileTreeNode.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ============================================================================
// HELPER MODELS
// ============================================================================

/// Text change representation
class TextChange {
  final TextRange range;
  final String text;

  const TextChange({
    required this.range,
    required this.text,
  });

  factory TextChange.fromJson(Map<String, dynamic> json) {
    return TextChange(
      range: TextRange.fromJson(json['range'] as Map<String, dynamic>),
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'range': range.toJson(),
        'text': text,
      };
}

/// Text range (start and end positions)
class TextRange {
  final Position start;
  final Position end;

  const TextRange({
    required this.start,
    required this.end,
  });

  factory TextRange.fromJson(Map<String, dynamic> json) {
    return TextRange(
      start: Position.fromJson(json['start'] as Map<String, dynamic>),
      end: Position.fromJson(json['end'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'start': start.toJson(),
        'end': end.toJson(),
      };
}

/// Position in a document
class Position {
  final int line;
  final int character;

  const Position({
    required this.line,
    required this.character,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      line: json['line'] as int,
      character: json['character'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'line': line,
        'character': character,
      };
}

/// Workspace folder
class WorkspaceFolder {
  final String uri;
  final String name;
  final int index;

  const WorkspaceFolder({
    required this.uri,
    required this.name,
    required this.index,
  });

  factory WorkspaceFolder.fromJson(Map<String, dynamic> json) {
    return WorkspaceFolder(
      uri: json['uri'] as String,
      name: json['name'] as String,
      index: json['index'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        'index': index,
      };
}

/// File tree node
class FileTreeNode {
  final String name;
  final String path;
  final FileNodeType type;
  final List<FileTreeNode>? children;

  const FileTreeNode({
    required this.name,
    required this.path,
    required this.type,
    this.children,
  });

  factory FileTreeNode.fromJson(Map<String, dynamic> json) {
    final childrenJson = json['children'] as List<dynamic>?;

    return FileTreeNode(
      name: json['name'] as String,
      path: json['path'] as String,
      type: FileNodeType.fromString(json['type'] as String),
      children: childrenJson
          ?.map((c) => FileTreeNode.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': type.value,
        if (children != null)
          'children': children!.map((c) => c.toJson()).toList(),
      };

  bool get isDirectory => type == FileNodeType.directory;
  bool get isFile => type == FileNodeType.file;
}

/// File node type enum
enum FileNodeType {
  file('file'),
  directory('directory');

  final String value;
  const FileNodeType(this.value);

  factory FileNodeType.fromString(String value) {
    return FileNodeType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => FileNodeType.file,
    );
  }
}
