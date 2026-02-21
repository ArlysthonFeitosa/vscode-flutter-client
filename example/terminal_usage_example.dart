import 'package:vscode_remote_client/core/websocket/ws_client.dart';
import 'package:logger/logger.dart';

/// Example demonstrating the new terminal features
/// Updated VS Code extension now supports visible terminals!
void main() async {
  // Create WebSocket client
  final client = VSCodeWebSocketClient(
    host: 'localhost',
    port: 8080,
    token: 'your-secret-token',
    logger: Logger(),
  );

  // Connect to VS Code
  await client.connect();

  // ============================================================================
  // Example 1: Capture Output (default behavior)
  // ============================================================================
  print('\n--- Example 1: Capture Output ---');
  final result = await client.runShellCommand(
    'npm test',
    cwd: '/path/to/project',
    captureOutput: true,
  );
  print('Exit code: ${result['exitCode']}');
  print('Output: ${result['stdout']}');

  // ============================================================================
  // Example 2: Visible Terminal in VS Code
  // ============================================================================
  print('\n--- Example 2: Visible Terminal ---');
  await client.runShellCommand(
    'npm run dev',
    cwd: '/path/to/project',
    useVisibleTerminal: true,
    terminalName: 'Dev Server',
  );
  print('Terminal opened in VS Code!');

  // ============================================================================
  // Example 3: Reuse Existing Terminal
  // ============================================================================
  print('\n--- Example 3: Reuse Terminal ---');

  // First command creates terminal
  await client.runShellCommand(
    'npm install',
    cwd: '/path/to/project',
    useVisibleTerminal: true,
    terminalName: 'Build',
    reuseTerminal: true,
  );

  // Wait a bit
  await Future.delayed(Duration(seconds: 2));

  // Second command reuses same terminal
  await client.runShellCommand(
    'npm run build',
    cwd: '/path/to/project',
    useVisibleTerminal: true,
    terminalName: 'Build',
    reuseTerminal: true,
  );
  print('Commands executed in same terminal!');

  // ============================================================================
  // Example 4: Multiple Named Terminals
  // ============================================================================
  print('\n--- Example 4: Multiple Named Terminals ---');

  // Start dev server in one terminal
  await client.runShellCommand(
    'npm run dev',
    cwd: '/path/to/frontend',
    useVisibleTerminal: true,
    terminalName: 'Frontend Dev',
  );

  // Start backend in another terminal
  await client.runShellCommand(
    'npm run start',
    cwd: '/path/to/backend',
    useVisibleTerminal: true,
    terminalName: 'Backend Server',
  );

  // Run tests in a third terminal
  await client.runShellCommand(
    'npm test -- --watch',
    cwd: '/path/to/project',
    useVisibleTerminal: true,
    terminalName: 'Test Runner',
  );
  print('Three terminals created with different names!');

  // ============================================================================
  // Example 5: Sequential Commands in Same Terminal
  // ============================================================================
  print('\n--- Example 5: Sequential Commands ---');

  final commands = [
    'git pull',
    'npm install',
    'npm run build',
    'npm test',
  ];

  for (final command in commands) {
    await client.runShellCommand(
      command,
      cwd: '/path/to/project',
      useVisibleTerminal: true,
      terminalName: 'CI/CD',
      reuseTerminal: true,
    );
    // Wait between commands if needed
    await Future.delayed(Duration(milliseconds: 500));
  }
  print('All commands executed sequentially in same terminal!');

  // Disconnect
  await client.disconnect();
}
