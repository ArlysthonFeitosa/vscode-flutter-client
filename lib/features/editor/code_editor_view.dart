import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
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
import '../../core/theme/vscode_theme.dart';
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
    final controller =
        _getOrCreateController(file.path, file.content, file.languageId);

    return Container(
      color: VSCodeColors.editorBackground,
      child: Column(
        children: [
          // Breadcrumb bar
          _buildBreadcrumb(file),
          // Editor
          Expanded(
            child: _buildEditor(context, controller, file),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(OpenFile file) {
    final parts = file.path.split(RegExp(r'[/\\]'));

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: VSCodeColors.editorBackground,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < parts.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: VSCodeColors.sideBarForeground,
                        ),
                      ),
                    Text(
                      parts[i],
                      style: TextStyle(
                        color: i == parts.length - 1
                            ? VSCodeColors.editorForeground
                            : VSCodeColors.sideBarForeground,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Save indicator
          if (file.isModified)
            Tooltip(
              message: 'Unsaved changes (Ctrl+S to save)',
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  color: VSCodeColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditor(
      BuildContext context, CodeController controller, OpenFile file) {
    return RawKeyboardListener(
      focusNode: FocusNode(),
      onKey: (event) {
        // Handle Ctrl+S for save
        if (event is RawKeyDownEvent &&
            event.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyS) {
          _saveFile(file.path);
        }
      },
      child: CodeTheme(
        data: CodeThemeData(
          styles: monokaiSublimeTheme,
        ),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicWidth(
              child: CodeField(
                controller: controller,
                textStyle: const TextStyle(
                  fontFamily: 'Consolas, Monaco, monospace',
                  fontSize: 14,
                  height: 1.5,
                ),
                lineNumberStyle: const LineNumberStyle(
                  width: 50,
                  margin: 8,
                  textStyle: TextStyle(
                    color: VSCodeColors.editorLineNumber,
                    fontSize: 12,
                    fontFamily: 'Consolas, Monaco, monospace',
                  ),
                ),
                background: VSCodeColors.editorBackground,
                expands: false,
                wrap: false,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      color: VSCodeColors.editorBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.code,
              size: 64,
              color: VSCodeColors.sideBarForeground.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No file open',
              style: TextStyle(
                color: VSCodeColors.sideBarForeground.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a file from the explorer to start editing',
              style: TextStyle(
                color: VSCodeColors.sideBarForeground.withOpacity(0.3),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            _buildShortcutHint('Ctrl+S', 'Save file'),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutHint(String shortcut, String action) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: VSCodeColors.inputBackground,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: VSCodeColors.divider),
          ),
          child: Text(
            shortcut,
            style: const TextStyle(
              color: VSCodeColors.sideBarForeground,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          action,
          style: TextStyle(
            color: VSCodeColors.sideBarForeground.withOpacity(0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  CodeController _getOrCreateController(
      String path, String content, String languageId) {
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

    // Debounce auto-save
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(seconds: 2), () {
      _saveFile(path);
    });
  }

  Future<void> _saveFile(String path) async {
    try {
      await ref.read(openFilesProvider.notifier).saveFile(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: VSCodeColors.errorForeground,
          ),
        );
      }
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
