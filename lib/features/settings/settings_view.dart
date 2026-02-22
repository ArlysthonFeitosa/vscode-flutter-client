import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../state/app_controller.dart';
import '../../core/websocket/ws_client.dart' show WSConnectionState;

/// Settings view for configuring connection
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tokenController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(connectionConfigProvider);
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: config.port.toString());
    _tokenController = TextEditingController(text: config.token);
    _loadSettings();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString('ws_host') ?? 'localhost';
      final port = prefs.getInt('ws_port') ?? 8080;
      final token = prefs.getString('ws_token') ?? 'your-secret-token-here';

      _hostController.text = host;
      _portController.text = port.toString();
      _tokenController.text = token;

      // Update provider
      ref.read(connectionConfigProvider.notifier).state = ConnectionConfig(
        host: host,
        port: port,
        token: token,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = _hostController.text.trim();
      final port = int.parse(_portController.text.trim());
      final token = _tokenController.text.trim();

      await prefs.setString('ws_host', host);
      await prefs.setInt('ws_port', port);
      await prefs.setString('ws_token', token);

      // Update provider
      ref.read(connectionConfigProvider.notifier).state = ConnectionConfig(
        host: host,
        port: port,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider).value;
    final isConnected = connectionState == WSConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildConnectionStatus(connectionState),
                    const SizedBox(height: 24),
                    _buildTextField(
                      controller: _hostController,
                      label: 'Host',
                      hint: 'localhost',
                      icon: Icons.computer,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a host';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _portController,
                      label: 'Port',
                      hint: '8080',
                      icon: Icons.numbers,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a port';
                        }
                        final port = int.tryParse(value);
                        if (port == null || port < 1 || port > 65535) {
                          return 'Please enter a valid port (1-65535)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _tokenController,
                      label: 'Authentication Token',
                      hint: 'your-secret-token',
                      icon: Icons.lock,
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter an authentication token';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saveSettings,
                            icon: const Icon(Icons.save),
                            label: const Text('Save Settings'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isConnected
                                ? () =>
                                    ref.read(appControllerProvider).disconnect()
                                : () =>
                                    ref.read(appControllerProvider).connect(),
                            icon: Icon(
                                isConnected ? Icons.close : Icons.play_arrow),
                            label: Text(isConnected ? 'Disconnect' : 'Connect'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  isConnected ? Colors.red : Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _buildInfoSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildConnectionStatus(WSConnectionState? state) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (state) {
      case WSConnectionState.connected:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Connected';
        break;
      case WSConnectionState.connecting:
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        statusText = 'Connecting...';
        break;
      case WSConnectionState.authenticating:
        statusColor = Colors.orange;
        statusIcon = Icons.security;
        statusText = 'Authenticating...';
        break;
      case WSConnectionState.reconnecting:
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        statusText = 'Reconnecting...';
        break;
      case WSConnectionState.error:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = 'Connection Error';
        break;
      case WSConnectionState.disconnected:
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.cancel;
        statusText = 'Disconnected';
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connection Status',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
    );
  }

  Widget _buildInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  'How to Connect',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '1. Install the VS Code WebSocket Bridge extension\n'
              '2. Configure the extension with a secret token\n'
              '3. Start VS Code with the extension enabled\n'
              '4. Enter the same token here and connect',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.security, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Security Note',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your authentication token is stored locally and transmitted securely. '
              'Never share your token with untrusted parties.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
