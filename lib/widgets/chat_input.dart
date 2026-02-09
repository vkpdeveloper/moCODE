import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../constants/file_icons.dart';

class ChatInput extends ConsumerStatefulWidget {
  final Future<bool> Function(
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

  static void appendText(BuildContext context, String text) {
    final state = context.findAncestorStateOfType<_ChatInputState>();
    if (state == null) return;
    state._appendText(text);
  }

  static void restoreDraft(
    BuildContext context,
    String text,
    List<Map<String, dynamic>> fileParts,
  ) {
    final state = context.findAncestorStateOfType<_ChatInputState>();
    if (state == null) return;
    state._setDraft(text, fileParts);
  }
}

class _ChatInputState extends ConsumerState<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();

  OverlayEntry? _overlayEntry;
  String _overlayMode = ''; // 'file' or 'command'
  String _searchQuery = '';
  int _triggerPosition = -1;
  bool _suppressOverlay = false;
  final List<Map<String, dynamic>> _attachedFiles = [];
  final ImagePicker _imagePicker = ImagePicker();
  final List<_ImageAttachment> _attachedImages = [];
  Timer? _debounce;
  bool _isPickingImages = false;

  static const int _maxAttachmentBase64Length = 10 * 1024 * 1024;

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
      _suppressOverlay = false;
      _removeOverlay();
      return;
    }

    if (_suppressOverlay) {
      final shouldRelease =
          cursorPos >= 2 &&
          text[cursorPos - 2] == ' ' &&
          (text[cursorPos - 1] == '@' || text[cursorPos - 1] == '/');
      if (!shouldRelease) {
        _removeOverlay();
        return;
      }
      _suppressOverlay = false;
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
        final query = beforeCursor.substring(lastAt + 1);
        if (query.contains(' ')) {
          _removeOverlay();
          return;
        }
        _searchQuery = query;
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
    _suppressOverlay = true;

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

    var displayPath = filePath;
    if (project != null) {
      final worktree = project.worktree.endsWith('/')
          ? project.worktree
          : '${project.worktree}/';
      if (path.startsWith(worktree)) {
        displayPath = path.substring(worktree.length);
      }
    }
    if (displayPath.startsWith('/')) {
      displayPath = displayPath.substring(1);
    }

    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    var triggerPos = _triggerPosition;
    if (triggerPos < 0 || triggerPos > text.length) {
      final lookupIndex = cursorPos > 0 ? cursorPos - 1 : text.length - 1;
      triggerPos = text.lastIndexOf('@', lookupIndex);
    }
    if (triggerPos < 0) {
      triggerPos = cursorPos.clamp(0, text.length);
    }
    final before = text.substring(0, triggerPos);
    final after = text.substring(cursorPos);
    final insertion = '@$displayPath';
    final needsSpace = after.isEmpty || !after.startsWith(' ');
    final next = '$before$insertion${needsSpace ? ' ' : ''}$after';

    _controller.text = next;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _triggerPosition = -1;

    setState(() {
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
    _suppressOverlay = true;
    _triggerPosition = -1;

    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    final after = text.substring(cursorPos);
    final remaining = after.trim();

    widget.onSendCommand(commandName, remaining);
    _controller.clear();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  Future<void> _send() async {
    final rawText = _controller.text;
    final text = rawText.trim();
    if (text.isEmpty && _attachedFiles.isEmpty && _attachedImages.isEmpty) {
      return;
    }

    if (_totalImageBase64Length() > _maxAttachmentBase64Length) {
      _showSizeLimitSnack();
      return;
    }

    final fileParts = _buildFileParts();
    final draftParts = fileParts ?? const <Map<String, dynamic>>[];
    final draftText = rawText;
    _controller.clear();
    setState(() {
      _attachedFiles.clear();
      _attachedImages.clear();
    });
    var success = false;
    try {
      success = await widget.onSendMessage(text, fileParts: fileParts);
    } catch (_) {
      success = false;
    }

    if (!success) {
      _setDraft(draftText, draftParts);
    }
  }

  void _appendText(String text) {
    if (text.isEmpty) return;
    final selection = _controller.selection;
    final base = selection.baseOffset < 0
        ? _controller.text.length
        : selection.baseOffset;
    final extent = selection.extentOffset < 0
        ? _controller.text.length
        : selection.extentOffset;
    final start = base < extent ? base : extent;
    final end = base < extent ? extent : base;
    final current = _controller.text;
    final before = current.substring(0, start);
    final after = current.substring(end);
    final next = '$before$text$after';
    _controller.text = next;
    final cursor = (before + text).length;
    _controller.selection = TextSelection.collapsed(offset: cursor);
    _focusNode.requestFocus();
  }

  void _setDraft(String text, List<Map<String, dynamic>> fileParts) {
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() {
      _attachedFiles
        ..clear()
        ..addAll(
          fileParts.where(
            (part) => part['url']?.toString().startsWith('data:') != true,
          ),
        );
      _attachedImages
        ..clear()
        ..addAll(
          fileParts
              .where(
                (part) => part['url']?.toString().startsWith('data:') == true,
              )
              .map(_ImageAttachment.fromPart),
        );
    });
    _focusNode.requestFocus();
  }

  void _removeFile(int index) {
    setState(() {
      _attachedFiles.removeAt(index);
    });
  }

  void _removeImage(int index) {
    setState(() {
      _attachedImages.removeAt(index);
    });
  }

  int _totalImageBase64Length() {
    var total = 0;
    for (final image in _attachedImages) {
      total += image.base64Length;
    }
    return total;
  }

  void _showSizeLimitSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Image attachments must be under 10 MB total.'),
      ),
    );
  }

  Future<void> _openImagePicker() async {
    if (_isPickingImages) return;
    if (!mounted) return;
    setState(() => _isPickingImages = true);
    try {
      final picked = await _imagePicker.pickMultiImage();
      if (!mounted || picked.isEmpty) return;
      await _showImagePreview(picked);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to pick images.')));
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImages = false);
      }
    }
  }

  Future<void> _showImagePreview(List<XFile> files) async {
    if (!mounted) return;
    final newImages = await _loadImageAttachments(files);
    if (!mounted || newImages.isEmpty) return;

    final preview = List<_ImageAttachment>.from(newImages);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _ImagePreviewDialog(
          images: preview,
          onRemove: (index) => preview.removeAt(index),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final totalBase64 =
        _totalImageBase64Length() +
        preview.fold<int>(0, (sum, item) => sum + item.base64Length);
    if (totalBase64 > _maxAttachmentBase64Length) {
      _showSizeLimitSnack();
      return;
    }

    setState(() {
      _attachedImages.addAll(preview);
    });
  }

  Future<List<_ImageAttachment>> _loadImageAttachments(
    List<XFile> files,
  ) async {
    final attachments = <_ImageAttachment>[];
    for (final file in files) {
      try {
        final bytes = await file.readAsBytes();
        final name = file.name.isNotEmpty
            ? file.name
            : file.path.split('/').last;
        final mime = file.mimeType ?? _guessImageMime(name);
        final base64Data = base64Encode(bytes);
        final uri = 'data:$mime;base64,$base64Data';
        attachments.add(
          _ImageAttachment(
            name: name,
            mime: mime,
            bytes: bytes,
            dataUri: uri,
            base64Length: base64Data.length,
          ),
        );
      } catch (_) {
        // ignore individual failures
      }
    }
    return attachments;
  }

  String _guessImageMime(String name) {
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      _ => 'image/*',
    };
  }

  List<Map<String, dynamic>>? _buildFileParts() {
    final parts = <Map<String, dynamic>>[];
    if (_attachedFiles.isNotEmpty) {
      parts.addAll(List<Map<String, dynamic>>.from(_attachedFiles));
    }

    for (final image in _attachedImages) {
      parts.add({
        'type': 'file',
        'mime': image.mime,
        'url': image.dataUri,
        'filename': image.name,
      });
    }

    return parts.isEmpty ? null : parts;
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
              if (_attachedFiles.isNotEmpty || _attachedImages.isNotEmpty)
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
                    children: [
                      ..._attachedFiles.asMap().entries.map((entry) {
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
                              Icon(
                                getIconForExtension(
                                  (entry.value['filename'] as String? ?? 'file')
                                      .split('.')
                                      .last,
                                ),
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
                      }),
                      ..._attachedImages.asMap().entries.map((entry) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: Image.memory(
                                  entry.value.bytes,
                                  width: 14,
                                  height: 14,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                entry.value.name,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _removeImage(entry.key),
                                child: const Icon(
                                  Icons.close,
                                  size: 12,
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: widget.enabled ? _openImagePicker : null,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      tooltip: 'Attach images',
                    ),
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

class _ImageAttachment {
  final String name;
  final String mime;
  final Uint8List bytes;
  final String dataUri;
  final int base64Length;

  const _ImageAttachment({
    required this.name,
    required this.mime,
    required this.bytes,
    required this.dataUri,
    required this.base64Length,
  });

  factory _ImageAttachment.fromPart(Map<String, dynamic> part) {
    final dataUri = part['url']?.toString() ?? '';
    final mime = part['mime']?.toString() ?? 'image/*';
    final name = part['filename']?.toString() ?? 'image';
    final base64Data = dataUri.contains(',')
        ? dataUri.substring(dataUri.indexOf(',') + 1)
        : '';
    Uint8List bytes;
    if (base64Data.isEmpty) {
      bytes = Uint8List(0);
    } else {
      try {
        bytes = base64Decode(base64Data);
      } catch (_) {
        bytes = Uint8List(0);
      }
    }
    return _ImageAttachment(
      name: name,
      mime: mime,
      bytes: bytes,
      dataUri: dataUri,
      base64Length: base64Data.length,
    );
  }
}

class _ImagePreviewDialog extends StatefulWidget {
  final List<_ImageAttachment> images;
  final void Function(int index) onRemove;

  const _ImagePreviewDialog({required this.images, required this.onRemove});

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  @override
  Widget build(BuildContext context) {
    final hasImages = widget.images.isNotEmpty;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attach images',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: hasImages
                  ? GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                      itemCount: widget.images.length,
                      itemBuilder: (context, index) {
                        final image = widget.images[index];
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.memory(
                                image.bytes,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 2,
                              top: 2,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    widget.onRemove(index);
                                  });
                                },
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    border: Border.all(color: AppTheme.border),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  : const Center(
                      child: Text(
                        'No images selected',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('CANCEL', style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: hasImages
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.textPrimary,
                    ),
                    child: const Text('ATTACH', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          ],
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
                      getIconForExtension(fileName.split('.').last),
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
