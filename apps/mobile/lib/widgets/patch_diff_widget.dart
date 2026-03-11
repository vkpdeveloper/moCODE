import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

class PatchDiffWidget extends StatefulWidget {
  final String rawPatch;
  final List<String> fallbackFiles;

  const PatchDiffWidget({
    super.key,
    required this.rawPatch,
    this.fallbackFiles = const [],
  });

  @override
  State<PatchDiffWidget> createState() => _PatchDiffWidgetState();
}

class _PatchDiffWidgetState extends State<PatchDiffWidget> {
  static const int _maxCacheEntries = 64;
  static final Map<String, List<_ParsedPatchFile>> _cache =
      <String, List<_ParsedPatchFile>>{};

  late String _cacheKey;
  late List<_ParsedPatchFile> _files;

  @override
  void initState() {
    super.initState();
    _reparse();
  }

  @override
  void didUpdateWidget(covariant PatchDiffWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawPatch != widget.rawPatch ||
        oldWidget.fallbackFiles.join('|') != widget.fallbackFiles.join('|')) {
      _reparse();
    }
  }

  void _reparse() {
    _cacheKey = '${widget.rawPatch.hashCode}|${widget.fallbackFiles.join('|')}';
    final cached = _cache[_cacheKey];
    if (cached != null) {
      _files = cached;
      return;
    }

    _files = _PatchParser.parse(widget.rawPatch, widget.fallbackFiles);

    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[_cacheKey] = _files;
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _files
          .map((file) => _PatchFileCard(key: ValueKey(file.path), file: file))
          .toList(),
    );
  }
}

class _PatchFileCard extends StatefulWidget {
  final _ParsedPatchFile file;

  const _PatchFileCard({super.key, required this.file});

  @override
  State<_PatchFileCard> createState() => _PatchFileCardState();
}

class _PatchFileCardState extends State<_PatchFileCard> {
  static const int _previewLineCount = 180;

  bool _expanded = true;
  bool _showAllLines = false;

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final hasOverflow = file.lines.length > _previewLineCount;
    final visibleLines = _showAllLines
        ? file.lines
        : file.lines.take(_previewLineCount).toList();
    final diffText = visibleLines.map((line) => line.text).join('\n');

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border, width: 0.5),
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
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: AppTheme.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      file.path,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '+${file.additions}',
                    style: const TextStyle(
                      color: AppTheme.success,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '-${file.deletions}',
                    style: const TextStyle(
                      color: AppTheme.error,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (diffText.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'No diff hunks available',
                        style: TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(8),
                      child: SelectableText.rich(
                        TextSpan(children: _buildColoredSpans(visibleLines)),
                      ),
                    ),
                  if (hasOverflow)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          setState(() => _showAllLines = !_showAllLines);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _showAllLines ? 'Show less' : 'Show full diff',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<TextSpan> _buildColoredSpans(List<_DiffLine> lines) {
    final base = GoogleFonts.jetBrainsMono(
      textStyle: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 11,
        height: 1.4,
      ),
    );

    final spans = <TextSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final style = _styleForLine(line.kind, base);
      final text = i == lines.length - 1 ? line.text : '${line.text}\n';
      spans.add(TextSpan(text: text, style: style));
    }
    return spans;
  }

  TextStyle _styleForLine(_DiffLineType kind, TextStyle base) {
    return switch (kind) {
      _DiffLineType.addition => base.copyWith(
        color: const Color(0xFF9EE6B8),
        backgroundColor: AppTheme.success.withValues(alpha: 0.12),
      ),
      _DiffLineType.deletion => base.copyWith(
        color: const Color(0xFFF1A3A3),
        backgroundColor: AppTheme.error.withValues(alpha: 0.12),
      ),
      _DiffLineType.hunk => base.copyWith(
        color: AppTheme.info,
        backgroundColor: AppTheme.info.withValues(alpha: 0.08),
      ),
      _DiffLineType.fileMeta => base.copyWith(color: AppTheme.warning),
      _DiffLineType.meta => base.copyWith(color: AppTheme.textTertiary),
      _DiffLineType.context => base,
    };
  }
}

class _ParsedPatchFile {
  final String path;
  final int additions;
  final int deletions;
  final List<_DiffLine> lines;

  const _ParsedPatchFile({
    required this.path,
    required this.additions,
    required this.deletions,
    required this.lines,
  });
}

class _DiffLine {
  final String text;
  final _DiffLineType kind;

  const _DiffLine({required this.text, required this.kind});

  factory _DiffLine.fromText(String text) {
    return _DiffLine(text: text, kind: _DiffLineTypeClassifier.classify(text));
  }
}

enum _DiffLineType { addition, deletion, hunk, fileMeta, meta, context }

class _DiffLineTypeClassifier {
  static _DiffLineType classify(String line) {
    if (line.startsWith('+++ ') ||
        line.startsWith('--- ') ||
        line.startsWith('*** Update File: ') ||
        line.startsWith('*** Add File: ') ||
        line.startsWith('*** Delete File: ') ||
        line.startsWith('*** Move to: ')) {
      return _DiffLineType.fileMeta;
    }
    if (line.startsWith('@@')) return _DiffLineType.hunk;
    if (line.startsWith('diff --git') ||
        line.startsWith('index ') ||
        line.startsWith('new file mode ') ||
        line.startsWith('deleted file mode ') ||
        line.startsWith('rename from ') ||
        line.startsWith('rename to ') ||
        line.startsWith('similarity index ') ||
        line.startsWith('dissimilarity index ') ||
        line.startsWith('Patched ')) {
      return _DiffLineType.meta;
    }
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return _DiffLineType.addition;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return _DiffLineType.deletion;
    }
    return _DiffLineType.context;
  }
}

class _PatchParser {
  static List<_ParsedPatchFile> parse(String raw, List<String> fallbackFiles) {
    final text = raw.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty && fallbackFiles.isEmpty) {
      return const [];
    }

    if (text.contains('*** Begin Patch')) {
      final parsed = _parseApplyPatch(text);
      if (parsed.isNotEmpty) return parsed;
    }

    if (text.contains('diff --git ') ||
        text.contains('\n--- ') ||
        text.startsWith('--- ')) {
      final parsed = _parseUnifiedDiff(text);
      if (parsed.isNotEmpty) return parsed;
    }

    final parsedPatched = _parsePatchedOutput(text);
    if (parsedPatched.isNotEmpty) return parsedPatched;

    if (fallbackFiles.isNotEmpty) {
      return fallbackFiles
          .map(
            (file) => _ParsedPatchFile(
              path: file,
              additions: _countAdds(text),
              deletions: _countDels(text),
              lines: text.isEmpty
                  ? const []
                  : text
                        .split('\n')
                        .map((line) => _DiffLine.fromText(line))
                        .toList(),
            ),
          )
          .toList();
    }

    return [
      _ParsedPatchFile(
        path: 'Patch',
        additions: _countAdds(text),
        deletions: _countDels(text),
        lines: text.split('\n').map((line) => _DiffLine.fromText(line)).toList(),
      ),
    ];
  }

  static List<_ParsedPatchFile> _parseApplyPatch(String text) {
    final lines = text.split('\n');
    final files = <_MutablePatchFile>[];
    _MutablePatchFile? current;

    for (final line in lines) {
      if (line.startsWith('*** Update File: ')) {
        final path = line.substring('*** Update File: '.length).trim();
        current = _MutablePatchFile(path);
        files.add(current);
        continue;
      }
      if (line.startsWith('*** Add File: ')) {
        final path = line.substring('*** Add File: '.length).trim();
        current = _MutablePatchFile(path);
        files.add(current);
        continue;
      }
      if (line.startsWith('*** Delete File: ')) {
        final path = line.substring('*** Delete File: '.length).trim();
        current = _MutablePatchFile(path);
        files.add(current);
        current.lines.add(_DiffLine.fromText(line));
        continue;
      }
      if (line.startsWith('*** Move to: ')) {
        current?.lines.add(_DiffLine.fromText(line));
        continue;
      }
      if (current == null) continue;

      current.lines.add(_DiffLine.fromText(line));
      if (line.startsWith('+') && !line.startsWith('+++')) {
        current.additions++;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        current.deletions++;
      }
    }

    return files
        .map(
          (file) => _ParsedPatchFile(
            path: file.path,
            additions: file.additions,
            deletions: file.deletions,
            lines: file.lines,
          ),
        )
        .where((file) => file.path.isNotEmpty)
        .toList();
  }

  static List<_ParsedPatchFile> _parseUnifiedDiff(String text) {
    final lines = text.split('\n');
    final files = <_MutablePatchFile>[];
    _MutablePatchFile? current;
    String? pendingOldPath;

    for (final line in lines) {
      if (line.startsWith('diff --git ')) {
        final parts = line.split(' ');
        final path = parts.length >= 4
            ? parts[3].replaceFirst('b/', '').trim()
            : 'Patch';
        current = _MutablePatchFile(path);
        files.add(current);
        current.lines.add(_DiffLine.fromText(line));
        continue;
      }

      if (line.startsWith('+++ ') && current != null) {
        final path = line.substring(4).trim();
        if (path.isNotEmpty && path != '/dev/null') {
          current.path = path.replaceFirst('b/', '');
        }
      }

      if (line.startsWith('--- ') && current == null) {
        pendingOldPath = line.substring(4).trim();
        continue;
      }

      if (line.startsWith('+++ ') && current == null) {
        final newPath = line.substring(4).trim();
        final preferred = newPath.isNotEmpty && newPath != '/dev/null'
            ? newPath
            : (pendingOldPath ?? 'Patch');
        current = _MutablePatchFile(
          preferred.replaceFirst('a/', '').replaceFirst('b/', ''),
        );
        files.add(current);
        current.lines.add(_DiffLine.fromText('--- ${pendingOldPath ?? ''}'));
        current.lines.add(_DiffLine.fromText(line));
        continue;
      }

      if (current == null) {
        continue;
      }

      current.lines.add(_DiffLine.fromText(line));
      if (line.startsWith('+') && !line.startsWith('+++')) {
        current.additions++;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        current.deletions++;
      }
    }

    if (files.isEmpty) return const [];
    return files
        .map(
          (file) => _ParsedPatchFile(
            path: file.path,
            additions: file.additions,
            deletions: file.deletions,
            lines: file.lines,
          ),
        )
        .toList();
  }

  static List<_ParsedPatchFile> _parsePatchedOutput(String text) {
    final lines = text.split('\n');
    final files = <_MutablePatchFile>[];
    _MutablePatchFile? current;

    final patchedRegex = RegExp(r'^Patched\s+(.+?)(?:\s+\+(\d+)\s+-(\d+))?$');

    for (final line in lines) {
      final match = patchedRegex.firstMatch(line.trim());
      if (match != null) {
        final path = (match.group(1) ?? '').trim();
        current = _MutablePatchFile(path.isEmpty ? 'Patch' : path);
        current.additions = int.tryParse(match.group(2) ?? '') ?? 0;
        current.deletions = int.tryParse(match.group(3) ?? '') ?? 0;
        current.lines.add(_DiffLine.fromText(line));
        files.add(current);
        continue;
      }

      if (current == null) {
        continue;
      }

      current.lines.add(_DiffLine.fromText(line));
      if (line.startsWith('+') && !line.startsWith('+++')) {
        current.additions++;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        current.deletions++;
      }
    }

    return files
        .map(
          (file) => _ParsedPatchFile(
            path: file.path,
            additions: file.additions,
            deletions: file.deletions,
            lines: file.lines,
          ),
        )
        .toList();
  }

  static int _countAdds(String text) {
    var count = 0;
    for (final line in text.split('\n')) {
      if (line.startsWith('+') && !line.startsWith('+++')) count++;
    }
    return count;
  }

  static int _countDels(String text) {
    var count = 0;
    for (final line in text.split('\n')) {
      if (line.startsWith('-') && !line.startsWith('---')) count++;
    }
    return count;
  }
}

class _MutablePatchFile {
  String path;
  int additions = 0;
  int deletions = 0;
  final List<_DiffLine> lines = <_DiffLine>[];

  _MutablePatchFile(this.path);
}
