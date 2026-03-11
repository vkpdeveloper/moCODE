import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../providers/ssh_provider.dart';
import '../providers/providers.dart';
import '../services/connection_manager.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';

class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key});

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage>
    with WidgetsBindingObserver {
  final TerminalController _terminalController = TerminalController();
  final FocusNode _terminalFocusNode = FocusNode();
  Terminal? _proxiedTerminal;
  void Function(String)? _terminalOutputDelegate;
  bool _isCtrlLatched = false;
  bool _showQuickCommands = false;
  bool _selectionMode = false;

  final GlobalKey _terminalKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  OverlayEntry? _copyOverlay;
  Size? _charSize;

  static const double _toolbarHeight = 52;
  static const Map<String, List<String>> _quickCommands = {
    'Navigation': ['ls -la', 'cd ..', 'pwd', 'cd ~', 'clear'],
    'Git': [
      'git status',
      'git log --oneline -10',
      'git branch -a',
      'git diff',
      'git pull',
    ],
    'Docker': [
      'docker ps',
      'docker ps -a',
      'docker images',
      'docker logs',
      'docker compose ps',
    ],
    'Process': ['ps aux', 'top', 'htop', 'kill -9', 'df -h'],
  };
  static const TerminalTheme _terminalTheme = TerminalTheme(
    cursor: AppTheme.accent,
    selection: Color(0x66FFFFFF),
    foreground: AppTheme.textPrimary,
    background: AppTheme.surfaceVariant,
    black: Color(0xFF000000),
    red: Color(0xFFCD3131),
    green: Color(0xFF0DBC79),
    yellow: Color(0xFFE5E510),
    blue: Color(0xFF2472C8),
    magenta: Color(0xFFBC3FBC),
    cyan: Color(0xFF11A8CD),
    white: Color(0xFFE5E5E5),
    brightBlack: Color(0xFF666666),
    brightRed: Color(0xFFF14C4C),
    brightGreen: Color(0xFF23D18B),
    brightYellow: Color(0xFFF5F543),
    brightBlue: Color(0xFF3B8EEA),
    brightMagenta: Color(0xFFD670D6),
    brightCyan: Color(0xFF29B8DB),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _terminalController.addListener(_onTerminalStateChanged);
    _scrollController.addListener(_updateCopyMenu);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measureCharSize();
  }

  String _getTerminalFontFamily() {
    final settings = ref.watch(settingsProvider);
    return settings.useNerdFont ? 'JetBrainsMono-Nerd-Font' : 'JetBrains Mono';
  }

  void _measureCharSize() {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'M',
        style: TextStyle(fontFamily: _getTerminalFontFamily(), fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    _charSize = textPainter.size;
  }

  void _onTerminalStateChanged() {
    if (mounted) {
      setState(() {});
      _updateCopyMenu();
    }
  }

  void _updateCopyMenu() {
    final selection = _terminalController.selection;
    if (selection == null || _charSize == null) {
      _hideCopyMenu();
      return;
    }

    if (_copyOverlay == null) {
      _copyOverlay = OverlayEntry(
        builder: (context) => Positioned(
          left: _calculateMenuPosition(selection).dx,
          top: _calculateMenuPosition(selection).dy,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final terminal = ref.read(sshProvider).terminal;
                if (terminal != null) {
                  final text = terminal.buffer.getText(selection);
                  await Clipboard.setData(ClipboardData(text: text));
                  _terminalController.clearSelection();
                  if (mounted) {
                    AppSnackBar.showSuccess(
                      context,
                      'Copied to clipboard',
                      duration: const Duration(seconds: 1),
                    );
                  }
                  HapticFeedback.selectionClick();
                }
                _hideCopyMenu();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Copy',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Overlay.of(context).insert(_copyOverlay!);
    } else {
      _copyOverlay!.markNeedsBuild();
    }
  }

  Offset _calculateMenuPosition(var selection) {
    if (_terminalKey.currentContext == null) return Offset.zero;

    final renderBox =
        _terminalKey.currentContext!.findRenderObject() as RenderBox;
    final terminalPosition = renderBox.localToGlobal(Offset.zero);

    final dynamic begin = (selection as dynamic).begin;
    final int startRow;
    int startCol = 0;

    if (begin is int) {
      startRow = begin;
    } else {
      startRow = begin.y;
      startCol = begin.x;
    }

    final visibleStartRow = _scrollController.hasClients
        ? _scrollController.offset / _charSize!.height
        : 0.0;

    final relativeRow = startRow - visibleStartRow;

    final double y =
        terminalPosition.dy + (relativeRow * _charSize!.height) - 45;
    final double x = terminalPosition.dx + (startCol * _charSize!.width);

    final screenWidth = MediaQuery.of(context).size.width;
    final clampedX = x.clamp(16.0, screenWidth - 80.0);

    return Offset(clampedX, y);
  }

  void _hideCopyMenu() {
    _copyOverlay?.remove();
    _copyOverlay = null;
  }

  @override
  void didChangeMetrics() {
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndReconnect();
    }
  }

  Future<void> _checkAndReconnect() async {
    final sshState = ref.read(sshProvider);
    if (sshState.isConnected) {
      final isAlive = await ref.read(sshProvider.notifier).checkSshConnection();
      if (!isAlive) {
        ref.read(sshProvider.notifier).reconnect();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachTerminalProxy();
    _terminalController.removeListener(_onTerminalStateChanged);
    _scrollController.removeListener(_updateCopyMenu);
    _scrollController.dispose();
    _hideCopyMenu();
    _terminalController.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  void _ensureTerminalProxy(Terminal? terminal) {
    if (identical(_proxiedTerminal, terminal)) {
      return;
    }

    _detachTerminalProxy();

    if (terminal == null) {
      return;
    }

    _terminalOutputDelegate = terminal.onOutput;
    terminal.onOutput = (data) {
      final transformed = _isCtrlLatched ? _applyCtrlChord(data) : data;
      _terminalOutputDelegate?.call(transformed);
    };
    _proxiedTerminal = terminal;
  }

  void _detachTerminalProxy() {
    final terminal = _proxiedTerminal;
    if (terminal != null) {
      terminal.onOutput = _terminalOutputDelegate;
    }
    _proxiedTerminal = null;
    _terminalOutputDelegate = null;
  }

  String _applyCtrlChord(String text) {
    if (text.isEmpty) return text;
    final output = <int>[];
    for (final rune in text.runes) {
      var code = rune;

      if (code >= 0x41 && code <= 0x5A) {
        code += 0x20;
      }

      if (code >= 0x61 && code <= 0x7A) {
        output.add(code - 0x60);
        continue;
      }

      if (code == 0x20) {
        output.add(0x00);
        continue;
      }

      if (code >= 0x5B && code <= 0x5F) {
        output.add(code - 0x40);
        continue;
      }

      output.add(code);
    }
    return String.fromCharCodes(output);
  }

  void _sendText(String text) {
    final sshState = ref.read(sshProvider);
    final terminal = sshState.terminal;
    if (terminal != null) {
      terminal.textInput(text);
      _terminalFocusNode.requestFocus();
      HapticFeedback.selectionClick();
    }
  }

  void _sendControlKey(String key) {
    final sshState = ref.read(sshProvider);
    final terminal = sshState.terminal;
    if (terminal == null) return;

    HapticFeedback.lightImpact();

    switch (key) {
      case 'ctrl':
        setState(() {
          _isCtrlLatched = !_isCtrlLatched;
        });
        break;
      case 'esc':
        terminal.keyInput(TerminalKey.escape);
        break;
      case 'tab':
        terminal.keyInput(TerminalKey.tab, ctrl: _isCtrlLatched);
        break;
      case 'home':
        terminal.keyInput(TerminalKey.home);
        break;
      case 'end':
        terminal.keyInput(TerminalKey.end);
        break;
      case 'page_up':
        terminal.keyInput(TerminalKey.pageUp);
        break;
      case 'page_down':
        terminal.keyInput(TerminalKey.pageDown);
        break;
      case 'arrow_left':
        terminal.keyInput(TerminalKey.arrowLeft, ctrl: _isCtrlLatched);
        break;
      case 'arrow_right':
        terminal.keyInput(TerminalKey.arrowRight, ctrl: _isCtrlLatched);
        break;
      case 'arrow_up':
        terminal.keyInput(TerminalKey.arrowUp, ctrl: _isCtrlLatched);
        break;
      case 'arrow_down':
        terminal.keyInput(TerminalKey.arrowDown, ctrl: _isCtrlLatched);
        break;
    }

    _terminalFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final sshState = ref.watch(sshProvider);
    final terminal = sshState.terminal;
    _ensureTerminalProxy(terminal);
    final paddingBottom = MediaQuery.of(context).padding.bottom;
    final toolbarBottomOffset = paddingBottom;
    final terminalBottomPadding = _toolbarHeight + toolbarBottomOffset;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(context, sshState),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    color: AppTheme.surfaceVariant,
                    padding: EdgeInsets.only(
                      bottom:
                          terminalBottomPadding + (_showQuickCommands ? 80 : 0),
                    ),
                    child: sshState.isReconnecting
                        ? _buildReconnectingOverlay(sshState)
                        : terminal != null
                        ? ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              physics: _selectionMode
                                  ? const NeverScrollableScrollPhysics()
                                  : const BouncingScrollPhysics(),
                            ),
                            child: TerminalView(
                              terminal,
                              key: _terminalKey,
                              controller: _terminalController,
                              focusNode: _terminalFocusNode,
                              autofocus: false,
                              backgroundOpacity: 1.0,
                              theme: _terminalTheme,
                              padding: const EdgeInsets.all(8),
                              scrollController: _scrollController,
                              textStyle: TerminalStyle(
                                fontSize: 13,
                                fontFamily: _getTerminalFontFamily(),
                              ),
                              cursorType: TerminalCursorType.block,
                              alwaysShowCursor: true,
                              simulateScroll: true,
                            ),
                          )
                        : const Center(
                            child: Text(
                              'No terminal session',
                              style: TextStyle(
                                color: AppTheme.textTertiary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                  ),
                  if (!sshState.isReconnecting) ...[
                    if (_showQuickCommands)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: toolbarBottomOffset + _toolbarHeight,
                        child: _buildQuickCommandsPanel(),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: toolbarBottomOffset,
                      child: _buildKeyboardToolbar(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, SshState sshState) {
    final isConnected = sshState.isConnected;
    final isReconnecting = sshState.isReconnecting;
    final connectionState = sshState.connectionState;

    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(color: AppTheme.border, height: 1.0),
      ),
      title: const Text(
        'Terminal',
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      actions: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: EdgeInsets.all(isConnected ? 4 : 4),
            decoration: BoxDecoration(
              color: _getStatusColor(
                isConnected,
                isReconnecting,
              ).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(isConnected ? 50 : 4),
            ),
            child: isConnected
                ? Icon(
                    Icons.check,
                    size: 14,
                    color: _getStatusColor(isConnected, isReconnecting),
                  )
                : Text(
                    _getStatusText(
                      isConnected,
                      isReconnecting,
                      connectionState,
                    ),
                    style: TextStyle(
                      color: _getStatusColor(isConnected, isReconnecting),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
        if (!isConnected && !isReconnecting && sshState.credentials != null)
          IconButton(
            onPressed: () {
              ref.read(sshProvider.notifier).reconnect();
            },
            icon: const Icon(Icons.refresh, size: 20, color: AppTheme.accent),
            tooltip: 'Reconnect',
          ),
        IconButton(
          onPressed: () {
            ref.read(sshProvider.notifier).disconnect();
            Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.close,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          tooltip: 'Disconnect',
        ),
      ],
    );
  }

  Widget _buildReconnectingOverlay(SshState sshState) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Reconnecting...',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          if (sshState.nextRetryDelay != null)
            Text(
              'Retry ${sshState.retryAttempt}/5 in ${sshState.nextRetryDelay!.inSeconds}s',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              ref.read(sshProvider.notifier).reconnect();
            },
            child: const Text(
              'Reconnect Now',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(bool isConnected, bool isReconnecting) {
    if (isReconnecting) return AppTheme.warning;
    if (isConnected) return AppTheme.success;
    return AppTheme.error;
  }

  String _getStatusText(
    bool isConnected,
    bool isReconnecting,
    SshConnectionState state,
  ) {
    if (isReconnecting) return 'Reconnecting';
    if (isConnected) return 'Connected';
    return 'Disconnected';
  }

  Widget _buildQuickCommandsPanel() {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.border),
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: _quickCommands.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: entry.value.map((cmd) {
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _sendText('$cmd\n');
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.border, width: 0.5),
                      ),
                      child: Text(
                        cmd,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontFamily: _getTerminalFontFamily(),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKeyboardToolbar() {
    return Container(
      height: _toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.border),
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _KeyboardButton(
              icon: _selectionMode ? Icons.touch_app : Icons.pan_tool,
              label: '',
              selected: _selectionMode,
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _selectionMode = !_selectionMode;
                  if (_selectionMode) {
                    _terminalFocusNode.unfocus();
                  } else {
                    _terminalController.clearSelection();
                  }
                });
              },
            ),
            const SizedBox(width: 8),
            _KeyboardButton(label: 'Esc', onTap: () => _sendControlKey('esc')),
            const SizedBox(width: 4),
            _KeyboardButton(
              label: 'Ctrl',
              selected: _isCtrlLatched,
              onTap: () => _sendControlKey('ctrl'),
            ),
            const SizedBox(width: 4),
            _KeyboardButton(label: 'Tab', onTap: () => _sendControlKey('tab')),
            const SizedBox(width: 8),
            _KeyboardButton(
              icon: Icons.arrow_back,
              label: '',
              onTap: () => _sendControlKey('arrow_left'),
            ),
            const SizedBox(width: 4),
            _KeyboardButton(
              icon: Icons.arrow_downward,
              label: '',
              onTap: () => _sendControlKey('arrow_down'),
            ),
            const SizedBox(width: 4),
            _KeyboardButton(
              icon: Icons.arrow_upward,
              label: '',
              onTap: () => _sendControlKey('arrow_up'),
            ),
            const SizedBox(width: 4),
            _KeyboardButton(
              icon: Icons.arrow_forward,
              label: '',
              onTap: () => _sendControlKey('arrow_right'),
            ),
            const SizedBox(width: 8),
            _KeyboardButton(
              icon: Icons.keyboard_arrow_down,
              label: 'PgDn',
              onTap: () => _sendControlKey('page_down'),
            ),
            const SizedBox(width: 8),
            _KeyboardButton(
              icon: Icons.code,
              label: '',
              selected: _showQuickCommands,
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _showQuickCommands = !_showQuickCommands;
                });
              },
            ),

            const SizedBox(width: 16),
            IconButton(
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) {
                  _sendText(data!.text!);
                  HapticFeedback.selectionClick();
                }
              },
              icon: const Icon(
                Icons.paste,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              tooltip: 'Paste',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              onPressed: () => _sendText('\n'),
              icon: const Icon(
                Icons.keyboard_return,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              tooltip: 'Enter',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyboardButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _KeyboardButton({
    required this.label,
    this.icon,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: const BoxConstraints(minWidth: 32),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.border,
            width: 0.5,
          ),
        ),
        child: Center(
          child: icon != null
              ? Icon(
                  icon,
                  size: 16,
                  color: selected
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}
