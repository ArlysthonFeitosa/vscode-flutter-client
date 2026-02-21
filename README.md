# VS Code Remote Client

A professional Flutter application that serves as the official mobile/desktop client for the VS Code WebSocket Bridge extension. This app enables remote control and synchronization with VS Code through a robust WebSocket connection.

## Features

- ✅ **Real-time WebSocket Communication** - Bidirectional sync with VS Code
- ✅ **Authentication** - Secure token-based authentication
- ✅ **Workspace Explorer** - Browse and navigate project files
- ✅ **Code Editor** - Full-featured editor with syntax highlighting
- ✅ **Terminal** - Execute shell commands remotely
- ✅ **Automatic Reconnection** - Exponential backoff reconnection strategy
- ✅ **Bidirectional File Sync** - Edit files locally and sync to VS Code
- ✅ **State Management** - Robust Riverpod-based architecture
- ✅ **Type Safety** - Full type-safe protocol implementation

---

## Architecture

```
lib/
├── core/
│   ├── websocket/
│   │   └── ws_client.dart           # WebSocket client implementation
│   ├── models/
│   │   └── protocol_message.dart    # Protocol message definitions
│   └── utils/                        # Utilities (future)
├── features/
│   ├── workspace/
│   │   └── workspace_explorer.dart  # File tree widget
│   ├── editor/
│   │   └── code_editor_view.dart    # Code editor with syntax highlighting
│   ├── terminal/
│   │   └── terminal_view.dart       # Terminal interface
│   └── settings/
│       └── settings_view.dart       # Connection configuration
├── state/
│   └── app_controller.dart          # Global state management
└── main.dart                         # Application entry point
```

---

## Prerequisites

### Required

- **Flutter SDK** (>=3.0.0)
- **Dart SDK** (>=3.0.0)
- **VS Code** with WebSocket Bridge extension installed

### Optional

- Physical device or emulator for mobile testing
- Desktop OS for desktop app testing

---

## Installation

### 1. Clone and Setup

```bash
# Navigate to the project directory
cd vscode_remote_client

# Install dependencies
flutter pub get
```

### 2. Configure VS Code Extension

First, install and configure the VS Code WebSocket Bridge extension:

1. Install the extension in VS Code
2. Create a `.env` file in the extension directory:

```env
REMOTE_WS_PORT=8080
REMOTE_WS_TOKEN=your-secret-token-here
REMOTE_WS_HOST=localhost
```

3. Restart VS Code

### 3. Run the App

```bash
# Run on connected device/emulator
flutter run

# Or for specific platforms:
flutter run -d macos       # macOS desktop
flutter run -d windows     # Windows desktop
flutter run -d linux       # Linux desktop
flutter run -d chrome      # Web browser
flutter run -d android     # Android device/emulator
flutter run -d ios         # iOS device/simulator
```

---

## Configuration

### First Time Setup

1. **Launch the app**
2. **Tap "Configure & Connect"** button
3. **Enter connection details**:
    - **Host**: `localhost` (or IP address if remote)
    - **Port**: `8080` (default)
    - **Token**: Same token as in VS Code `.env` file
4. **Tap "Save Settings"**
5. **Tap "Connect"**

### Settings Persistence

Settings are automatically saved to local storage using `SharedPreferences`. Your configuration persists across app restarts.

---

## Usage Guide

### Workspace Explorer

- **Navigate Files**: Tap folders to expand/collapse
- **Open Files**: Tap a file to open in the editor
- **Refresh**: Use the refresh button to reload the workspace tree
- **Visual Indicators**: Color-coded icons for different file types

### Code Editor

- **Syntax Highlighting**: Automatic language detection
- **Edit Files**: Changes are debounced and auto-saved
- **Theme Toggle**: Switch between dark/light editor themes
- **Modified Indicator**: Orange dot shows unsaved changes
- **Manual Save**: Save button available for explicit saves
- **Close Files**: Prompts to save if unsaved changes exist

**Supported Languages**:

- Dart, JavaScript, TypeScript, Python, Java, Go, C/C++, C#, Ruby, PHP
- JSON, YAML, XML, HTML, CSS, Markdown, SQL

### Terminal

- **Execute Commands**: Enter commands and press Enter
- **Command History**: Navigate with up/down arrows (coming soon)
- **Auto-scroll**: Terminal automatically scrolls to latest output
- **Color-coded Output**:
    - Green: Input commands
    - White: Standard output
    - Red: Errors
    - Blue: Info messages
- **Clear Terminal**: Clear button removes all output

---

## Authentication Flow

1. **App starts** → Loads saved connection config
2. **User taps "Connect"** → WebSocket connection initiated
3. **Connection established** → Auth message sent with token
4. **Server validates token** → Returns `clientId` if successful
5. **App authenticated** → Features become active
6. **Connection lost** → Auto-reconnection with exponential backoff

### Token Security

- Tokens are stored encrypted in local device storage
- Never transmitted over insecure channels
- Use strong, randomly-generated tokens
- Regenerate tokens periodically

---

## Protocol Implementation

This app implements the complete VS Code WebSocket Bridge protocol as specified in `PROTOCOL.md`.

### Implemented Events (VS Code → App)

| Event               | Handler                 | Description                     |
| ------------------- | ----------------------- | ------------------------------- |
| `document.opened`   | `OpenFilesNotifier`     | File opened in VS Code          |
| `document.changed`  | `OpenFilesNotifier`     | File content changed in VS Code |
| `document.saved`    | `OpenFilesNotifier`     | File saved in VS Code           |
| `document.closed`   | `OpenFilesNotifier`     | File closed in VS Code          |
| `workspace.changed` | `WorkspaceTreeNotifier` | Workspace folders changed       |
| `workspace.tree`    | `WorkspaceTreeNotifier` | Workspace structure received    |

### Implemented Commands (App → VS Code)

| Command                | Implementation          | Description                 |
| ---------------------- | ----------------------- | --------------------------- |
| `auth`                 | `VSCodeWebSocketClient` | Authenticate connection     |
| `ping`                 | `VSCodeWebSocketClient` | Keep-alive ping             |
| `readFile`             | `OpenFilesNotifier`     | Read file content           |
| `writeFile`            | `OpenFilesNotifier`     | Write file content          |
| `openFile`             | `OpenFilesNotifier`     | Open file in VS Code        |
| `saveFile`             | `OpenFilesNotifier`     | Save file to disk           |
| `deleteFile`           | Extension methods       | Delete file/directory       |
| `createDirectory`      | Extension methods       | Create directory            |
| `runShellCommand`      | `AppController`         | Execute shell command       |
| `requestWorkspaceTree` | `WorkspaceTreeNotifier` | Request workspace structure |
| `executeCommand`       | Extension methods       | Execute VS Code command     |

See `PROTOCOL_USAGE.md` for detailed implementation explanations.

---

## State Management

### Riverpod Providers

```dart
// Connection
connectionConfigProvider        // Connection configuration
connectionStateProvider         // Real-time connection state
messageStreamProvider          // WebSocket message stream
errorStreamProvider            // Error notifications

// Workspace
workspaceTreeProvider          // File tree state
openFilesProvider              // Open file documents
activeFilePathProvider         // Currently active file

// Terminal
terminalOutputProvider         // Terminal output lines

// Core
wsClientProvider               // WebSocket client instance
appControllerProvider          // Global app actions
```

### State Flow

```
User Action
    ↓
Widget (ConsumerWidget)
    ↓
Provider.notifier
    ↓
State Notifier / Controller
    ↓
WebSocket Client
    ↓
VS Code Extension
    ↓
WebSocket Events
    ↓
Message Stream
    ↓
State Notifier Listeners
    ↓
Provider Updates
    ↓
Widget Rebuilds
```

---

## Bidirectional Synchronization

### Local → VS Code

1. User edits file in app editor
2. `OpenFilesNotifier.updateContent()` called
3. File marked as modified
4. Debounced save triggered (1.5s delay)
5. `writeFile` request sent to VS Code
6. VS Code updates file on disk
7. `document.saved` event received
8. File marked as not modified

### VS Code → App

1. User edits file in VS Code
2. Extension sends `document.changed` event
3. App receives event via message stream
4. `OpenFilesNotifier` listener triggered
5. Checks if change is from local edit (to prevent loops)
6. Updates file content if external change
7. Editor UI updates automatically

### Loop Prevention

- **Local modification tracking**: `_locallyModifiedFiles` Set
- **Timestamp comparison**: `lastSync` DateTime
- **Source detection**: Events only applied if not locally initiated

---

## Error Handling

### Connection Errors

- **Network failures**: Automatic exponential backoff reconnection
- **Authentication failures**: Clear error display, disconnect
- **Timeout**: Configurable request timeout (default 30s)

### File Operation Errors

- **Read/Write failures**: Error toast with details
- **Permission errors**: Graceful degradation
- **Not found errors**: User notification

### Protocol Errors

- **Invalid messages**: Logged and ignored
- **Unknown message types**: `UnknownMessage` graceful handling
- **Malformed JSON**: Caught and logged

---

## Development

### Code Structure Standards

- **Strong typing**: No `dynamic` types
- **Null safety**: Full null-safe implementation
- **Immutability**: State objects use `copyWith`
- **Documentation**: All public APIs documented

### Building for Production

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release

# macOS
flutter build macos --release

# Windows
flutter build windows --release

# Linux
flutter build linux --release

# Web
flutter build web --release
```

---

## Troubleshooting

### Connection Issues

**Problem**: "Connection failed" or "Authentication failed"

**Solutions**:

1. Verify VS Code extension is running (`View → Output → WebSocket Bridge`)
2. Check token matches exactly in both app and VS Code
3. Confirm port 8080 is not blocked by firewall
4. Try `127.0.0.1` instead of `localhost`

### App Not Connecting to Remote Machine

**Problem**: App on mobile can't connect to desktop VS Code

**Solutions**:

1. Set `REMOTE_WS_HOST=0.0.0.0` in VS Code `.env` to bind all interfaces
2. Use desktop's local IP address (e.g., `192.168.1.100`) in app
3. Ensure firewall allows connections on port 8080
4. Verify both devices are on same network

### Files Not Syncing

**Problem**: Changes in app don't appear in VS Code

**Solutions**:

1. Check connection status indicator is green
2. Verify file is actually saved (orange dot should disappear)
3. Check VS Code output panel for errors
4. Try refreshing workspace tree

### Editor Syntax Highlighting Not Working

**Problem**: Code appears as plain text

**Solutions**:

1. Verify file extension is recognized
2. Check language ID mapping in `_getLanguageIdFromPath()`
3. Ensure `flutter_highlight` package is properly installed

---

## Performance Considerations

### Memory Management

- Controllers disposed when widgets unmount
- WebSocket streams properly closed
- File content cached efficiently

### Network Optimization

- Debounced file saves reduce network traffic
- Request/response correlation prevents duplicate requests
- Automatic reconnection with capped exponential backoff

### UI Performance

- Lazy rendering of file tree
- Virtualized lists for large outputs
- Efficient widget rebuilds with Riverpod

---

## Roadmap

- [ ] Multi-workspace support
- [ ] File search functionality
- [ ] Git integration
- [ ] Snippet support
- [ ] Find/replace in editor
- [ ] Split editor view
- [ ] Diff viewer
- [ ] Desktop notification support

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Follow existing code style
4. Add tests if applicable
5. Submit a pull request

---

## License

MIT License - See LICENSE file for details

---

## Support

- **Issues**: Report bugs on GitHub
- **Documentation**: See `PROTOCOL_USAGE.md` for protocol details
- **Extension**: Ensure VS Code extension is up to date

---

## Credits

Built with:

- [Flutter](https://flutter.dev/)
- [Riverpod](https://riverpod.dev/)
- [flutter_code_editor](https://pub.dev/packages/flutter_code_editor)
- [web_socket_channel](https://pub.dev/packages/web_socket_channel)

---

**Made with ❤️ for the Flutter and VS Code communities**
