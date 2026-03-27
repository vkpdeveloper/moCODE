import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/providers.dart';
import '../models/app_models.dart' as app_models;
import '../services/app_logger.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
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
  final ValueNotifier<_OverlayPayload?> _overlayPayload =
      ValueNotifier<_OverlayPayload?>(null);

  OverlayEntry? _overlayEntry;
  int _triggerPosition = -1;
  bool _overlayLocked = false;
  int _overlayLockPosition = -1;
  String _overlayLockChar = '';
  final List<Map<String, dynamic>> _attachedFiles = [];
  final ImagePicker _imagePicker = ImagePicker();
  final List<_ImageAttachment> _attachedImages = [];
  Timer? _debounce;
  bool _isPickingImages = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _recordingPath;

  static const int _maxAttachmentBase64Length = 10 * 1024 * 1024;
  static const int _overlayScanLimit = 80;
  static const int _overlayDebounceMs = 160;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _overlayPayload.dispose();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;

    if (cursorPos < 0 || text.isEmpty) {
      _hideOverlay();
      return;
    }

    if (_overlayLocked) {
      if (_shouldReleaseOverlayLock(text, cursorPos)) {
        _overlayLocked = false;
      } else {
        _hideOverlay();
        return;
      }
    }

    if (cursorPos == 0) {
      _hideOverlay();
      return;
    }

    final match = _findTrigger(text, cursorPos);
    if (match == null) {
      _hideOverlay();
      return;
    }

    _triggerPosition = match.position;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _overlayDebounceMs), () {
      _showOverlay(match.mode, match.query, match.triggerChar);
    });
  }

  bool _shouldReleaseOverlayLock(String text, int cursorPos) {
    if (_overlayLockPosition < 0 || _overlayLockPosition >= text.length) {
      return true;
    }

    if (cursorPos <= _overlayLockPosition) return true;

    if (text[_overlayLockPosition] != _overlayLockChar) return true;

    if (cursorPos >= 1) {
      final prev = text[cursorPos - 1];
      if (prev == '@' || prev == '/' || prev == r'$') {
        if (cursorPos == 1 || text[cursorPos - 2] == ' ') {
          return true;
        }
      }
    }

    return false;
  }

  _TriggerMatch? _findTrigger(String text, int cursorPos) {
    final start = (cursorPos - _overlayScanLimit).clamp(0, cursorPos);
    for (var i = cursorPos - 1; i >= start; i--) {
      final ch = text[i];
      if (ch == ' ' || ch == '\n' || ch == '\t') {
        break;
      }
      if (ch == '@') {
        if (i == 0 || text[i - 1] == ' ') {
          final query = text.substring(i + 1, cursorPos);
          if (query.isEmpty || query.contains(' ') || query.length >= 50) {
            return null;
          }
          return _TriggerMatch(
            position: i,
            query: query,
            mode: 'file',
            triggerChar: '@',
          );
        }
      }
      if (ch == r'$') {
        if (i == 0 || text[i - 1] == ' ') {
          final query = text.substring(i + 1, cursorPos);
          if (query.isEmpty || query.contains(' ') || query.length >= 50) {
            return null;
          }
          return _TriggerMatch(
            position: i,
            query: query,
            mode: 'command',
            triggerChar: r'$',
          );
        }
      }
      if (ch == '/') {
        if (i == 0) {
          final query = text.substring(i + 1, cursorPos);
          if (query.contains(' ')) return null;
          return _TriggerMatch(
            position: i,
            query: query,
            mode: 'command',
            triggerChar: '/',
          );
        }
      }
    }
    return null;
  }

  void _ensureOverlayEntry() {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<_OverlayPayload?>(
        valueListenable: _overlayPayload,
        builder: (context, payload, _) {
          if (payload == null) return const SizedBox.shrink();
          return _OverlayContent(
            mode: payload.mode,
            query: payload.query,
            triggerChar: payload.triggerChar,
            layerLink: _layerLink,
            onSelectFile: _onFileSelected,
            onSelectCommand: _onCommandSelected,
            onDismiss: _hideOverlay,
          );
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _showOverlay(String mode, String query, String triggerChar) {
    _ensureOverlayEntry();
    final current = _overlayPayload.value;
    if (current != null &&
        current.mode == mode &&
        current.query == query &&
        current.triggerChar == triggerChar) {
      return;
    }
    _overlayPayload.value = _OverlayPayload(
      mode: mode,
      query: query,
      triggerChar: triggerChar,
    );
  }

  void _hideOverlay() {
    if (_overlayPayload.value != null) {
      _overlayPayload.value = null;
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onFileSelected(String filePath) {
    _hideOverlay();
    _overlayLocked = true;
    _overlayLockChar = '@';
    _overlayLockPosition = _triggerPosition;
    _triggerPosition = -1;

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
    _overlayLockPosition = triggerPos;

    setState(() {
      _attachedFiles.add({
        'type': 'file',
        'mime': 'text/plain',
        'url': 'file://$path',
        'filename': filePath.split('/').last,
      });
    });
  }

  void _onCommandSelected(String commandName, String type) {
    _hideOverlay();
    _overlayLocked = true;
    _overlayLockChar = type == 'skill' ? r'$' : '/';
    _overlayLockPosition = _triggerPosition;
    _triggerPosition = -1;

    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    var triggerPos = _triggerPosition;
    if (triggerPos < 0 || triggerPos > text.length) {
      final lookupIndex = cursorPos > 0 ? cursorPos - 1 : text.length - 1;
      triggerPos = text.lastIndexOf(type == 'skill' ? r'$' : '/', lookupIndex);
    }
    if (triggerPos < 0) {
      triggerPos = cursorPos.clamp(0, text.length);
    }

    final before = text.substring(0, triggerPos);
    final after = text.substring(cursorPos);

    if (type == 'skill') {
      final insertion = r'$skill ' + commandName;
      final needsSpace = after.isEmpty || !after.startsWith(' ');
      final next = '$before$insertion${needsSpace ? ' ' : ''}$after';
      _controller.text = next;
      _controller.selection = TextSelection.collapsed(
        offset: (before + insertion).length + (needsSpace ? 1 : 0),
      );
      _focusNode.requestFocus();
      return;
    }

    final insertion = '/$commandName ';
    final needsSpace = after.isNotEmpty && !after.startsWith(' ');
    final next = '$before$insertion${needsSpace ? ' ' : ''}$after';
    _controller.text = next;
    _controller.selection = TextSelection.collapsed(
      offset: (before + insertion).length + (needsSpace ? 1 : 0),
    );
    _focusNode.requestFocus();
  }

  Future<void> _send() async {
    final rawText = _controller.text;
    final text = rawText.trim();
    if (text.isEmpty && _attachedFiles.isEmpty && _attachedImages.isEmpty) {
      return;
    }

    if (_attachedFiles.isEmpty && _attachedImages.isEmpty) {
      if (text.startsWith('/')) {
        final parts = text.substring(1).split(RegExp(r'\s+'));
        final command = parts.isNotEmpty ? parts.first : '';
        final args = parts.length > 1
            ? parts.sublist(1).where((part) => part.isNotEmpty).toList()
            : <String>[];
        if (command.isNotEmpty) {
          final commandsAsync = ref.read(commandsProvider);
          final commands = commandsAsync.hasValue
              ? commandsAsync.value!
              : <app_models.Command>[];
          app_models.Command? commandMeta;
          for (final item in commands) {
            if (item.name == command) {
              commandMeta = item;
              break;
            }
          }
          final hints = commandMeta?.hints ?? const [];
          final requiresArgs = command == 'run' || hints.isNotEmpty;
          if (requiresArgs && args.isEmpty) {
            if (hints.isNotEmpty) {
              AppSnackBar.showInfo(context, 'Hint: ${hints.join(' ')}');
            }
            return;
          }
          _controller.clear();
          widget.onSendCommand(command, args.join(' '));
          return;
        }
      }
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
    AppSnackBar.showWarning(
      context,
      'Image attachments must be under 10 MB total.',
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
        AppSnackBar.showError(context, 'Failed to pick images.');
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

  Future<void> _handleVoiceInput() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    AppLogger.instance.info('Starting voice recording flow', scope: 'voice');

    // First check using permission_handler to see current status
    final currentStatus = await Permission.microphone.status;
    AppLogger.instance.debug(
      'Current microphone permission status',
      scope: 'voice',
      data: {'permissionStatus': currentStatus.toString()},
    );

    // Use the record package's hasPermission method
    final hasPermission = await _audioRecorder.hasPermission();
    AppLogger.instance.debug(
      'Record package permission check',
      scope: 'voice',
      data: {'hasPermission': hasPermission},
    );

    if (!hasPermission) {
      // Request permission using permission_handler
      final status = await Permission.microphone.request();
      AppLogger.instance.info(
        'Requested microphone permission',
        scope: 'voice',
        data: {'permissionStatus': status.toString()},
      );

      // Check again with record package after requesting
      final hasPermissionAfterRequest = await _audioRecorder.hasPermission();
      AppLogger.instance.debug(
        'Record package permission after request',
        scope: 'voice',
        data: {'hasPermission': hasPermissionAfterRequest},
      );

      if (!hasPermissionAfterRequest) {
        if (!mounted) return;
        AppSnackBar.showError(
          context,
          'Microphone permission is required for voice input',
          duration: const Duration(seconds: 4),
        );
        return;
      }
    }

    AppLogger.instance.info(
      'Microphone permission granted, starting recorder',
      scope: 'voice',
    );

    try {
      final tempDir = await getTemporaryDirectory();
      _recordingPath =
          '${tempDir.path}/voice_input_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _recordingPath!,
      );

      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      AppLogger.instance.error(
        'Failed to start voice recording',
        scope: 'voice',
        error: e,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start recording: $e')));
    }
  }

  Future<void> _stopRecording() async {
    String? audioPath;
    try {
      audioPath = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isTranscribing = true;
      });

      if (audioPath != null && audioPath.isNotEmpty) {
        await _transcribeAudio(audioPath);
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _isTranscribing = false;
      });
    }
  }

  Future<void> _transcribeAudio(String audioPath) async {
    if (!mounted) return;

    try {
      final idToken = await ref.read(idTokenProvider.future);
      if (idToken == null) {
        if (!mounted) return;
        setState(() {
          _isTranscribing = false;
        });
        return;
      }

      final asrService = ref.read(asrServiceProvider);
      final result = await asrService.transcribe(audioPath, idToken: idToken);

      if (!mounted) return;

      setState(() {
        _isTranscribing = false;
      });

      if (result.text.isNotEmpty) {
        final currentText = _controller.text;
        final separator = currentText.isNotEmpty && !currentText.endsWith(' ')
            ? ' '
            : '';
        _appendText('$separator${result.text}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTranscribing = false;
      });
    }
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
                _ChatInputAttachments(
                  attachedFiles: _attachedFiles,
                  attachedImages: _attachedImages,
                  onRemoveFile: _removeFile,
                  onRemoveImage: _removeImage,
                ),
              _ChatInputFieldRow(
                controller: _controller,
                focusNode: _focusNode,
                isBusy: widget.isBusy,
                enabled: widget.enabled,
                isRecording: _isRecording,
                isTranscribing: _isTranscribing,
                onPickImage: _openImagePicker,
                onSend: _send,
                onVoiceInput: _handleVoiceInput,
                onStop: widget.onStop,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatInputAttachments extends StatelessWidget {
  final List<Map<String, dynamic>> attachedFiles;
  final List<_ImageAttachment> attachedImages;
  final void Function(int index) onRemoveFile;
  final void Function(int index) onRemoveImage;

  const _ChatInputAttachments({
    required this.attachedFiles,
    required this.attachedImages,
    required this.onRemoveFile,
    required this.onRemoveImage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          ...attachedFiles.asMap().entries.map((entry) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      entry.value['filename'] as String? ?? 'file',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => onRemoveFile(entry.key),
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
          ...attachedImages.asMap().entries.map((entry) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                  Flexible(
                    child: Text(
                      entry.value.name,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => onRemoveImage(entry.key),
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
    );
  }
}

class _ChatInputFieldRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isBusy;
  final bool enabled;
  final bool isRecording;
  final bool isTranscribing;
  final VoidCallback onPickImage;
  final VoidCallback onSend;
  final VoidCallback onVoiceInput;
  final VoidCallback? onStop;

  const _ChatInputFieldRow({
    required this.controller,
    required this.focusNode,
    required this.isBusy,
    required this.enabled,
    required this.isRecording,
    required this.isTranscribing,
    required this.onPickImage,
    required this.onSend,
    required this.onVoiceInput,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: enabled ? onPickImage : null,
            icon: const Icon(Icons.image_outlined, size: 18),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            tooltip: 'Attach images',
          ),
          Expanded(child: _buildCenterContent()),
          const SizedBox(width: 4),
          _buildRightButton(),
        ],
      ),
    );
  }

  Widget _buildCenterContent() {
    if (isRecording) {
      return Container(
        constraints: const BoxConstraints(minHeight: 44, maxHeight: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PulsingDot(),
            SizedBox(width: 8),
            Text(
              'Recording...',
              style: TextStyle(
                color: AppTheme.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (isTranscribing) {
      return Container(
        constraints: const BoxConstraints(minHeight: 44, maxHeight: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent,
              ),
            ),
            SizedBox(width: 8),
            Text(
              'Transcribing...',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, maxHeight: 140),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        maxLines: null,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: isBusy
              ? 'Processing...'
              : 'Message... (@ files, / commands)',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          fillColor: Colors.transparent,
          filled: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 12,
          ),
        ),
        onSubmitted: (_) => onSend(),
      ),
    );
  }

  Widget _buildRightButton() {
    if (isRecording) {
      return GestureDetector(
        onTap: onVoiceInput,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.error,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.stop, size: 18, color: Colors.white),
        ),
      );
    }

    if (isBusy) {
      return GestureDetector(
        onTap: onStop,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: onStop != null ? AppTheme.error : AppTheme.border,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.stop, size: 18, color: Colors.white),
        ),
      );
    }

    if (isTranscribing) {
      return const SizedBox(width: 40, height: 40);
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasText = controller.text.isNotEmpty;
        if (hasText) {
          return GestureDetector(
            onTap: enabled ? onSend : null,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: enabled ? AppTheme.accent : AppTheme.border,
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.arrow_upward,
                size: 18,
                color: Colors.white,
              ),
            ),
          );
        }

        return IconButton(
          onPressed: enabled ? onVoiceInput : null,
          icon: const Icon(Icons.mic, size: 18, color: AppTheme.textPrimary),
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          tooltip: 'Voice input',
        );
      },
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class _OverlayContent extends ConsumerWidget {
  final String mode;
  final String query;
  final String triggerChar;
  final LayerLink layerLink;
  final void Function(String) onSelectFile;
  final void Function(String, String) onSelectCommand;
  final VoidCallback onDismiss;

  const _OverlayContent({
    required this.mode,
    required this.query,
    required this.triggerChar,
    required this.layerLink,
    required this.onSelectFile,
    required this.onSelectCommand,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenSize = MediaQuery.of(context).size;

    final maxOverlayWidth = (screenSize.width - 32).clamp(280.0, 420.0);
    final maxOverlayHeight = (screenSize.height * 0.35).clamp(180.0, 320.0);

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
              constraints: BoxConstraints(
                maxHeight: maxOverlayHeight,
                maxWidth: maxOverlayWidth,
              ),
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
                    : _CommandList(
                        query: query,
                        triggerChar: triggerChar,
                        onSelect: onSelectCommand,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayPayload {
  final String mode;
  final String query;
  final String triggerChar;

  const _OverlayPayload({
    required this.mode,
    required this.query,
    required this.triggerChar,
  });
}

class _CommandSuggestion {
  final String name;
  final String? description;
  final String type;
  final String source;
  final List<String> hints;

  const _CommandSuggestion({
    required this.name,
    this.description,
    required this.type,
    required this.source,
    this.hints = const [],
  });
}

class _TriggerMatch {
  final int position;
  final String query;
  final String mode;
  final String triggerChar;

  const _TriggerMatch({
    required this.position,
    required this.query,
    required this.mode,
    required this.triggerChar,
  });
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
          itemExtent: 44,
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            final fileName = file.name;
            final icon = file.isDirectory
                ? Icons.folder_outlined
                : getIconForExtension(file.extension ?? fileName.split('.').last);

            return GestureDetector(
              onTap: () => onSelect(file.path),
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
                      icon,
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
                            file.path,
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
  final String triggerChar;
  final void Function(String, String) onSelect;

  const _CommandList({
    required this.query,
    required this.triggerChar,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commandsAsync = ref.watch(commandsProvider);

    return commandsAsync.when(
      data: (commands) {
        final commandsItems = <_CommandSuggestion>[];
        final skillsItems = <_CommandSuggestion>[];

        for (final cmd in commands) {
          if (cmd.source == 'mcp') {
            continue;
          }
          if (cmd.source == 'skill') {
            skillsItems.add(
              _CommandSuggestion(
                name: cmd.name,
                description: cmd.description,
                type: 'skill',
                source: 'skill',
                hints: const [],
              ),
            );
          } else {
            commandsItems.add(
              _CommandSuggestion(
                name: cmd.name,
                description: cmd.description,
                type: 'command',
                source: cmd.source ?? 'command',
                hints: cmd.hints,
              ),
            );
          }
        }

        List<_CommandSuggestion> filterItems(List<_CommandSuggestion> items) {
          if (query.isEmpty) return items;
          final lower = query.toLowerCase();
          return items
              .where((item) => item.name.toLowerCase().contains(lower))
              .toList();
        }

        final filteredCommands = triggerChar == '/'
            ? filterItems(commandsItems)
            : <_CommandSuggestion>[];
        final filteredSkills = triggerChar == r'$'
            ? filterItems(skillsItems)
            : <_CommandSuggestion>[];

        if (filteredCommands.isEmpty && filteredSkills.isEmpty) {
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

        return ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            if (filteredCommands.isNotEmpty)
              _CommandSection(
                title: 'Commands',
                items: filteredCommands,
                onSelect: onSelect,
              ),
            if (filteredSkills.isNotEmpty)
              _CommandSection(
                title: 'Skills',
                items: filteredSkills,
                onSelect: onSelect,
              ),
          ],
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

class _CommandSection extends StatelessWidget {
  final String title;
  final List<_CommandSuggestion> items;
  final void Function(String, String) onSelect;

  const _CommandSection({
    required this.title,
    required this.items,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
        ...items.map((item) {
          final isSkill = item.type == 'skill';
          final titleText = isSkill ? item.name : '/${item.name}';
          final hint = item.hints.isNotEmpty ? item.hints.join(' ') : '';

          return GestureDetector(
            onTap: () => onSelect(item.name, item.type),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          titleText,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 12,
                          ),
                        ),
                        if ((item.description ?? '').isNotEmpty)
                          Text(
                            item.description ?? '',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (hint.isNotEmpty)
                          Text(
                            hint,
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
                  if (item.source.isNotEmpty)
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
                        item.source.toUpperCase(),
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
        }),
      ],
    );
  }
}
