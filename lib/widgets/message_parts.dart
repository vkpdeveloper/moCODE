import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../models/part.dart';
import '../theme/app_theme.dart';
import '../constants/file_icons.dart';
import 'message_parts_presenter.dart';
import 'patch_diff_widget.dart';

final md.ExtensionSet _safeMarkdownExtensionSet = md.ExtensionSet(
  md.ExtensionSet.gitHubWeb.blockSyntaxes,
  List<md.InlineSyntax>.unmodifiable(
    md.ExtensionSet.gitHubWeb.inlineSyntaxes.where(
      (syntax) => syntax is! md.InlineHtmlSyntax,
    ),
  ),
);

class MessagePartsWidget extends StatelessWidget {
  final List<Part> parts;
  final bool isUser;
  final bool collapseOperationalParts;
  final bool groupOperationalByMessageID;

  const MessagePartsWidget({
    super.key,
    required this.parts,
    this.isUser = false,
    this.collapseOperationalParts = true,
    this.groupOperationalByMessageID = true,
  });

  @override
  Widget build(BuildContext context) {
    final displayParts = _partsForDisplay(parts);

    if (displayParts.isEmpty) {
      return const Text(
        '(empty)',
        style: TextStyle(
          color: AppTheme.textTertiary,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final blocks = buildMessagePartBlocks(
      displayParts,
      groupOperationalParts: collapseOperationalParts && !isUser,
      groupByMessageID: groupOperationalByMessageID,
    );
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) => _buildBlock(context, block)).toList(),
    );
  }

  List<Part> _partsForDisplay(List<Part> source) {
    if (!isUser) {
      return source;
    }

    final hasAttachment = source.any((part) => part is FilePart);
    if (!hasAttachment) {
      return source;
    }

    final files = <Part>[];
    final other = <Part>[];
    TextPart? finalUserText;

    for (final part in source) {
      if (part is FilePart) {
        files.add(part);
        continue;
      }

      if (part is TextPart) {
        final text = part.text.trim();
        if (text.isNotEmpty) {
          finalUserText = part;
        }
        continue;
      }

      if (part is StepStartPart || part is StepFinishPart) {
        continue;
      }

      other.add(part);
    }

    final merged = <Part>[...files, ...other];
    if (finalUserText != null) {
      merged.add(finalUserText);
    }
    return merged;
  }

  Widget _buildBlock(BuildContext context, MessagePartBlock block) {
    return switch (block) {
      SinglePartBlock b => _buildPart(context, b.part),
      ToolCallSetBlock b => _ToolCallSetCard(
        messageID: b.messageID,
        parts: b.parts,
        toolCount: b.toolCount,
        isRunning: b.isRunning,
        hasError: b.hasError,
        primaryTool: b.primaryTool,
      ),
    };
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
        softLineBreak: true,
        extensionSet: _safeMarkdownExtensionSet,
        builders: {'pre': _CodeBlockBuilder(context)},
        onTapLink: (text, href, title) async {
          if (href == null || href.isEmpty) return;
          final uri = Uri.tryParse(href);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
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
          listBulletPadding: const EdgeInsets.only(right: 8),
          blockSpacing: 10,
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
            borderRadius: BorderRadius.circular(8),
          ),
          codeblockPadding: const EdgeInsets.all(0),
          tableHead: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          tableBody: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            height: 1.4,
          ),
          tableBorder: TableBorder.all(color: AppTheme.border),
          tableCellsPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
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
    final label = toolDisplayLabel(part.tool);
    final title = _toolHeaderTitle(part, label);
    final inputHeader = toolInputHeader(part);
    final inputText = toolInputText(part) ?? '';
    final rawInput = inputText.trim();
    final rawOutput = (part.output ?? '').trim();
    final isApplyPatchTool = part.tool.toLowerCase() == 'apply_patch';
    final patchText = isApplyPatchTool ? extractPatchDiffFromTool(part) : null;
    final hasInlinePatch = patchText != null && patchText.isNotEmpty;

    var trimmedInput = _truncate(rawInput, 1200);
    var trimmedOutput = _truncate(rawOutput, 1200);
    if (hasInlinePatch) {
      if (_looksLikePatch(trimmedInput)) {
        trimmedInput = '';
      }
      if (_looksLikePatch(trimmedOutput)) {
        trimmedOutput = '';
      }
    }

    final isRunning = status == 'running' || status == 'pending';
    final isError = status == 'error';
    final iconColor = isError ? AppTheme.error : AppTheme.textSecondary;
    final leading = isRunning
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.warning),
            ),
          )
        : Icon(_iconForTool(part.tool), size: 14, color: iconColor);

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
          leading: leading,
          title: Row(
            children: [
              if (!isRunning)
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (isRunning) ...[
                const Text(
                  'Loading',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
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
            ],
          ),
          children: [
            if (trimmedInput.isNotEmpty)
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
                    Text(
                      inputHeader,
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      trimmedInput,
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
            if (trimmedOutput.isNotEmpty)
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
                      trimmedOutput,
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
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.border, width: 0.5),
                  ),
                  color: AppTheme.error.withValues(alpha: 0.1),
                ),
                child: Text(
                  part.error!,
                  style: const TextStyle(
                    color: AppTheme.error,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            if (hasInlinePatch)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.border, width: 0.5),
                  ),
                ),
                child: _PatchPreviewTile(rawPatch: patchText),
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

  Widget _buildStepFinishPart(StepFinishPart _) {
    return const SizedBox.shrink();
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
    final partIndex = parts.indexOf(part);
    final fileCount = part.files.length;
    final title = fileCount == 1 ? 'Patch 1 file' : 'Patch $fileCount files';
    final patchText = _nearestPatchText(partIndex);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
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
          leading: const Icon(
            Icons.difference_outlined,
            size: 14,
            color: AppTheme.warning,
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            if (part.files.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.border, width: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: part.files
                      .map(
                        (file) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Icon(
                                getIconForExtension(file.split('.').last),
                                size: 13,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  file,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (patchText != null && patchText.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.border, width: 0.5),
                  ),
                ),
                child: PatchDiffWidget(
                  rawPatch: patchText,
                  fallbackFiles: part.files,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _nearestPatchText(int partIndex) {
    if (partIndex < 0 || parts.isEmpty) return null;

    for (var i = partIndex; i >= 0; i--) {
      final candidate = parts[i];
      if (candidate is ToolPart) {
        final text = extractPatchDiffFromTool(candidate);
        if (text != null && text.isNotEmpty) {
          return _truncate(text, 6000);
        }
      }
    }

    for (var i = partIndex + 1; i < parts.length; i++) {
      final candidate = parts[i];
      if (candidate is ToolPart) {
        final text = extractPatchDiffFromTool(candidate);
        if (text != null && text.isNotEmpty) {
          return _truncate(text, 6000);
        }
      }
    }

    return null;
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
    final output = _cleanTerminalOutput(rawOutput);
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

  /// Clean raw terminal output for display.
  ///
  /// 1. Strip all ANSI escape sequences (CSI, OSC, single-char).
  /// 2. Simulate carriage-return (\r) line overwrites so progress bars
  ///    collapse to the final visible text on each line.
  /// 3. Remove remaining non-printable control chars (except \n and \t).
  /// 4. Collapse runs of 3+ blank lines into 2.
  /// 5. Trim trailing whitespace.
  String _cleanTerminalOutput(String input) {
    // 1. Strip all ANSI escape sequences
    //    - CSI sequences: \x1B[ ... letter
    //    - OSC sequences: \x1B] ... (terminated by BEL \x07 or ST \x1B\\)
    //    - Two-char sequences: \x1B followed by a single char (e.g. \x1B(B)
    final ansiRegex = RegExp(
      r'\x1B' // ESC
      r'(?:'
      r'\[[0-9;?]*[A-Za-z]' // CSI: \x1B[ ... letter
      r'|'
      r'\][^\x07\x1B]*(?:\x07|\x1B\\)?' // OSC: \x1B] ... BEL/ST
      r'|'
      r'[()#][A-Za-z0-9]?' // charset switching
      r'|'
      r'[A-Za-z]' // single-char (e.g. \x1BM)
      r')',
    );
    var cleaned = input.replaceAll(ansiRegex, '');

    // 2. Simulate carriage-return overwrites.
    //    Split by newlines, then for each line if it contains \r,
    //    split by \r and keep only the last non-empty segment.
    final lines = cleaned.split('\n');
    final processed = <String>[];
    for (final line in lines) {
      if (line.contains('\r')) {
        final segments = line.split('\r');
        // Find the last non-empty segment (that's what the terminal shows)
        var lastVisible = '';
        for (final seg in segments) {
          if (seg.isNotEmpty) {
            lastVisible = seg;
          }
        }
        processed.add(lastVisible);
      } else {
        processed.add(line);
      }
    }

    // 3. Remove remaining non-printable control characters
    //    (keep \n implicit via the join, keep \t for indentation)
    var result = processed.join('\n');
    result = result.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    // 4. Collapse runs of 3+ blank lines into 2
    result = result.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');

    // 5. Trim
    return result.trim();
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  bool _looksLikePatch(String text) {
    if (text.isEmpty) return false;
    return text.contains('*** Begin Patch') ||
        text.contains('diff --git ') ||
        text.startsWith('@@ ') ||
        text.contains('\n@@ ') ||
        (text.contains('\n--- ') && text.contains('\n+++ '));
  }

  String _toolHeaderTitle(ToolPart part, String fallbackLabel) {
    final tool = part.tool.toLowerCase();
    if (tool == 'read') {
      final payload = part.state['input'];
      if (payload is Map) {
        final raw = payload['filePath']?.toString().trim();
        if (raw != null && raw.isNotEmpty) {
          return 'Read ${_basename(raw)}';
        }
      }
      final summary = toolSummary(part)?.trim();
      if (summary != null && summary.isNotEmpty) {
        return 'Read ${_basename(summary)}';
      }
      return fallbackLabel;
    }
    return fallbackLabel;
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/').where((e) => e.isNotEmpty).toList();
    if (segments.isEmpty) return path;
    return segments.last;
  }
}

class _ToolCallSetCard extends StatefulWidget {
  final String messageID;
  final List<Part> parts;
  final int toolCount;
  final bool isRunning;
  final bool hasError;
  final String? primaryTool;

  const _ToolCallSetCard({
    required this.messageID,
    required this.parts,
    required this.toolCount,
    required this.isRunning,
    required this.hasError,
    this.primaryTool,
  });

  @override
  State<_ToolCallSetCard> createState() => _ToolCallSetCardState();
}

class _ToolCallSetCardState extends State<_ToolCallSetCard> {
  late bool _expanded;
  late bool _wasRunning;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isRunning;
    _wasRunning = widget.isRunning;
  }

  @override
  void didUpdateWidget(covariant _ToolCallSetCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning && !_expanded) {
      setState(() {
        _expanded = true;
      });
    } else if (_wasRunning && !widget.isRunning && _expanded) {
      setState(() {
        _expanded = false;
      });
    }
    _wasRunning = widget.isRunning;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.toolCount > 0 ? widget.toolCount : widget.parts.length;
    final summary = count == 1 ? '1 item' : '$count items';

    final headerColor = widget.isRunning
        ? AppTheme.warning
        : widget.hasError
        ? AppTheme.error
        : AppTheme.textSecondary;

    final leadingIcon = widget.isRunning
        ? LucideIcons.loaderCircle
        : _iconForTool(widget.primaryTool);

    final title = widget.toolCount == 1 && widget.primaryTool != null
        ? toolDisplayLabel(widget.primaryTool!)
        : 'Tool calls';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant.withValues(alpha: 0.35),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: 13,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Icon(leadingIcon, size: 14, color: headerColor),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    summary,
                    style: TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                  const Spacer(),
                  if (widget.isRunning)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.warning,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 2, 0, 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: AppTheme.border.withValues(alpha: 0.8),
                    width: 1,
                  ),
                ),
              ),
              child: MessagePartsWidget(
                parts: widget.parts,
                collapseOperationalParts: false,
              ),
            ),
        ],
      ),
    );
  }
}

class _PatchPreviewTile extends StatelessWidget {
  final String rawPatch;

  const _PatchPreviewTile({required this.rawPatch});

  @override
  Widget build(BuildContext context) {
    return Theme(
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
        leading: const Icon(
          LucideIcons.fileDiff,
          size: 14,
          color: AppTheme.warning,
        ),
        title: const Text(
          'Patch',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.border, width: 0.5),
              ),
            ),
            child: PatchDiffWidget(
              rawPatch: rawPatch,
              fallbackFiles: const <String>[],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconForTool(String? tool) {
  switch ((tool ?? '').toLowerCase()) {
    case 'read':
      return LucideIcons.glasses;
    case 'grep':
      return LucideIcons.scanSearch;
    case 'glob':
      return LucideIcons.search;
    case 'bash':
    case 'shell':
      return LucideIcons.terminal;
    case 'write':
      return LucideIcons.fileCode;
    case 'edit':
      return LucideIcons.filePen;
    case 'apply_patch':
      return LucideIcons.fileDiff;
    case 'task':
      return LucideIcons.workflow;
    case 'question':
      return LucideIcons.messageCircleQuestionMark;
    case 'webfetch':
      return LucideIcons.globe;
    default:
      return LucideIcons.wrench;
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  _CodeBlockBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final language = _extractLanguage(element);
    final code = _extractCode(element);
    if (code.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                Text(
                  language,
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied.')),
                      );
                    }
                  },
                  child: const Icon(
                    Icons.copy,
                    size: 14,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: GoogleFonts.jetBrainsMono(
                textStyle: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _extractCode(md.Element element) {
    if (element.children == null || element.children!.isEmpty) return '';
    final child = element.children!.first;
    if (child is md.Element && child.tag == 'code') {
      return child.textContent;
    }
    return element.textContent;
  }

  String _extractLanguage(md.Element element) {
    if (element.children == null || element.children!.isEmpty) {
      return 'code';
    }
    final child = element.children!.first;
    if (child is! md.Element) return 'code';
    final className = child.attributes['class'];
    if (className == null || className.isEmpty) return 'code';
    const prefix = 'language-';
    if (!className.startsWith(prefix)) return 'code';
    return className.substring(prefix.length);
  }
}
