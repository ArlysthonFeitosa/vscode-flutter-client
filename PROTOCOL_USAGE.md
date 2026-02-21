# Protocol Usage Documentation

This document explains how each event and command from the VS Code WebSocket Bridge PROTOCOL.md specification was implemented in the Flutter application.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Request/Response System](#requestresponse-system)
3. [Events Implementation](#events-implementation)
4. [Commands Implementation](#commands-implementation)
5. [Synchronization Strategy](#synchronization-strategy)
6. [Error Handling](#error-handling)

---

## Architecture Overview

### Protocol Layer Structure

```
┌─────────────────────────────────────┐
│      UI Layer (Widgets)             │
├─────────────────────────────────────┤
│  State Management (Riverpod)        │
├─────────────────────────────────────┤
│  Business Logic (Notifiers)         │
├─────────────────────────────────────┤
│  WebSocket Client (ws_client.dart)  │
├─────────────────────────────────────┤
│  Protocol Models (protocol_message) │
├─────────────────────────────────────┤
│  Network (web_socket_channel)       │
└─────────────────────────────────────┘
```

### Type-Safe Message Routing

All messages are strongly typed using Dart classes. The `ProtocolMessage.fromJson()` factory automatically routes incoming messages to their specific types:

```dart
factory ProtocolMessage.fromJson(Map<String, dynamic> json) {
  final type = json['type'] as String;

  switch (type) {
    case 'response':
      return ResponseMessage.fromJson(json);
    case 'document.opened':
      return DocumentOpenedEvent.fromJson(json);
    // ... etc
  }
}
```

**Location**: `lib/core/models/protocol_message.dart`

---

## Request/Response System

### Request ID Management

Every request sent to VS Code includes a unique UUID for correlation:

```dart
String generateRequestId() => _uuid.v4();
```

### Pending Request Tracking

```dart
// Track pending requests
final Map<String, Completer<ResponseMessage>> _pendingRequests = {};
final Map<String, Timer> _requestTimeouts = {};

// Send request
Future<ResponseMessage> sendRequest(ProtocolMessage request) async {
  final completer = Completer<ResponseMessage>();
  _pendingRequests[request.requestId!] = completer;

  // Set timeout
  final timeoutTimer = Timer(timeout, () {
    _pendingRequests.remove(request.requestId);
    completer.completeError('Request timeout');
  });

  _sendMessage(request);
  return completer.future;
}
```

### Response Handling

When a response arrives, it's matched to the pending request:

```dart
void _handleMessage(dynamic data) {
  final message = ProtocolMessage.fromJson(json);

  if (message is ResponseMessage && message.requestId != null) {
    final completer = _pendingRequests.remove(message.requestId);
    final timer = _requestTimeouts.remove(message.requestId);
    timer?.cancel();

    completer?.complete(message);
  }

  _messageController.add(message);
}
```

**Location**: `lib/core/websocket/ws_client.dart`

---

## Events Implementation

### 1. Authentication (`auth`)

**Protocol Spec**: Client → Server

**Request Format**:

```json
{
    "type": "auth",
    "requestId": "uuid",
    "payload": {
        "token": "secret-token"
    }
}
```

**Implementation**:

```dart
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
```

**Authentication Flow**:

1. Connection established → `_authenticate()` called
2. `AuthRequest` sent with token
3. Response received with `clientId` if successful
4. Connection state updated to `connected`
5. If failed, disconnect and show error

**Location**: `lib/core/websocket/ws_client.dart` (lines 218-244)

---

### 2. Ping/Pong (`ping`)

**Protocol Spec**: Keep-alive mechanism

**Request Format**:

```json
{
    "type": "ping",
    "requestId": "uuid"
}
```

**Response Format**:

```json
{
    "type": "pong",
    "requestId": "uuid",
    "payload": {
        "timestamp": 1645564800000
    }
}
```

**Implementation**:

Automatic ping every 30 seconds:

```dart
void _startPingTimer() {
  _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
    if (isConnected) {
      _sendPing();
    }
  });
}

void _sendPing() {
  final ping = PingRequest(requestId: generateRequestId());
  sendRequest(ping).then((response) {
    logger.d('Ping successful');
  }).catchError((error) {
    logger.w('Ping failed: $error');
  });
}
```

**Location**: `lib/core/websocket/ws_client.dart` (lines 367-389)

---

### 3. Document Opened (`document.opened`)

**Protocol Spec**: Server → Client (Event)

**Event Format**:

```json
{
    "type": "document.opened",
    "payload": {
        "uri": "file:///path/to/file.ts",
        "fileName": "/path/to/file.ts",
        "languageId": "typescript",
        "lineCount": 42,
        "content": "..."
    }
}
```

**Implementation**:

**Model**:

```dart
class DocumentOpenedEvent extends ProtocolMessage {
  final String uri;
  final String fileName;
  final String languageId;
  final int lineCount;
  final String content;

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
```

**Handler**:

```dart
void _handleDocumentOpened(DocumentOpenedEvent event) {
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
```

**Listener Setup**:

```dart
_messageSubscription = wsClient.messageStream.listen((message) {
  if (message is DocumentOpenedEvent) {
    _handleDocumentOpened(message);
  }
});
```

**Location**:

- Model: `lib/core/models/protocol_message.dart` (lines 267-290)
- Handler: `lib/state/app_controller.dart` (lines 220-232)

---

### 4. Document Changed (`document.changed`)

**Protocol Spec**: Server → Client (Event)

**Event Format**:

```json
{
    "type": "document.changed",
    "payload": {
        "uri": "file:///path/to/file.ts",
        "fileName": "/path/to/file.ts",
        "changes": [
            {
                "range": {
                    "start": { "line": 5, "character": 0 },
                    "end": { "line": 5, "character": 10 }
                },
                "text": "const x = 42;"
            }
        ],
        "contentAfterChange": "..."
    }
}
```

**Implementation**:

**Models**:

```dart
class DocumentChangedEvent extends ProtocolMessage {
  final String uri;
  final String fileName;
  final List<TextChange> changes;
  final String? contentAfterChange;
}

class TextChange {
  final TextRange range;
  final String text;
}

class TextRange {
  final Position start;
  final Position end;
}

class Position {
  final int line;
  final int character;
}
```

**Handler with Loop Prevention**:

```dart
void _handleDocumentChanged(DocumentChangedEvent event) {
  // Only update if change came from VS Code (not from us)
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
```

**Loop Prevention Strategy**:

1. Track locally modified files in `_locallyModifiedFiles` Set
2. Only apply external changes if file not locally modified
3. Clear tracking when `document.saved` event received

**Location**:

- Model: `lib/core/models/protocol_message.dart` (lines 293-320)
- Handler: `lib/state/app_controller.dart` (lines 234-250)

---

### 5. Document Saved (`document.saved`)

**Protocol Spec**: Server → Client (Event)

**Event Format**:

```json
{
    "type": "document.saved",
    "payload": {
        "uri": "file:///path/to/file.ts",
        "fileName": "/path/to/file.ts",
        "content": "..."
    }
}
```

**Implementation**:

**Handler**:

```dart
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
```

**Purpose**:

- Sync saved content from VS Code
- Clear modified flag
- Remove from local modification tracking

**Location**:

- Model: `lib/core/models/protocol_message.dart` (lines 323-342)
- Handler: `lib/state/app_controller.dart` (lines 252-266)

---

### 6. Document Closed (`document.closed`)

**Protocol Spec**: Server → Client (Event)

**Event Format**:

```json
{
    "type": "document.closed",
    "payload": {
        "uri": "file:///path/to/file.ts",
        "fileName": "/path/to/file.ts"
    }
}
```

**Implementation**:

**Handler**:

```dart
void _handleDocumentClosed(DocumentClosedEvent event) {
  final newState = Map<String, OpenFile>.from(state);
  newState.remove(event.fileName);
  state = newState;
  _locallyModifiedFiles.remove(event.fileName);
}
```

**Location**:

- Model: `lib/core/models/protocol_message.dart` (lines 345-361)
- Handler: `lib/state/app_controller.dart` (lines 268-274)

---

### 7. Workspace Changed (`workspace.changed`)

**Protocol Spec**: Server → Client (Event)

**Event Format**:

```json
{
    "type": "workspace.changed",
    "payload": {
        "workspaceFolders": [
            {
                "uri": "file:///path/to/workspace",
                "name": "my-project",
                "index": 0
            }
        ]
    }
}
```

**Implementation**:

**Models**:

```dart
class WorkspaceChangedEvent extends ProtocolMessage {
  final List<WorkspaceFolder> workspaceFolders;
}

class WorkspaceFolder {
  final String uri;
  final String name;
  final int index;
}
```

**Handler**: Currently logged but not used for UI updates (future enhancement for multi-workspace support)

**Location**: `lib/core/models/protocol_message.dart` (lines 364-387)

---

### 8. Workspace Tree (`workspace.tree`)

**Protocol Spec**: Server → Client (Event/Response)

**Event Format**:

```json
{
  "type": "workspace.tree",
  "payload": {
    "tree": [{
      "name": "src",
      "path": "/path/to/src",
      "type": "directory",
      "children": [...]
    }]
  }
}
```

**Implementation**:

**Models**:

```dart
class WorkspaceTreeEvent extends ProtocolMessage {
  final List<FileTreeNode> tree;
}

class FileTreeNode {
  final String name;
  final String path;
  final FileNodeType type;
  final List<FileTreeNode>? children;

  bool get isDirectory => type == FileNodeType.directory;
  bool get isFile => type == FileNodeType.file;
}

enum FileNodeType {
  file('file'),
  directory('directory');
}
```

**Handler**:

```dart
class WorkspaceTreeNotifier extends StateNotifier<List<FileTreeNode>> {
  void _init() {
    _messageSubscription = wsClient.messageStream.listen((message) {
      if (message is WorkspaceTreeEvent) {
        state = message.tree;
      }
    });
  }

  Future<void> refresh() async {
    final tree = await client.requestWorkspaceTree();
    state = tree;
  }
}
```

**UI Rendering**:

```dart
class _FileTreeNodeWidget extends ConsumerStatefulWidget {
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => node.isDirectory
            ? setState(() => _isExpanded = !_isExpanded)
            : _openFile(node.path),
          child: /* file/folder UI */,
        ),
        if (_isExpanded && node.children != null)
          ...node.children!.map((child) => _FileTreeNodeWidget(node: child)),
      ],
    );
  }
}
```

**Location**:

- Model: `lib/core/models/protocol_message.dart` (lines 390-434)
- Handler: `lib/state/app_controller.dart` (lines 170-195)
- UI: `lib/features/workspace/workspace_explorer.dart`

---

## Commands Implementation

### 1. Read File (`readFile`)

**Protocol Spec**: Client → Server

**Request**:

```json
{
    "type": "readFile",
    "requestId": "uuid",
    "payload": {
        "path": "/path/to/file.txt"
    }
}
```

**Response**:

```json
{
    "type": "response",
    "requestId": "uuid",
    "success": true,
    "payload": {
        "path": "/path/to/file.txt",
        "content": "..."
    }
}
```

**Implementation**:

**Request Class**:

```dart
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
```

**Extension Method**:

```dart
extension VSCodeWebSocketClientExtensions on VSCodeWebSocketClient {
  Future<String> readFile(String path) async {
    final response = await sendRequest(ReadFileRequest(
      requestId: generateRequestId(),
      path: path,
    ));

    if (!response.success) {
      throw Exception(response.error ?? 'Failed to read file');
    }

    return response.payload?['content'] as String? ?? '';
  }
}
```

**Usage in App**:

```dart
Future<void> openFile(String path) async {
  final content = await client.readFile(path);
  final languageId = _getLanguageIdFromPath(path);

  state = {
    ...state,
    path: OpenFile(
      path: path,
      content: content,
      languageId: languageId,
    ),
  };
}
```

**Location**:

- Request: `lib/core/models/protocol_message.dart` (lines 167-175)
- Extension: `lib/core/websocket/ws_client.dart` (lines 397-408)
- Usage: `lib/state/app_controller.dart` (lines 277-303)

---

### 2. Write File (`writeFile`)

**Protocol Spec**: Client → Server

**Request**:

```json
{
    "type": "writeFile",
    "requestId": "uuid",
    "payload": {
        "path": "/path/to/file.txt",
        "content": "...",
        "createDirectories": true
    }
}
```

**Implementation**:

**Request Class**:

```dart
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
      if (createDirectories != null) 'createDirectories': createDirectories,
    },
  );
}
```

**Extension Method with Debouncing**:

```dart
Future<void> writeFile(String path, String content, {bool createDirectories = true}) async {
  final response = await sendRequest(WriteFileRequest(
    requestId: generateRequestId(),
    path: path,
    content: content,
    createDirectories: createDirectories,
  ));

  if (!response.success) {
    throw Exception(response.error ?? 'Failed to write file');
  }
}
```

**Save with Debouncing**:

```dart
// In code editor
void _handleTextChange(String path, String newContent) {
  ref.read(openFilesProvider.notifier).updateContent(path, newContent);

  _saveDebouncer?.cancel();
  _saveDebouncer = Timer(const Duration(milliseconds: 1500), () {
    _saveFile(path);
  });
}
```

**Location**:

- Request: `lib/core/models/protocol_message.dart` (lines 145-164)
- Extension: `lib/core/websocket/ws_client.dart` (lines 411-425)
- Editor: `lib/features/editor/code_editor_view.dart` (lines 238-248)

---

### 3. Open File (`openFile`)

**Protocol Spec**: Client → Server

**Request**:

```json
{
    "type": "openFile",
    "requestId": "uuid",
    "payload": {
        "path": "/path/to/file.ts",
        "preview": false,
        "viewColumn": 1
    }
}
```

**Implementation**:

```dart
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
```

**Location**: `lib/core/models/protocol_message.dart` (lines 178-197)

---

### 4. Run Shell Command (`runShellCommand`)

**Protocol Spec**: Client → Server

**Request**:

```json
{
    "type": "runShellCommand",
    "requestId": "uuid",
    "payload": {
        "command": "npm install",
        "cwd": "/path/to/project",
        "captureOutput": true,
        "useVisibleTerminal": false,
        "terminalName": "Build",
        "reuseTerminal": true
    }
}
```

**Response**:

```json
{
    "type": "response",
    "requestId": "uuid",
    "success": true,
    "payload": {
        "stdout": "...",
        "stderr": "...",
        "exitCode": 0
    }
}
```

**Implementation**:

**Request Class**:

```dart
class RunShellCommandRequest extends ProtocolMessage {
  RunShellCommandRequest({
    required String requestId,
    required String command,
    String? cwd,
    bool? captureOutput,
    bool? useVisibleTerminal,
    String? terminalName,
    bool? reuseTerminal,
  }) : super(
    type: 'runShellCommand',
    requestId: requestId,
    payload: {
      'command': command,
      if (cwd != null) 'cwd': cwd,
      if (captureOutput != null) 'captureOutput': captureOutput,
      if (useVisibleTerminal != null) 'useVisibleTerminal': useVisibleTerminal,
      if (terminalName != null) 'terminalName': terminalName,
      if (reuseTerminal != null) 'reuseTerminal': reuseTerminal,
    },
  );
}
```

**New Terminal Parameters**:

- `useVisibleTerminal` (optional): When `true`, opens a visible terminal in VS Code instead of capturing output
- `terminalName` (optional): Custom name for the terminal (useful for identifying terminals)
- `reuseTerminal` (optional): When `true`, reuses an existing terminal with the same name instead of creating a new one

**Extension Method**:

```dart
Future<Map<String, dynamic>> runShellCommand(
  String command, {
  String? cwd,
  bool captureOutput = true,
  bool? useVisibleTerminal,
  String? terminalName,
  bool? reuseTerminal,
}) async {
  final response = await sendRequest(RunShellCommandRequest(
    requestId: generateRequestId(),
    command: command,
    cwd: cwd,
    captureOutput: captureOutput,
    useVisibleTerminal: useVisibleTerminal,
    terminalName: terminalName,
    reuseTerminal: reuseTerminal,
  ));

  if (!response.success) {
    throw Exception(response.error ?? 'Failed to run command');
  }

  return response.payload ?? {};
}
```

**Usage Examples**:

1. **Capture Output (default behavior)**:

```dart
final result = await client.runShellCommand(
  'npm test',
  cwd: '/path/to/project',
  captureOutput: true,
);
print('Exit code: ${result['exitCode']}');
print('Output: ${result['stdout']}');
```

2. **Visible Terminal in VS Code**:

```dart
await client.runShellCommand(
  'npm run dev',
  cwd: '/path/to/project',
  useVisibleTerminal: true,
  terminalName: 'Dev Server',
);
```

3. **Reuse Existing Terminal**:

```dart
// First command creates terminal
await client.runShellCommand(
  'npm install',
  useVisibleTerminal: true,
  terminalName: 'Build',
  reuseTerminal: true,
);

// Second command reuses same terminal
await client.runShellCommand(
  'npm run build',
  useVisibleTerminal: true,
  terminalName: 'Build',
  reuseTerminal: true,
);
```

**Location**:

- Request: `lib/core/models/protocol_message.dart`
- Extension: `lib/core/websocket/ws_client.dart`

---

### 5. Request Workspace Tree (`requestWorkspaceTree`)

**Protocol Spec**: Client → Server

**Request**:

```json
{
    "type": "requestWorkspaceTree",
    "requestId": "uuid",
    "payload": {
        "includeHidden": false,
        "maxDepth": 5
    }
}
```

**Implementation**:

```dart
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
```

**Extension Method**:

```dart
Future<List<FileTreeNode>> requestWorkspaceTree({
  bool includeHidden = false,
  int maxDepth = 10,
}) async {
  final response = await sendRequest(RequestWorkspaceTreeRequest(
    requestId: generateRequestId(),
    includeHidden: includeHidden,
    maxDepth: maxDepth,
  ));

  if (!response.success) {
    throw Exception(response.error ?? 'Failed to get workspace tree');
  }

  final treeJson = response.payload?['tree'] as List<dynamic>? ?? [];
  return treeJson
    .map((node) => FileTreeNode.fromJson(node as Map<String, dynamic>))
    .toList();
}
```

**Location**:

- Request: `lib/core/models/protocol_message.dart` (lines 257-272)
- Extension: `lib/core/websocket/ws_client.dart` (lines 470-489)

---

## Synchronization Strategy

### Bidirectional Sync Architecture

```
┌─────────────┐          ┌─────────────┐
│  Flutter    │          │   VS Code   │
│     App     │          │  Extension  │
└──────┬──────┘          └──────┬──────┘
       │                        │
       │  1. Edit in App        │
       │───────────────────────>│
       │  writeFile             │
       │                        │
       │  2. VS Code Saves      │
       │<───────────────────────│
       │  document.saved        │
       │                        │
       │  3. Edit in VS Code    │
       │<───────────────────────│
       │  document.changed      │
       │                        │
```

### Loop Prevention Mechanisms

**1. Local Modification Tracking**

```dart
final Set<String> _locallyModifiedFiles = {};

void updateContent(String path, String content) {
  _locallyModifiedFiles.add(path);  // Mark as locally modified
  // ... update state
}

void _handleDocumentChanged(DocumentChangedEvent event) {
  // Only apply if NOT locally modified
  if (!_locallyModifiedFiles.contains(event.fileName)) {
    // ... apply change
  }
}

void _handleDocumentSaved(DocumentSavedEvent event) {
  _locallyModifiedFiles.remove(event.fileName);  // Clear flag
}
```

**2. Timestamp Tracking**

```dart
class OpenFile {
  final DateTime lastSync;

  OpenFile copyWith({DateTime? lastSync}) {
    return OpenFile(
      lastSync: lastSync ?? this.lastSync,
      // ...
    );
  }
}
```

**3. Content Hash Comparison** (Future Enhancement)

Could add SHA-256 hash comparison to detect if content actually changed.

### Debounced Saves

Prevents excessive network traffic:

```dart
Timer? _saveDebouncer;

void _handleTextChange(String path, String newContent) {
  ref.read(openFilesProvider.notifier).updateContent(path, newContent);

  _saveDebouncer?.cancel();
  _saveDebouncer = Timer(const Duration(milliseconds: 1500), () {
    _saveFile(path);
  });
}
```

**Location**: `lib/features/editor/code_editor_view.dart` (lines 238-248)

---

## Error Handling

### Connection Errors

**Exponential Backoff Reconnection**:

```dart
void _scheduleReconnect() {
  _reconnectAttempts++;

  // Exponential backoff: 2s, 4s, 8s, 16s, 32s...
  final delay = Duration(
    milliseconds: initialReconnectDelay.inMilliseconds * (1 << (_reconnectAttempts - 1)),
  );

  // Cap at 1 minute
  final cappedDelay = delay > const Duration(minutes: 1)
    ? const Duration(minutes: 1)
    : delay;

  _reconnectTimer = Timer(cappedDelay, () {
    connect();
  });
}
```

### Request Timeouts

```dart
final timeoutTimer = Timer(timeout, () {
  if (_pendingRequests.containsKey(request.requestId)) {
    _pendingRequests.remove(request.requestId);
    completer.completeError('Request timeout');
  }
});
```

### Protocol Errors

**Unknown Message Types**:

```dart
default:
  return UnknownMessage(type: type, requestId: requestId, payload: payload);
```

**JSON Parse Errors**:

```dart
try {
  final json = jsonDecode(data as String) as Map<String, dynamic>;
  final message = ProtocolMessage.fromJson(json);
  // ...
} catch (e) {
  logger.e('Failed to parse message: $e');
  _errorController.add('Failed to parse message: $e');
}
```

**Location**: `lib/core/websocket/ws_client.dart`

---

## Summary

This implementation provides:

✅ **Complete Protocol Coverage** - All events and commands implemented  
✅ **Type Safety** - Strongly typed models with null safety  
✅ **Robust Error Handling** - Graceful degradation and recovery  
✅ **Bidirectional Sync** - Loop-free synchronization  
✅ **Production Ready** - Reconnection, timeouts, debouncing  
✅ **Clean Architecture** - Separation of concerns  
✅ **Maintainable** - Well-documented and structured

The implementation follows Flutter best practices and provides a solid foundation for a professional VS Code remote client.
