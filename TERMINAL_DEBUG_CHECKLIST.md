# Terminal Events Debugging Checklist

You mentioned you're not receiving `terminal.output` and `terminal.completed` events. Here's a comprehensive checklist to help diagnose the issue.

## ✅ What Was Implemented

### 1. Protocol Message Classes

- ✅ Added `TerminalOutputEvent` class in `lib/core/models/protocol_message.dart`
- ✅ Added `TerminalCompletedEvent` class in `lib/core/models/protocol_message.dart`
- ✅ Updated message router to handle `terminal.output` and `terminal.completed` types

### 2. Event Listeners

- ✅ `TerminalOutputNotifier` now listens for terminal events from WebSocket
- ✅ Real-time output is processed via `_handleTerminalOutput()`
- ✅ Completion events are processed via `_handleTerminalCompleted()`

### 3. Logging

- ✅ Added logging in WebSocket client when terminal events are received
- ✅ Added logging in TerminalOutputNotifier when events are processed
- ✅ Created debug example in `example/terminal_debug_example.dart`

---

## 🔍 Debugging Steps

### Step 1: Verify VS Code WebSocket Bridge Version

The terminal events (`terminal.output` and `terminal.completed`) were added in **PROTOCOL.md** but may not be implemented in older versions of the VS Code WebSocket Bridge extension.

**Check:**

1. Navigate to the `vscode-websocket-bridge` project
2. Open the extension source code
3. Search for `terminal.output` or `terminal.completed` in the TypeScript files
4. Verify that the extension is broadcasting these events

**Expected Location:**

- The extension should have code that listens to terminal output
- It should broadcast events when:
    - Output is received: `{ type: 'terminal.output', payload: { ... } }`
    - Command completes: `{ type: 'terminal.completed', payload: { ... } }`

### Step 2: Check WebSocket Bridge Extension Implementation

Look for this pattern in the VS Code extension:

```typescript
// Expected in the extension code
terminal.onDidWriteData((data) => {
    broadcast({
        type: "terminal.output",
        payload: {
            terminalName: terminal.name,
            data: data,
            timestamp: Date.now(),
        },
    });
});

// And when process exits
terminal.processId.then((pid) => {
    // On exit
    broadcast({
        type: "terminal.completed",
        payload: {
            terminalName: terminal.name,
            exitCode: exitCode,
            stdout: accumulatedOutput,
            stderr: accumulatedErrors,
            timestamp: Date.now(),
        },
    });
});
```

**If this code is NOT in the extension**, the events won't be sent no matter what we do on the Flutter side.

### Step 3: Run the Debug Example

1. Run the debug example:

    ```bash
    flutter run -d macos example/terminal_debug_example.dart
    ```

2. Click "Connect to VS Code Bridge"

3. Click "Test Terminal (echo)"

4. Check the logs for these messages:
    ```
    TerminalOutputNotifier: Initializing terminal event listener
    TerminalOutputNotifier: Received message type: response
    TerminalOutputNotifier: Received message type: terminal.output  ← SHOULD SEE THIS
    Terminal event received: terminal.output                         ← SHOULD SEE THIS
    ```

### Step 4: Monitor Raw WebSocket Messages

Add this temporary logging to see ALL incoming messages:

In `lib/core/websocket/ws_client.dart`, the logging I added will show:

```
Terminal event received: terminal.output
Terminal event payload: {...}
```

**If you DON'T see these logs**, it means the VS Code bridge is NOT sending the events.

### Step 5: Test with Manual WebSocket Inspection

You can use a WebSocket debugging tool to see raw messages:

1. Install a WebSocket client (like `wscat`):

    ```bash
    npm install -g wscat
    ```

2. Connect to the bridge:

    ```bash
    wscat -c ws://localhost:8080
    ```

3. Send auth:

    ```json
    {
        "type": "auth",
        "requestId": "test-1",
        "payload": { "token": "your-token" }
    }
    ```

4. Send a command:

    ```json
    {
        "type": "runShellCommand",
        "requestId": "test-2",
        "payload": {
            "command": "echo test",
            "useVisibleTerminal": true,
            "terminalName": "Test"
        }
    }
    ```

5. Watch for terminal events in the response

---

## 🐛 Common Issues

### Issue 1: VS Code Bridge Extension Not Sending Events

**Symptom:** No `terminal.output` or `terminal.completed` logs in the Flutter app

**Solution:** The VS Code WebSocket Bridge extension needs to be updated to send these events.

**Fix:** Check the extension code in `/Users/arlysthonfreitas/Downloads/Projetos/remote_ai_projects/vscode-websocket-bridge/` and ensure it implements terminal event broadcasting.

### Issue 2: Wrong Terminal Parameters

**Symptom:** Events only work with `useVisibleTerminal: false`

**Current Code:**

```dart
await client.runShellCommand(
  command,
  cwd: cwd,
  captureOutput: true,
  useVisibleTerminal: true,  // ← Must be true for events
  terminalName: 'VS Code Remote Client Terminal',
  reuseTerminal: true,
);
```

**Note:** According to PROTOCOL.md, terminal events are ONLY sent when `useVisibleTerminal: true`.

### Issue 3: Message Parsing Error

**Symptom:** Logs show "Failed to parse message"

**Check:** Look for this in logs:

```
Failed to parse message: ...
Raw data: ...
```

If you see this, the JSON structure might not match our classes.

---

## 📋 Expected Log Flow (When Working)

When everything works correctly, you should see this sequence:

```
1. [WebSocket] Received: runShellCommand (uuid-123)
2. [WebSocket] Terminal event received: terminal.output
3. [WebSocket] Terminal event payload: {terminalName: ..., data: ..., timestamp: ...}
4. [TerminalOutputNotifier] Received message type: terminal.output
5. [TerminalOutputNotifier] Processing TerminalOutputEvent
6. [TerminalOutputNotifier] Terminal output from VS Code Remote Client Terminal: Hello from terminal test
7. [WebSocket] Terminal event received: terminal.completed
8. [TerminalOutputNotifier] Received message type: terminal.completed
9. [TerminalOutputNotifier] Processing TerminalCompletedEvent
10. [TerminalOutputNotifier] Terminal completed: VS Code Remote Client Terminal with exit code 0
```

---

## 🔧 Next Steps

### If Events Are NOT Being Sent by VS Code Bridge:

You need to update the VS Code WebSocket Bridge extension to implement terminal event broadcasting. Here's what needs to be added:

**File:** `vscode-websocket-bridge/src/extension.ts` (or similar)

```typescript
import * as vscode from "vscode";

// Track active terminals and their output
const terminalData = new Map<string, { stdout: string; stderr: string }>();

export function setupTerminalEventHandlers(broadcast: (message: any) => void) {
    // Listen for terminal output
    vscode.window.onDidWriteTerminalShellIntegration((e) => {
        // This is a simplified example - actual implementation may vary
        broadcast({
            type: "terminal.output",
            payload: {
                terminalName: e.terminal.name,
                data: e.data,
                timestamp: Date.now(),
            },
        });
    });

    // Listen for terminal close (process completion)
    vscode.window.onDidCloseTerminal((terminal) => {
        const data = terminalData.get(terminal.name);
        if (data) {
            broadcast({
                type: "terminal.completed",
                payload: {
                    terminalName: terminal.name,
                    exitCode: terminal.exitStatus?.code ?? 0,
                    stdout: data.stdout,
                    stderr: data.stderr,
                    timestamp: Date.now(),
                },
            });
            terminalData.delete(terminal.name);
        }
    });
}
```

### If Events ARE Being Sent:

1. Check if they're being received in the WebSocket client logs
2. Check if they're being parsed correctly
3. Check if the TerminalOutputNotifier listener is active

---

## 📞 Support

If after following this checklist you still don't receive events:

1. Share the logs from running the debug example
2. Confirm whether the VS Code bridge extension has terminal event broadcasting
3. Check if there are any errors in VS Code's Output panel (View → Output → WebSocket Bridge)

---

## Summary

The most likely issue is that **the VS Code WebSocket Bridge extension is not yet sending these events**. The PROTOCOL.md documents the expected behavior, but the extension code needs to implement it.

Check the extension code first before debugging the Flutter side further.
