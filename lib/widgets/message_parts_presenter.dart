import 'dart:convert';

import '../models/part.dart';

sealed class MessagePartBlock {
  const MessagePartBlock();
}

class SinglePartBlock extends MessagePartBlock {
  final Part part;

  const SinglePartBlock(this.part);
}

class StepPartBlock extends MessagePartBlock {
  final List<Part> parts;
  final StepFinishPart? finish;

  const StepPartBlock({required this.parts, this.finish});
}

class StepsGroupBlock extends MessagePartBlock {
  final List<Part> parts;
  final int stepCount;
  final String? lastReason;

  const StepsGroupBlock({
    required this.parts,
    required this.stepCount,
    this.lastReason,
  });
}

List<MessagePartBlock> buildMessagePartBlocks(List<Part> parts) {
  final firstStepIndex = parts.indexWhere((part) => part is StepStartPart);
  if (firstStepIndex < 0) {
    return parts.map((part) => SinglePartBlock(part)).toList();
  }

  final consumedIndices = <int>{};
  final groupedStepParts = <Part>[];
  var stepCount = 0;
  String? lastReason;

  var i = 0;
  while (i < parts.length) {
    final current = parts[i];
    if (current is! StepStartPart) {
      i++;
      continue;
    }

    stepCount++;
    consumedIndices.add(i);
    i++;

    while (i < parts.length) {
      final next = parts[i];
      if (next is StepStartPart) {
        break;
      }
      consumedIndices.add(i);
      if (next is StepFinishPart) {
        final reason = next.reason.trim();
        if (reason.isNotEmpty) {
          lastReason = reason;
        }
        i++;
        break;
      }
      groupedStepParts.add(next);
      i++;
    }
  }

  final blocks = <MessagePartBlock>[];
  var insertedGroup = false;
  for (var index = 0; index < parts.length; index++) {
    if (!insertedGroup && index == firstStepIndex) {
      blocks.add(
        StepsGroupBlock(
          parts: groupedStepParts,
          stepCount: stepCount,
          lastReason: lastReason,
        ),
      );
      insertedGroup = true;
    }
    if (consumedIndices.contains(index)) {
      continue;
    }
    blocks.add(SinglePartBlock(parts[index]));
  }

  if (!insertedGroup) {
    blocks.add(
      StepsGroupBlock(
        parts: groupedStepParts,
        stepCount: stepCount,
        lastReason: lastReason,
      ),
    );
  }

  return blocks;
}

String toolDisplayLabel(String tool) {
  const labels = <String, String>{
    'apply_patch': 'Patch',
    'read': 'Read',
    'grep': 'Grep',
    'glob': 'Glob',
    'bash': 'Shell',
    'write': 'Write',
    'edit': 'Edit',
    'task': 'Task',
    'question': 'Question',
    'webfetch': 'Fetch',
  };
  final normalized = tool.trim();
  if (normalized.isEmpty) return 'Tool';
  final mapped = labels[normalized.toLowerCase()];
  if (mapped != null) return mapped;
  final words = normalized
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  return words
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

String? toolSummary(ToolPart part) {
  final title = part.title?.trim();
  if (title != null && title.isNotEmpty) {
    return title;
  }

  final input = _normalizePayload(part.state['input']);
  if (input is Map<String, dynamic>) {
    for (final key in const [
      'description',
      'command',
      'filePath',
      'pattern',
      'url',
      'name',
    ]) {
      final value = input[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
  }

  final inputText = part.input?.trim();
  if (inputText != null && inputText.isNotEmpty) {
    return inputText;
  }
  return null;
}

bool isShellTool(ToolPart part) {
  final tool = part.tool.toLowerCase();
  return tool == 'bash' || tool == 'shell';
}

String toolInputHeader(ToolPart part) {
  return isShellTool(part) ? 'COMMAND' : 'INPUT';
}

String? toolInputText(ToolPart part) {
  if (isShellTool(part)) {
    final command = _extractShellCommand(part);
    if (command != null && command.isNotEmpty) {
      return command;
    }
  }

  final raw = part.input?.trim();
  if (raw != null && raw.isNotEmpty) {
    return raw;
  }

  final input = _normalizePayload(part.state['input']);
  if (input is Map<String, dynamic>) {
    final pretty = input.toString().trim();
    if (pretty.isNotEmpty) {
      return pretty;
    }
  }

  return null;
}

String? _extractShellCommand(ToolPart part) {
  final stateInput = _normalizePayload(part.state['input']);
  if (stateInput is Map<String, dynamic>) {
    final cmd = stateInput['command']?.toString().trim();
    if (cmd != null && cmd.isNotEmpty) {
      return cmd;
    }
  }

  final input = part.input?.trim();
  if (input == null || input.isEmpty) {
    return null;
  }

  final normalized = _normalizePayload(input);
  if (normalized is Map<String, dynamic>) {
    final cmd = normalized['command']?.toString().trim();
    if (cmd != null && cmd.isNotEmpty) {
      return cmd;
    }
  }

  final fromMapStyle = RegExp(r'\bcommand\s*:\s*(.+?)(?:,\s*\w+\s*:|\})')
      .firstMatch(input)
      ?.group(1)
      ?.trim();
  if (fromMapStyle != null && fromMapStyle.isNotEmpty) {
    return fromMapStyle;
  }

  return input;
}

String? extractPatchDiffFromTool(ToolPart part) {
  final tool = part.tool.toLowerCase();
  if (tool != 'apply_patch' && tool != 'bash' && tool != 'shell') return null;
  final candidates = <String>[];

  void collect(dynamic value) {
    if (value == null) return;
    final normalized = _normalizePayload(value);
    if (normalized is String) {
      final text = normalized.trim();
      if (text.isNotEmpty) {
        candidates.add(text);
      }
      return;
    }
    if (normalized is Map<String, dynamic>) {
      for (final key in const [
        'patch',
        'diff',
        'output',
        'input',
        'stdout',
        'stderr',
        'text',
      ]) {
        final nested = normalized[key];
        if (nested is String && nested.trim().isNotEmpty) {
          candidates.add(nested.trim());
        }
      }
      return;
    }
    if (normalized is List) {
      for (final item in normalized) {
        collect(item);
      }
    }
  }

  collect(part.state);
  collect(part.input);
  collect(part.output);
  collect(part.error);

  for (final candidate in candidates) {
    final text = candidate.trim();
    final begin = text.indexOf('*** Begin Patch');
    if (begin >= 0) {
      final end = text.indexOf('*** End Patch', begin);
      if (end > begin) {
        return text.substring(begin, end + '*** End Patch'.length).trim();
      }
      return text.substring(begin).trim();
    }

    final hasUnifiedDiff = text.contains('diff --git ') ||
        text.contains('\n@@ ') ||
        text.startsWith('@@ ') ||
        (text.contains('\n--- ') && text.contains('\n+++ '));
    if (hasUnifiedDiff) {
      return text;
    }

    final hasPatchedSummary = RegExp(r'^Patched\s+.+\+\d+\s+-\d+', multiLine: true)
        .hasMatch(text);
    if (hasPatchedSummary) {
      return text;
    }

    if (text.contains('@@') && (text.contains('--- ') || text.contains('+++ '))) {
      return text;
    }
  }
  return null;
}

dynamic _normalizePayload(dynamic value) {
  if (value is Map<String, dynamic> || value is List) return value;
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return value;
    final startsLikeJson = text.startsWith('{') || text.startsWith('[');
    if (!startsLikeJson) return value;
    try {
      return jsonDecode(text);
    } catch (_) {
      return value;
    }
  }
  return value;
}
