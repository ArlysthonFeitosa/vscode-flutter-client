import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/protocol_message.dart';
import '../../core/theme/vscode_theme.dart';
import '../../state/app_controller.dart';
import '../../core/websocket/ws_client.dart';

/// Workspace explorer widget
/// Displays the file tree and allows navigation
class WorkspaceExplorer extends ConsumerWidget {
  const WorkspaceExplorer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(workspaceTreeProvider);
    final connectionState = ref.watch(connectionStateProvider).value;
    final isConnected = connectionState == WSConnectionState.connected;

    return Column(
      children: [
        _buildWorkspaceHeader(context, ref, isConnected),
        Expanded(
          child: tree.isEmpty
              ? _buildEmptyState(context, isConnected)
              : _buildTree(context, ref, tree),
        ),
      ],
    );
  }

  Widget _buildWorkspaceHeader(
      BuildContext context, WidgetRef ref, bool isConnected) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'WORKSPACE',
              style: TextStyle(
                color: VSCodeColors.sideBarForeground,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isConnected) ...[
            _buildHeaderAction(
              icon: Icons.create_new_folder_outlined,
              tooltip: 'New Folder',
              onTap: () => _showCreateDialog(context, ref, isFolder: true),
            ),
            _buildHeaderAction(
              icon: Icons.note_add_outlined,
              tooltip: 'New File',
              onTap: () => _showCreateDialog(context, ref, isFolder: false),
            ),
            _buildHeaderAction(
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onTap: () => ref.read(workspaceTreeProvider.notifier).refresh(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size: 16,
            color: VSCodeColors.sideBarForeground,
          ),
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref,
      {required bool isFolder}) {
    final controller = TextEditingController();
    final title = isFolder ? 'New Folder' : 'New File';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isFolder ? 'Folder name' : 'File name',
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              Navigator.of(context).pop();
              _createItem(ref, value, isFolder: isFolder);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.of(context).pop();
                _createItem(ref, controller.text, isFolder: isFolder);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createItem(WidgetRef ref, String name,
      {required bool isFolder}) async {
    try {
      final client = ref.read(wsClientProvider);
      if (isFolder) {
        await client.createDirectory(name);
      } else {
        await client.writeFile(name, '', createDirectories: true);
      }
      // Refresh tree after creation
      ref.read(workspaceTreeProvider.notifier).refresh();
    } catch (e) {
      debugPrint('Failed to create ${isFolder ? 'folder' : 'file'}: $e');
    }
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
              size: 48,
              color: VSCodeColors.sideBarForeground.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              isConnected ? 'No folder opened' : 'Not connected',
              style: TextStyle(
                color: VSCodeColors.sideBarForeground.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
            if (!isConnected) ...[
              const SizedBox(height: 8),
              Text(
                'Connect to VS Code to browse files',
                style: TextStyle(
                  color: VSCodeColors.sideBarForeground.withOpacity(0.5),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTree(
      BuildContext context, WidgetRef ref, List<FileTreeNode> tree) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: tree.length,
      itemBuilder: (context, index) => _FileTreeNodeWidget(
        node: tree[index],
        depth: 0,
      ),
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
  ConsumerState<_FileTreeNodeWidget> createState() =>
      _FileTreeNodeWidgetState();
}

class _FileTreeNodeWidgetState extends ConsumerState<_FileTreeNodeWidget> {
  bool _isExpanded = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final activeFilePath = ref.watch(activeFilePathProvider);
    final isActive = activeFilePath == widget.node.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: () => _handleTap(context),
            onSecondaryTapDown: (details) =>
                _showContextMenu(context, details.globalPosition),
            onLongPress: () => _showContextMenu(
              context,
              Offset(
                MediaQuery.of(context).size.width / 2,
                MediaQuery.of(context).size.height / 2,
              ),
            ),
            child: Container(
              height: 22,
              padding: EdgeInsets.only(
                left: 8 + widget.depth * 12.0,
                right: 8,
              ),
              color: isActive
                  ? VSCodeColors.listActiveSelectionBackground
                  : _isHovered
                      ? VSCodeColors.listHoverBackground
                      : Colors.transparent,
              child: Row(
                children: [
                  // Expand/collapse arrow for directories
                  if (widget.node.isDirectory)
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 16,
                      color: VSCodeColors.sideBarForeground,
                    )
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 2),
                  // File/folder icon
                  Icon(
                    _getIcon(),
                    size: 16,
                    color: _getIconColor(),
                  ),
                  const SizedBox(width: 6),
                  // File name
                  Expanded(
                    child: Text(
                      widget.node.name,
                      style: TextStyle(
                        color: isActive
                            ? Colors.white
                            : VSCodeColors.sideBarForeground,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Actions on hover
                  if (_isHovered) ...[
                    _buildActionButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete',
                      onTap: () => _confirmDelete(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Children
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

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size: 14,
            color: VSCodeColors.sideBarForeground,
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        if (widget.node.isDirectory) ...[
          const PopupMenuItem(
            value: 'new_file',
            child: Row(
              children: [
                Icon(Icons.note_add_outlined, size: 16),
                SizedBox(width: 8),
                Text('New File'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'new_folder',
            child: Row(
              children: [
                Icon(Icons.create_new_folder_outlined, size: 16),
                SizedBox(width: 8),
                Text('New Folder'),
              ],
            ),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'new_file':
          _showCreateInFolderDialog(context, isFolder: false);
          break;
        case 'new_folder':
          _showCreateInFolderDialog(context, isFolder: true);
          break;
        case 'delete':
          _confirmDelete(context);
          break;
      }
    });
  }

  void _showCreateInFolderDialog(BuildContext context,
      {required bool isFolder}) {
    final controller = TextEditingController();
    final title = isFolder ? 'New Folder' : 'New File';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create in: ${widget.node.path}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: isFolder ? 'Folder name' : 'File name',
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  Navigator.of(context).pop();
                  _createInFolder(value, isFolder: isFolder);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.of(context).pop();
                _createInFolder(controller.text, isFolder: isFolder);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createInFolder(String name, {required bool isFolder}) async {
    try {
      final client = ref.read(wsClientProvider);
      final path = '${widget.node.path}/$name';
      if (isFolder) {
        await client.createDirectory(path);
      } else {
        await client.writeFile(path, '', createDirectories: true);
      }
      // Refresh tree after creation
      ref.read(workspaceTreeProvider.notifier).refresh();
      // Expand folder to show new item
      setState(() => _isExpanded = true);
    } catch (e) {
      debugPrint('Failed to create ${isFolder ? 'folder' : 'file'}: $e');
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete'),
        content: Text(
          'Are you sure you want to delete "${widget.node.name}"?'
          '${widget.node.isDirectory ? '\n\nThis will delete all contents inside.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteItem();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem() async {
    try {
      final client = ref.read(wsClientProvider);
      await client.deleteFile(widget.node.path, recursive: true);
      // Refresh tree after deletion
      ref.read(workspaceTreeProvider.notifier).refresh();
    } catch (e) {
      debugPrint('Failed to delete: $e');
    }
  }

  void _handleTap(BuildContext context) {
    if (widget.node.isDirectory) {
      setState(() {
        _isExpanded = !_isExpanded;
      });
    } else {
      // Open file
      ref
          .read(openFilesProvider.notifier)
          .openFile(widget.node.path)
          .catchError((error) {
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

  Color _getIconColor() {
    if (widget.node.isDirectory) {
      return const Color(0xFFDCB67A); // Folder color
    }

    final ext = widget.node.name.split('.').last.toLowerCase();

    switch (ext) {
      case 'dart':
        return const Color(0xFF61DAFB);
      case 'js':
      case 'jsx':
        return const Color(0xFFF7DF1E);
      case 'ts':
      case 'tsx':
        return const Color(0xFF3178C6);
      case 'json':
        return const Color(0xFFCBCB41);
      case 'md':
        return const Color(0xFF519ABA);
      case 'html':
        return const Color(0xFFE34C26);
      case 'css':
      case 'scss':
        return const Color(0xFF563D7C);
      case 'yaml':
      case 'yml':
        return const Color(0xFFCB171E);
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
        return const Color(0xFF8BC34A);
      default:
        return VSCodeColors.sideBarForeground;
    }
  }
}
