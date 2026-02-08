import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

class ChatInput extends ConsumerStatefulWidget {
  final Future<void> Function(
    String text, {
    List<Map<String, dynamic>>? fileParts,
  })
  onSendMessage;
  final Future<void> Function(String command, String arguments) onSendCommand;
  final VoidCallback? onStop;
  final bool isBusy;
  final bool enabled;

  const ChatInput({
    super.key,
    required this.onSendMessage,
    required this.onSendCommand,
    this.onStop,
    this.isBusy = false,
    this.enabled = true,
  });

  @override
  ConsumerState<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();

  OverlayEntry? _overlayEntry;
  String _overlayMode = ''; // 'file' or 'command'
  String _searchQuery = '';
  int _triggerPosition = -1;
  final List<Map<String, dynamic>> _attachedFiles = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;

    if (cursorPos <= 0 || text.isEmpty) {
      _removeOverlay();
      return;
    }

    // Check for "@" trigger
    final beforeCursor = text.substring(0, cursorPos);
    final lastAt = beforeCursor.lastIndexOf('@');
    final lastSlash = beforeCursor.lastIndexOf('/');

    if (lastAt >= 0 && (lastAt == 0 || text[lastAt - 1] == ' ')) {
      final query = beforeCursor.substring(lastAt + 1);
      if (!query.contains(' ') || query.length < 50) {
        _triggerPosition = lastAt;
        _searchQuery = query;
        _overlayMode = 'file';
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), () {
          _showOverlay();
        });
        return;
      }
    }

    if (lastSlash >= 0 &&
        (lastSlash == 0 || text[lastSlash - 1] == ' ') &&
        beforeCursor.startsWith('/')) {
      final query = beforeCursor.substring(lastSlash + 1);
      if (!query.contains(' ')) {
        _triggerPosition = lastSlash;
        _searchQuery = query;
        _overlayMode = 'command';
        _showOverlay();
        return;
      }
    }

    if (_overlayEntry != null && _overlayMode == 'file') {
      if (lastAt >= 0 && lastAt == _triggerPosition) {
        _searchQuery = beforeCursor.substring(lastAt + 1);
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), () {
          _showOverlay();
        });
        return;
      }
    }

    if (_overlayEntry != null && _overlayMode == 'command') {
      if (lastSlash >= 0 && lastSlash == _triggerPosition) {
        _searchQuery = beforeCursor.substring(lastSlash + 1);
        _showOverlay();
        return;
      }
    }

    _removeOverlay();
  }

  void _showOverlay() {
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) => _OverlayContent(
        mode: _overlayMode,
        query: _searchQuery,
        layerLink: _layerLink,
        onSelectFile: _onFileSelected,
        onSelectCommand: _onCommandSelected,
        onDismiss: _removeOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onFileSelected(String filePath) {
    _removeOverlay();

    final text = _controller.text;
    final before = text.substring(0, _triggerPosition);
    final cursorPos = _controller.selection.baseOffset;
    final after = text.substring(cursorPos);

    _controller.text = '$before$after';
    _controller.selection = TextSelection.collapsed(offset: before.length);

    setState(() {
      final project = ref.read(selectedProjectProvider);
      var path = filePath;

      if (!path.startsWith('/') && project != null) {
        if (project.worktree.endsWith('/')) {
          path = '${project.worktree}$path';
        } else {
          path = '${project.worktree}/$path';
        }
      }

      if (!path.startsWith('/')) {
        path = '/$path';
      }

      _attachedFiles.add({
        'type': 'file',
        'mime': 'text/plain',
        'url': 'file://$path',
        'filename': filePath.split('/').last,
      });
    });
  }

  void _onCommandSelected(String commandName) {
    _removeOverlay();

    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    final after = text.substring(cursorPos);
    final remaining = after.trim();

    widget.onSendCommand(commandName, remaining);
    _controller.clear();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachedFiles.isEmpty) return;

    widget.onSendMessage(
      text,
      fileParts: _attachedFiles.isNotEmpty ? List.from(_attachedFiles) : null,
    );
    _controller.clear();
    setState(() {
      _attachedFiles.clear();
    });
  }

  void _removeFile(int index) {
    setState(() {
      _attachedFiles.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_attachedFiles.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppTheme.border, width: 0.5),
                    ),
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _attachedFiles.asMap().entries.map((entry) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.insert_drive_file,
                              size: 12,
                              color: AppTheme.info,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              entry.value['filename'] as String? ?? 'file',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _removeFile(entry.key),
                              child: const Icon(
                                Icons.close,
                                size: 12,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: widget.enabled,
                          maxLines: null,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.isBusy
                                ? 'Processing...'
                                : 'Message... (@ files, / commands)',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            fillColor: Colors.transparent,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: widget.isBusy
                          ? widget.onStop
                          : (widget.enabled ? _send : null),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: widget.isBusy
                              ? AppTheme.error
                              : (widget.enabled
                                    ? AppTheme.accent
                                    : AppTheme.border),
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          widget.isBusy ? Icons.stop : Icons.arrow_upward,
                          size: 18,
                          color: widget.isBusy || widget.enabled
                              ? Colors.white
                              : AppTheme.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayContent extends ConsumerWidget {
  final String mode;
  final String query;
  final LayerLink layerLink;
  final void Function(String) onSelectFile;
  final void Function(String) onSelectCommand;
  final VoidCallback onDismiss;

  const _OverlayContent({
    required this.mode,
    required this.query,
    required this.layerLink,
    required this.onSelectFile,
    required this.onSelectCommand,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onDismiss,
        behavior: HitTestBehavior.translucent,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: CompositedTransformFollower(
            link: layerLink,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 250, maxWidth: 400),
              margin: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: mode == 'file'
                    ? _FileSearchList(query: query, onSelect: onSelectFile)
                    : _CommandList(query: query, onSelect: onSelectCommand),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileSearchList extends ConsumerWidget {
  final String query;
  final void Function(String) onSelect;

  const _FileSearchList({required this.query, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Type to search files...',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      );
    }

    final filesAsync = ref.watch(fileSearchProvider(query));

    return filesAsync.when(
      data: (files) {
        if (files.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No files found',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            final fileName = file.split('/').last;

            return GestureDetector(
              onTap: () => onSelect(file),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            file,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Search failed',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _CommandList extends ConsumerWidget {
  final String query;
  final void Function(String) onSelect;

  const _CommandList({required this.query, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commandsAsync = ref.watch(commandsProvider);
    final skillsAsync = ref.watch(skillsProvider);

    return commandsAsync.when(
      data: (commands) {
        final skills = skillsAsync.valueOrNull ?? [];

        final allItems = <Map<String, dynamic>>[];

        for (final cmd in commands) {
          allItems.add({
            'name': cmd.name,
            'description': cmd.description,
            'type': 'command',
            'source': cmd.source ?? 'command',
          });
        }

        for (final skill in skills) {
          allItems.add({
            'name': skill['name'] ?? '',
            'description': skill['description'] ?? '',
            'type': 'skill',
            'source': 'skill',
          });
        }

        final filtered = query.isEmpty
            ? allItems
            : allItems.where((item) {
                final name = (item['name'] as String).toLowerCase();
                return name.contains(query.toLowerCase());
              }).toList();

        if (filtered.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No commands found',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final item = filtered[index];
            final isSkill = item['type'] == 'skill';

            return GestureDetector(
              onTap: () => onSelect(item['name'] as String),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSkill ? Icons.auto_awesome : Icons.terminal,
                      size: 14,
                      color: isSkill
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '/${item['name']}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 12,
                            ),
                          ),
                          if ((item['description'] as String?)?.isNotEmpty ??
                              false)
                            Text(
                              item['description'] as String,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      child: Text(
                        (item['source'] as String? ?? '').toUpperCase(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Failed to load commands',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
