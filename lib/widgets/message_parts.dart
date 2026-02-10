import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/part.dart';
import '../theme/app_theme.dart';
import '../constants/file_icons.dart';

class MessagePartsWidget extends StatelessWidget {
  final List<Part> parts;
  final bool isUser;

  const MessagePartsWidget({
    super.key,
    required this.parts,
    this.isUser = false,
  });

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) {
      return const Text(
        '(empty)',
        style: TextStyle(
          color: AppTheme.textTertiary,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts.map((part) => _buildPart(context, part)).toList(),
    );
  }

  Widget _buildPart(BuildContext context, Part part) {
    return switch (part) {
      TextPart p => _buildTextPart(context, p),
      ToolPart p => _buildToolPart(context, p),
      ReasoningPart p => _buildReasoningPart(p),
      StepStartPart _ => const SizedBox.shrink(),
      StepFinishPart p => _buildStepFinishPart(p),
      FilePart p => _buildFilePart(p),
      SnapshotPart _ => const SizedBox.shrink(),
      PatchPart p => _buildPatchPart(p),
      AgentPart p => _buildAgentPart(p),
      RetryPart p => _buildRetryPart(p),
      SubtaskPart p => _buildSubtaskPart(p),
      CommandOutputPart p => _buildCommandOutputPart(context, p),
      CompactionPart _ => const SizedBox.shrink(),
      UnknownPart _ => const SizedBox.shrink(),
    };
  }

  Widget _buildTextPart(BuildContext context, TextPart part) {
    if (part.text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MarkdownBody(
        data: part.text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            height: 1.5,
          ),
          h1: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          h2: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          h3: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          code: GoogleFonts.jetBrainsMono(
            textStyle: const TextStyle(
              color: AppTheme.accent,
              backgroundColor: AppTheme.surfaceVariant,
              fontSize: 12,
            ),
          ),
          codeblockDecoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            border: Border.all(color: AppTheme.border),
          ),
          codeblockPadding: const EdgeInsets.all(12),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AppTheme.accent.withValues(alpha: 0.5),
                width: 3,
              ),
            ),
          ),
          blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          listBullet: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
          a: const TextStyle(
            color: AppTheme.info,
            decoration: TextDecoration.underline,
          ),
          strong: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
          em: const TextStyle(
            color: AppTheme.textSecondary,
            fontStyle: FontStyle.italic,
          ),
          horizontalRuleDecoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
        ),
      ),
    );
  }

  Widget _buildToolPart(BuildContext context, ToolPart part) {
    final status = part.status;
    final title = part.title ?? part.tool;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'completed':
        statusColor = AppTheme.success;
        statusIcon = Icons.check;
      case 'running':
        statusColor = AppTheme.warning;
        statusIcon = Icons.hourglass_top;
      case 'error':
        statusColor = AppTheme.error;
        statusIcon = Icons.error_outline;
      default:
        statusColor = AppTheme.textTertiary;
        statusIcon = Icons.pending;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppTheme.toolBg,
        border: Border.all(color: AppTheme.border),
      ),
      child: Theme(
        data: ThemeData(
          dividerColor: Colors.transparent,
          expansionTileTheme: const ExpansionTileThemeData(
            tilePadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            childrenPadding: EdgeInsets.zero,
            collapsedIconColor: AppTheme.textTertiary,
            iconColor: AppTheme.textTertiary,
            shape: RoundedRectangleBorder(),
            collapsedShape: RoundedRectangleBorder(),
          ),
        ),
        child: ExpansionTile(
          leading: Icon(statusIcon, size: 14, color: statusColor),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  part.tool,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          children: [
            if (part.input != null && part.input!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.border, width: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'INPUT',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _truncate(part.input!, 500),
                      style: GoogleFonts.jetBrainsMono(
                        textStyle: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (part.output != null && part.output!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.border, width: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'OUTPUT',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _truncate(part.output!, 500),
                      style: GoogleFonts.jetBrainsMono(
                        textStyle: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (part.error != null && part.error!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.border, width: 0.5),
                  ),
                  color: AppTheme.error,
                ),
                child: Text(
                  part.error!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasoningPart(ReasoningPart part) {
    if (part.text.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: AppTheme.textTertiary.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
      ),
      child: Text(
        part.text,
        style: const TextStyle(
          color: AppTheme.textTertiary,
          fontSize: 11,
          fontStyle: FontStyle.italic,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildStepFinishPart(StepFinishPart part) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 12,
            color: AppTheme.success,
          ),
          const Text(
            'Step complete',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 10),
          ),
          if (part.reason.isNotEmpty)
            Text(
              part.reason,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildFilePart(FilePart part) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(
            getIconForExtension((part.filename ?? part.url).split('.').last),
            size: 16,
            color: AppTheme.info,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  part.filename ?? part.url.split('/').last,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  part.mime,
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatchPart(PatchPart part) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border.all(color: AppTheme.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(
            Icons.difference_outlined,
            size: 14,
            color: AppTheme.warning,
          ),
          Text(
            '${part.files.length} file(s) patched',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentPart(AgentPart part) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.smart_toy, size: 12, color: AppTheme.info),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Agent: ${part.name}',
              style: const TextStyle(color: AppTheme.info, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetryPart(RetryPart part) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.refresh, size: 12, color: AppTheme.warning),
          const SizedBox(width: 6),
          Text(
            'Retry #${part.attempt}',
            style: const TextStyle(color: AppTheme.warning, fontSize: 10),
          ),
          if (part.errorMessage != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                part.errorMessage!,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubtaskPart(SubtaskPart part) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.account_tree, size: 14, color: AppTheme.info),
              Text(
                'Subtask: ${part.agent}',
                style: const TextStyle(
                  color: AppTheme.info,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (part.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              part.description,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommandOutputPart(BuildContext context, CommandOutputPart part) {
    final rawOutput = part.metadata?['output']?.toString() ?? '';
    final output = _stripAnsi(rawOutput);
    final isRunning = part.status == 'running';
    final statusLabel = part.status?.toUpperCase() ?? 'RUNNING';
    final header = [
      part.command,
      ...part.args,
    ].where((s) => s.isNotEmpty).toList();

    Color statusColor;
    if (isRunning) {
      statusColor = AppTheme.warning;
    } else if (part.exitCode == 0) {
      statusColor = AppTheme.success;
    } else if (part.exitCode != null) {
      statusColor = AppTheme.error;
    } else {
      statusColor = AppTheme.textTertiary;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 14, color: AppTheme.info),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    header.join(' '),
                    style: GoogleFonts.jetBrainsMono(
                      textStyle: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 11,
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    icon: const Icon(Icons.copy, size: 12),
                    onPressed: header.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: header.join(' ')),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Command copied.'),
                                ),
                              );
                            }
                          },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy command',
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: statusColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (part.cwd.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                part.cwd,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (output.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'OUTPUT',
                        style: TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 9,
                          letterSpacing: 1,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: IconButton(
                          icon: const Icon(Icons.copy, size: 12),
                          onPressed: output.isEmpty
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: output),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Output copied.'),
                                      ),
                                    );
                                  }
                                },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Copy output',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    output,
                    style: GoogleFonts.jetBrainsMono(
                      textStyle: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Text(
                isRunning ? 'Running...' : 'No output',
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _stripAnsi(String input) {
    final ansiRegex = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
    return input.replaceAll(ansiRegex, '');
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}
