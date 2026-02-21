import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/highlight.dart' show Mode;
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/ruby.dart';
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/sql.dart';
import '../../state/app_controller.dart';

/// Code editor view with syntax highlighting
class CodeEditorView extends ConsumerStatefulWidget {
  const CodeEditorView({super.key});

  @override
  ConsumerState<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends ConsumerState<CodeEditorView> {
  final Map<String, CodeController> _controllers = {};
  Timer? _saveDebouncer;
  bool _isDarkMode = true;

  @override
  void dispose() {
    _saveDebouncer?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeFilePath = ref.watch(activeFilePathProvider);
    final openFiles = ref.watch(openFilesProvider);

    if (activeFilePath == null || !openFiles.containsKey(activeFilePath)) {
      return _buildEmptyState(context);
    }

    final file = openFiles[activeFilePath]!;
    final controller = _getOrCreateController(file.path, file.content, file.languageId);

    return Column(
      children: [
        _buildHeader(context, file),
        Expanded(
          child: _buildEditor(context, controller, file),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, OpenFile file) {
    final fileName = file.path.split('/').last;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          Icon(
            _getFileIcon(fileName),
            size: 18,
            color: _getFileIconColor(fileName),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  file.path,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (file.isModified)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
          IconButton(
            icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode, size: 18),
            tooltip: 'Toggle theme',
            onPressed: () {
              setState(() {
                _isDarkMode = !_isDarkMode;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.save, size: 18),
            tooltip: 'Save (Ctrl+S)',
            onPressed: file.isModified ? () => _saveFile(file.path) : null,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close',
            onPressed: () => _closeFile(file.path),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context, CodeController controller, OpenFile file) {
    return Container(
      color: _isDarkMode ? const Color(0xFF272822) : Colors.white,
      child: CodeTheme(
        data: CodeThemeData(
          styles: _isDarkMode ? monokaiSublimeTheme : githubTheme,
        ),
        child: SingleChildScrollView(
          child: CodeField(
            controller: controller,
            textStyle: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            lineNumberStyle: LineNumberStyle(
              width: 48,
              textStyle: TextStyle(
                color: _isDarkMode ? Colors.grey.shade600 : Colors.grey.shade400,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final openFiles = ref.watch(openFilesProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.code,
              size: 64,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              openFiles.isEmpty ? 'No files open' : 'Select a file from workspace',
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

  CodeController _getOrCreateController(String path, String content, String languageId) {
    if (_controllers.containsKey(path)) {
      final controller = _controllers[path]!;

      // Update content if it changed externally (e.g., from VS Code)
      if (controller.text != content) {
        controller.text = content;
      }

      return controller;
    }

    final controller = CodeController(
      text: content,
      language: _getLanguageMode(languageId),
    );

    // Listen for changes with debouncing
    controller.addListener(() {
      _handleTextChange(path, controller.text);
    });

    _controllers[path] = controller;
    return controller;
  }

  void _handleTextChange(String path, String newContent) {
    // Update local state
    ref.read(openFilesProvider.notifier).updateContent(path, newContent);

    // Debounce save to VS Code
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(milliseconds: 1500), () {
      _saveFile(path);
    });
  }

  Future<void> _saveFile(String path) async {
    try {
      await ref.read(openFilesProvider.notifier).saveFile(path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File saved'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  void _closeFile(String path) {
    final file = ref.read(openFilesProvider)[path];

    if (file?.isModified ?? false) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text('Do you want to save changes before closing?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _controllers.remove(path)?.dispose();
                ref.read(openFilesProvider.notifier).closeFile(path);
              },
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _saveFile(path);
                _controllers.remove(path)?.dispose();
                ref.read(openFilesProvider.notifier).closeFile(path);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } else {
      _controllers.remove(path)?.dispose();
      ref.read(openFilesProvider.notifier).closeFile(path);
    }
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();

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
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();

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
        return Colors.grey;
    }
  }

  Mode? _getLanguageMode(String languageId) {
    switch (languageId) {
      case 'dart':
        return dart;
      case 'javascript':
      case 'javascriptreact':
        return javascript;
      case 'typescript':
      case 'typescriptreact':
        return typescript;
      case 'python':
        return python;
      case 'java':
        return java;
      case 'go':
        return go;
      case 'cpp':
      case 'c':
        return cpp;
      case 'csharp':
        return cs;
      case 'ruby':
        return ruby;
      case 'php':
        return php;
      case 'json':
        return json;
      case 'xml':
      case 'html':
        return xml;
      case 'yaml':
        return yaml;
      case 'markdown':
        return markdown;
      case 'sql':
        return sql;
      default:
        return null;
    }
  }
}
