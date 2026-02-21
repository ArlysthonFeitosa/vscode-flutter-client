import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/protocol_message.dart';
import '../../state/app_controller.dart';
import '../../core/websocket/ws_client.dart' show WSConnectionState;

/// Workspace explorer widget
/// Displays the file tree and allows navigation
class WorkspaceExplorer extends ConsumerWidget {
  const WorkspaceExplorer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(workspaceTreeProvider);
    final isConnected = ref.watch(connectionStateProvider).value == WSConnectionState.connected;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(context, ref, isConnected),
          Expanded(
            child: tree.isEmpty ? _buildEmptyState(context, isConnected) : _buildTree(context, ref, tree),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, bool isConnected) {
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
          const Icon(Icons.folder, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Workspace',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Refresh',
              onPressed: () {
                ref.read(workspaceTreeProvider.notifier).refresh();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isConnected) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              isConnected ? 'No workspace loaded' : 'Not connected',
              style: TextStyle(
                color: Theme.of(context).disabledColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTree(BuildContext context, WidgetRef ref, List<FileTreeNode> tree) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: tree.map((node) => _FileTreeNodeWidget(node: node)).toList(),
    );
  }
}

/// File tree node widget
class _FileTreeNodeWidget extends ConsumerStatefulWidget {
  final FileTreeNode node;
  final int depth;

  const _FileTreeNodeWidget({
    required this.node,
    this.depth = 0,
  });

  @override
  ConsumerState<_FileTreeNodeWidget> createState() => _FileTreeNodeWidgetState();
}

class _FileTreeNodeWidgetState extends ConsumerState<_FileTreeNodeWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final activeFilePath = ref.watch(activeFilePathProvider);
    final isActive = activeFilePath == widget.node.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _handleTap(context),
          child: Container(
            padding: EdgeInsets.only(
              left: widget.depth * 16.0,
              top: 4,
              bottom: 4,
              right: 8,
            ),
            color: isActive ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
            child: Row(
              children: [
                if (widget.node.isDirectory)
                  Icon(
                    _isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                    size: 20,
                  )
                else
                  const SizedBox(width: 20),
                Icon(
                  _getIcon(),
                  size: 16,
                  color: _getIconColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.node.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded && widget.node.children != null)
          ...widget.node.children!.map(
            (child) => _FileTreeNodeWidget(
              node: child,
              depth: widget.depth + 1,
            ),
          ),
      ],
    );
  }

  void _handleTap(BuildContext context) {
    if (widget.node.isDirectory) {
      setState(() {
        _isExpanded = !_isExpanded;
      });
    } else {
      // Open file
      ref.read(openFilesProvider.notifier).openFile(widget.node.path).catchError((error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open file: $error')),
        );
      });
    }
  }

  IconData _getIcon() {
    if (widget.node.isDirectory) {
      return _isExpanded ? Icons.folder_open : Icons.folder;
    }

    // Determine icon based on file extension
    final ext = widget.node.name.split('.').last.toLowerCase();

    switch (ext) {
      case 'dart':
        return Icons.code;
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
        return Icons.javascript;
      case 'json':
        return Icons.data_object;
      case 'yaml':
      case 'yml':
        return Icons.settings;
      case 'md':
        return Icons.article;
      case 'html':
      case 'css':
      case 'scss':
        return Icons.web;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getIconColor(BuildContext context) {
    if (widget.node.isDirectory) {
      return Colors.amber;
    }

    final ext = widget.node.name.split('.').last.toLowerCase();

    switch (ext) {
      case 'dart':
        return Colors.blue;
      case 'js':
      case 'ts':
        return Colors.yellow.shade700;
      case 'json':
        return Colors.orange;
      case 'md':
        return Colors.purple;
      case 'html':
        return Colors.red;
      case 'css':
      case 'scss':
        return Colors.blue;
      default:
        return Theme.of(context).iconTheme.color ?? Colors.grey;
    }
  }
}
