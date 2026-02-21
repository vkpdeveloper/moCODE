import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../models/part.dart';
import '../theme/app_theme.dart';
import 'message_parts_presenter.dart';
import 'patch_diff_widget.dart';
import '../constants/file_icons.dart';

final md.ExtensionSet _safeMarkdownExtensionSet = md.ExtensionSet(
  List<md.BlockSyntax>.unmodifiable(
    md.ExtensionSet.gitHubWeb.blockSyntaxes.where(
      (syntax) => syntax is! md.HtmlBlockSyntax,
    ),
  ),
  List<md.InlineSyntax>.unmodifiable(
    md.ExtensionSet.gitHubWeb.inlineSyntaxes.where(
      (syntax) => syntax is! md.InlineHtmlSyntax,
    ),
  ),
);

class UserMessageWidget extends StatelessWidget {
  final List<Part> parts;
  final bool isOptimistic;

  const UserMessageWidget({
    super.key,
    required this.parts,
    this.isOptimistic = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayParts = _partsForDisplay(parts);

    if (displayParts.isEmpty) {
      return const Text(
        '  ',
        style: TextStyle(
          color: AppTheme.textTertiary,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final part in displayParts) _buildPartWidget(context, part),
      ],
    );
  }

  List<Part> _partsForDisplay(List<Part> source) {
    final hasAttachment = source.any((part) => part.type != 'text');
    if (!hasAttachment) {
      return _getFilteredParts(source);
    }

    final files = <Part>[];
    final other = <Part>[];
    TextPart? finalUserText;

    for (final part in source) {
      if (part is FilePart) {
        files.add(part);
        continue;
      }

      if (part is TextPart && !part.synthetic) {
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

  List<Part> _getFilteredParts(List<Part> source) {
    final filtered = <Part>[];
    TextPart? finalUserText;

    for (final part in source) {
      if (part is StepStartPart || part is StepFinishPart) {
        continue;
      }

      if (part is TextPart) {
        final text = part.text.trim();
        if (text.isNotEmpty) {
          finalUserText = part;
        }
        continue;
      }

      filtered.add(part);
    }

    if (finalUserText != null) {
      filtered.add(finalUserText);
    }
    return filtered;
  }

  Widget _buildPartWidget(BuildContext context, Part part) {
    if (part is FilePart) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _buildFileAttachment(part),
      );
    }

    if (part is TextPart && !part.synthetic) {
      return _buildTextContent(context, part);
    }

    return const SizedBox.shrink();
  }

  Widget _buildFileAttachment(FilePart part) {
    final filename = part.filename ?? part.url.split('/').last;
    final extension = filename.contains('.') ? filename.split('.').last : '';
    final icon = getIconForExtension(extension);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.info),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              filename,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (part.mime.isNotEmpty && !_isTextOrCodeMime(part.mime)) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _getMimeCategory(part.mime),
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isTextOrCodeMime(String mime) {
    return mime.startsWith('text/') ||
        mime == 'application/json' ||
        mime == 'application/xml' ||
        mime == 'application/javascript';
  }

  String _getMimeCategory(String mime) {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
    if (mime.contains('pdf')) return 'pdf';
    if (mime.contains('zip') || mime.contains('archive')) return 'archive';
    return mime.split('/').last;
  }

  TextPart? _getTextPart(List<Part> parts) {
    for (final part in parts) {
      if (part is TextPart) {
        final text = part.text.trim();
        if (text.isNotEmpty) {
          return part;
        }
      }
    }
    return null;
  }

  Widget _buildTextContent(BuildContext context, TextPart part) {
    final text = part.text;
    if (text.isEmpty || text.trim().isEmpty) return const SizedBox.shrink();

    final sanitized = _sanitizeMarkdown(text);
    if (sanitized.isEmpty) return const SizedBox.shrink();

    return MarkdownBody(
      data: sanitized,
      selectable: true,
      softLineBreak: true,
      extensionSet: _safeMarkdownExtensionSet,
      builders: {'pre': _UserMessageCodeBlockBuilder(context)},
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
    );
  }
}

String _sanitizeMarkdown(String input) {
  return input.replaceAll(RegExp(r'<[^>]*>'), '');
}

class _UserMessageCodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  _UserMessageCodeBlockBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
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
                const Text(
                  'code',
                  style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    // Code copy functionality not needed for user messages
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
}
