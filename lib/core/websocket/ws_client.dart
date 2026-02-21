import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import '../models/protocol_message.dart';

/// WebSocket connection state enum
enum WSConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  reconnecting,
  error,
}

/// WebSocket client for VS Code Bridge protocol
/// Handles connection, authentication, message routing, and reconnection
class VSCodeWebSocketClient {
  final String host;
  final int port;
  final String token;
  final Logger logger;
  final Duration timeout;
  final int maxReconnectAttempts;
  final Duration initialReconnectDelay;

  WebSocketChannel? _channel;
  WSConnectionState _state = WSConnectionState.disconnected;
  String? _clientId;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  // Request tracking
  final Map<String, Completer<ResponseMessage>> _pendingRequests = {};
  final Map<String, Timer> _requestTimeouts = {};

  // Event stream controllers
  final StreamController<ProtocolMessage> _messageController = StreamController<ProtocolMessage>.broadcast();
  final StreamController<WSConnectionState> _stateController = StreamController<WSConnectionState>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();

  // UUID generator
  final Uuid _uuid = const Uuid();

  VSCodeWebSocketClient({
    required this.host,
    required this.port,
    required this.token,
    Logger? logger,
    this.timeout = const Duration(seconds: 30),
    this.maxReconnectAttempts = 10,
    this.initialReconnectDelay = const Duration(seconds: 2),
  }) : logger = logger ?? Logger();

  // ============================================================================
  // Public API
  // ============================================================================

  /// Current connection state
  WSConnectionState get state => _state;

  /// Whether currently connected and authenticated
  bool get isConnected => _state == WSConnectionState.connected;

  /// Client ID assigned by server (null if not authenticated)
  String? get clientId => _clientId;

  /// Stream of incoming messages
  Stream<ProtocolMessage> get messageStream => _messageController.stream;

  /// Stream of connection state changes
  Stream<WSConnectionState> get stateStream => _stateController.stream;

  /// Stream of error messages
  Stream<String> get errorStream => _errorController.stream;

  /// Connect to the WebSocket server and authenticate
  Future<void> connect() async {
    if (_state == WSConnectionState.connecting || _state == WSConnectionState.authenticating || _state == WSConnectionState.connected) {
      logger.w('Already connected or connecting');
      return;
    }

    _updateState(WSConnectionState.connecting);
    logger.i('Connecting to ws://$host:$port');

    try {
      final uri = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(uri);

      // Listen to messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnection,
        cancelOnError: false,
      );

      // Authenticate
      await _authenticate();

      // Start ping/pong heartbeat
      _startPingTimer();
    } catch (e) {
      logger.e('Connection failed: $e');
      _updateState(WSConnectionState.error);
      _errorController.add('Connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Disconnect from the server
  Future<void> disconnect() async {
    logger.i('Disconnecting...');
    _reconnectAttempts = maxReconnectAttempts; // Prevent auto-reconnect
    _stopPingTimer();
    _reconnectTimer?.cancel();

    await _channel?.sink.close();
    _channel = null;
    _clientId = null;
    _updateState(WSConnectionState.disconnected);

    // Cancel all pending requests
    for (final completer in _pendingRequests.values) {
      completer.completeError('Disconnected');
    }
    _pendingRequests.clear();

    for (final timer in _requestTimeouts.values) {
      timer.cancel();
    }
    _requestTimeouts.clear();
  }

  /// Send a request and wait for response
  Future<ResponseMessage> sendRequest(ProtocolMessage request) async {
    if (_state != WSConnectionState.connected && _state != WSConnectionState.authenticating) {
      throw Exception('Not connected to server');
    }

    if (request.requestId == null) {
      throw ArgumentError('Request must have a requestId');
    }

    final completer = Completer<ResponseMessage>();
    _pendingRequests[request.requestId!] = completer;

    // Set timeout
    final timeoutTimer = Timer(timeout, () {
      if (_pendingRequests.containsKey(request.requestId)) {
        _pendingRequests.remove(request.requestId);
        _requestTimeouts.remove(request.requestId);
        completer.completeError('Request timeout');
      }
    });
    _requestTimeouts[request.requestId!] = timeoutTimer;

    // Send message
    _sendMessage(request);

    return completer.future;
  }

  /// Send a message without expecting a response
  void sendMessage(ProtocolMessage message) {
    if (_state != WSConnectionState.connected && _state != WSConnectionState.authenticating) {
      logger.w('Cannot send message: not connected');
      return;
    }
    _sendMessage(message);
  }

  /// Generate a unique request ID
  String generateRequestId() => _uuid.v4();

  /// Dispose resources
  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
    _errorController.close();
  }

  // ============================================================================
  // Private Methods
  // ============================================================================

  /// Update connection state and notify listeners
  void _updateState(WSConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
      logger.d('State changed: $newState');
    }
  }

  /// Authenticate with the server
  Future<void> _authenticate() async {
    _updateState(WSConnectionState.authenticating);
    logger.i('Authenticating...');

    final authRequest = AuthRequest(
      requestId: generateRequestId(),
      token: token,
    );

    try {
      final response = await sendRequest(authRequest);

      if (response.success) {
        _clientId = response.payload?['clientId'] as String?;
        _reconnectAttempts = 0; // Reset reconnect counter
        _updateState(WSConnectionState.connected);
        logger.i('Authentication successful. Client ID: $_clientId');
      } else {
        final error = response.error ?? 'Authentication failed';
        logger.e('Authentication failed: $error');
        _errorController.add(error);
        _updateState(WSConnectionState.error);
        await disconnect();
      }
    } catch (e) {
      logger.e('Authentication error: $e');
      _errorController.add('Authentication error: $e');
      _updateState(WSConnectionState.error);
      await disconnect();
    }
  }

  /// Send a message to the server
  void _sendMessage(ProtocolMessage message) {
    try {
      final json = jsonEncode(message.toJson());
      _channel?.sink.add(json);
      logger.d('Sent: ${message.type} (${message.requestId})');
    } catch (e) {
      logger.e('Failed to send message: $e');
      _errorController.add('Failed to send message: $e');
    }
  }

  /// Handle incoming WebSocket message
  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final message = ProtocolMessage.fromJson(json);

      logger.d('Received: ${message.type} (${message.requestId})');

      // Log terminal events specifically for debugging
      if (message.type == 'terminal.output' || message.type == 'terminal.completed') {
        logger.i('Terminal event received: ${message.type}');
        logger.d('Terminal event payload: ${message.payload}');
      }

      // Handle responses to pending requests
      if (message is ResponseMessage && message.requestId != null) {
        final completer = _pendingRequests.remove(message.requestId);
        final timer = _requestTimeouts.remove(message.requestId);
        timer?.cancel();

        if (completer != null && !completer.isCompleted) {
          completer.complete(message);
        }
      }

      // Broadcast message to listeners
      _messageController.add(message);
    } catch (e) {
      logger.e('Failed to parse message: $e');
      logger.e('Raw data: $data');
      _errorController.add('Failed to parse message: $e');
    }
  }

  /// Handle WebSocket error
  void _handleError(dynamic error) {
    logger.e('WebSocket error: $error');
    _errorController.add('WebSocket error: $error');
    _updateState(WSConnectionState.error);
  }

  /// Handle WebSocket disconnection
  void _handleDisconnection() {
    logger.w('WebSocket disconnected');
    _updateState(WSConnectionState.disconnected);
    _stopPingTimer();

    // Schedule reconnection if not intentionally disconnected
    if (_reconnectAttempts < maxReconnectAttempts) {
      _scheduleReconnect();
    } else {
      logger.e('Max reconnection attempts reached');
      _errorController.add('Connection lost - max reconnection attempts reached');
    }
  }

  /// Schedule automatic reconnection with exponential backoff
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= maxReconnectAttempts) {
      logger.e('Max reconnect attempts reached');
      return;
    }

    _reconnectAttempts++;
    _updateState(WSConnectionState.reconnecting);

    // Exponential backoff: 2s, 4s, 8s, 16s, 32s...
    final delay = Duration(
      milliseconds: initialReconnectDelay.inMilliseconds * (1 << (_reconnectAttempts - 1)),
    );
    final cappedDelay = delay > const Duration(minutes: 1) ? const Duration(minutes: 1) : delay;

    logger.i('Reconnecting in ${cappedDelay.inSeconds}s (attempt $_reconnectAttempts/$maxReconnectAttempts)');

    _reconnectTimer = Timer(cappedDelay, () {
      connect();
    });
  }

  /// Start periodic ping to keep connection alive
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConnected) {
        _sendPing();
      }
    });
  }

  /// Stop ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Send ping message
  void _sendPing() {
    try {
      final ping = PingRequest(requestId: generateRequestId());
      sendRequest(ping).then((response) {
        logger.d('Ping successful');
      }).catchError((error) {
        logger.w('Ping failed: $error');
      });
    } catch (e) {
      logger.e('Ping error: $e');
    }
  }
}

// ============================================================================
// Convenience Extensions
// ============================================================================

/// Extension methods for common operations
extension VSCodeWebSocketClientExtensions on VSCodeWebSocketClient {
  /// Read a file
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

  /// Write a file
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

  /// Open a file in VS Code
  Future<void> openFile(String path, {bool preview = false, int viewColumn = 1}) async {
    final response = await sendRequest(OpenFileRequest(
      requestId: generateRequestId(),
      path: path,
      preview: preview,
      viewColumn: viewColumn,
    ));

    if (!response.success) {
      throw Exception(response.error ?? 'Failed to open file');
    }
  }

  /// Save a file
  Future<void> saveFile([String? path]) async {
    final response = await sendRequest(SaveFileRequest(
      requestId: generateRequestId(),
      path: path,
    ));

    if (!response.success) {
      throw Exception(response.error ?? 'Failed to save file');
    }
  }

  /// Delete a file or directory
  Future<void> deleteFile(String path, {bool recursive = false}) async {
    final response = await sendRequest(DeleteFileRequest(
      requestId: generateRequestId(),
      path: path,
      recursive: recursive,
    ));

    if (!response.success) {
      throw Exception(response.error ?? 'Failed to delete file');
    }
  }

  /// Create a directory
  Future<void> createDirectory(String path) async {
    final response = await sendRequest(CreateDirectoryRequest(
      requestId: generateRequestId(),
      path: path,
    ));

    if (!response.success) {
      throw Exception(response.error ?? 'Failed to create directory');
    }
  }

  /// Run a shell command
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

  /// Request workspace tree
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
    return treeJson.map((node) => FileTreeNode.fromJson(node as Map<String, dynamic>)).toList();
  }

  /// Execute a VS Code command
  Future<dynamic> executeCommand(String command, [List<dynamic>? args]) async {
    final response = await sendRequest(ExecuteCommandRequest(
      requestId: generateRequestId(),
      command: command,
      args: args,
    ));

    if (!response.success) {
      throw Exception(response.error ?? 'Failed to execute command');
    }

    return response.payload?['result'];
  }
}
