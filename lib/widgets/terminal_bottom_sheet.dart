import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../providers/ssh_provider.dart';
import '../theme/app_theme.dart';

class TerminalBottomSheet extends ConsumerStatefulWidget {
  const TerminalBottomSheet({super.key});

  @override
  ConsumerState<TerminalBottomSheet> createState() => _TerminalBottomSheetState();
}

class _TerminalBottomSheetState extends ConsumerState<TerminalBottomSheet>
    with WidgetsBindingObserver {
  final TerminalController _terminalController = TerminalController();
  final FocusNode _terminalFocusNode = FocusNode();
  Terminal? _proxiedTerminal;
  void Function(String)? _terminalOutputDelegate;
  bool _isCtrlLatched = false;

  static const double _toolbarHeight = 52;
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
  }

  @override
  void didChangeMetrics() {
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachTerminalProxy();
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
    }
  }

  void _sendControlKey(String key) {
    final sshState = ref.read(sshProvider);
    final terminal = sshState.terminal;
    if (terminal == null) return;

    switch (key) {
      case 'ctrl':
        setState(() {
          _isCtrlLatched = !_isCtrlLatched;
        });
        break;
      case 'tab':
        terminal.keyInput(TerminalKey.tab, ctrl: _isCtrlLatched);
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
    if (terminal != null && !_terminalFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _terminalFocusNode.requestFocus();
        }
      });
    }
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0;
    final toolbarBottomOffset = isKeyboardVisible ? bottomInset : 0.0;
    final terminalBottomPadding = _toolbarHeight + toolbarBottomOffset;

    return Container(
      height: double.infinity,
      decoration: const BoxDecoration(
        color: AppTheme.background,
      ),
      child: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            _buildHeader(sshState.isConnected),
            Expanded(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: () => _terminalFocusNode.requestFocus(),
                    child: Container(
                      color: AppTheme.surfaceVariant,
                      padding: EdgeInsets.only(bottom: terminalBottomPadding),
                      child: terminal != null
                          ? TerminalView(
                              terminal,
                              controller: _terminalController,
                              focusNode: _terminalFocusNode,
                              autofocus: true,
                              backgroundOpacity: 1.0,
                              theme: _terminalTheme,
                              padding: const EdgeInsets.all(8),
                              textStyle: const TerminalStyle(
                                fontSize: 14,
                                fontFamily: 'JetBrains Mono',
                              ),
                              cursorType: TerminalCursorType.block,
                              alwaysShowCursor: true,
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
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: toolbarBottomOffset,
                    child: _buildKeyboardToolbar(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Terminal',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: isConnected
                  ? AppTheme.success.withValues(alpha: 0.2)
                  : AppTheme.error.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isConnected ? 'Connected' : 'Disconnected',
              style: TextStyle(
                color: isConnected ? AppTheme.success : AppTheme.error,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.minimize,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            tooltip: 'Minimize',
          ),
          IconButton(
            onPressed: () {
              ref.read(sshProvider.notifier).disconnect();
              Navigator.of(context).pop();
            },
            icon: const Icon(
              Icons.close,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            tooltip: 'Disconnect',
          ),
        ],
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
      child: Row(
        children: [
          _KeyboardButton(
            label: 'Ctrl',
            selected: _isCtrlLatched,
            onTap: () => _sendControlKey('ctrl'),
          ),
          const SizedBox(width: 8),
          _KeyboardButton(
            label: 'Tab',
            onTap: () => _sendControlKey('tab'),
          ),
          const SizedBox(width: 8),
          _KeyboardButton(
            icon: Icons.arrow_back,
            label: '',
            onTap: () => _sendControlKey('arrow_left'),
          ),
          const SizedBox(width: 8),
          _KeyboardButton(
            icon: Icons.arrow_forward,
            label: '',
            onTap: () => _sendControlKey('arrow_right'),
          ),
          const SizedBox(width: 8),
          _KeyboardButton(
            icon: Icons.arrow_upward,
            label: '',
            onTap: () => _sendControlKey('arrow_up'),
          ),
          const SizedBox(width: 8),
          _KeyboardButton(
            icon: Icons.arrow_downward,
            label: '',
            onTap: () => _sendControlKey('arrow_down'),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _terminalFocusNode.requestFocus(),
            icon: const Icon(
              Icons.keyboard,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            tooltip: 'Focus terminal',
          ),
          IconButton(
            onPressed: () => _sendText('\n'),
            icon: const Icon(
              Icons.keyboard_return,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            tooltip: 'Enter',
          ),
        ],
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
    return Material(
      color: selected ? AppTheme.accent.withValues(alpha: 0.2) : AppTheme.surfaceVariant,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: icon != null
              ? Icon(
                  icon,
                  size: 18,
                  color: selected ? AppTheme.accent : AppTheme.textPrimary,
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppTheme.accent : AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}

void showTerminalBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => const TerminalBottomSheet(),
  );
}
