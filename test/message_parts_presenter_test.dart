import 'package:flutter_test/flutter_test.dart';
import 'package:mecode/models/part.dart';
import 'package:mecode/widgets/message_parts_presenter.dart';

void main() {
  group('buildMessagePartBlocks', () {
    test('groups non-text assistant parts into one tool call set', () {
      final parts = <Part>[
        _stepStart('s1'),
        _tool('t1'),
        _stepFinish('f1', reason: 'done'),
        _text('x1', 'Final answer'),
      ];

      final blocks = buildMessagePartBlocks(parts);

      expect(blocks.length, 2);
      expect(blocks.first, isA<ToolCallSetBlock>());
      final group = blocks.first as ToolCallSetBlock;
      expect(group.toolCount, 1);
      expect(group.isRunning, isFalse);
      expect(group.hasError, isFalse);
      expect(group.primaryTool, 'bash');
      expect(group.parts.length, 3);
      expect(group.parts.first, isA<StepStartPart>());
      expect(group.parts[1], isA<ToolPart>());
      expect(group.parts[2], isA<StepFinishPart>());
      expect(blocks.last, isA<SinglePartBlock>());
      expect((blocks.last as SinglePartBlock).part, isA<TextPart>());
    });

    test('keeps text outside and merges operational parts into one group', () {
      final parts = <Part>[
        _text('x0', 'Intro'),
        _reasoning('r1'),
        _tool('t1'),
        _text('x1', 'Answer body'),
      ];

      final blocks = buildMessagePartBlocks(parts);

      expect(blocks.length, 3);
      expect(blocks.first, isA<SinglePartBlock>());
      expect((blocks.first as SinglePartBlock).part, isA<TextPart>());
      expect(blocks[1], isA<ToolCallSetBlock>());
      final group = blocks[1] as ToolCallSetBlock;
      expect(group.parts.length, 2);
      expect(group.parts[0], isA<ReasoningPart>());
      expect(group.parts[1], isA<ToolPart>());
      expect((blocks.last as SinglePartBlock).part, isA<TextPart>());
    });

    test('tracks running and error status from grouped tool parts', () {
      final parts = <Part>[
        _tool('t1', status: 'running'),
        _tool('t2', status: 'error'),
        _text('x1', 'Done'),
      ];

      final blocks = buildMessagePartBlocks(parts);

      expect(blocks.length, 2);
      final group = blocks.first as ToolCallSetBlock;
      expect(group.isRunning, isTrue);
      expect(group.hasError, isTrue);
      expect(group.toolCount, 2);
      expect(group.primaryTool, isNull);
    });

    test('keeps message order around single grouped tool set', () {
      final parts = <Part>[
        _text('x1', 'Intro'),
        _tool('t1'),
        _text('x2', 'Conclusion'),
        _commandOutput('c1'),
      ];

      final blocks = buildMessagePartBlocks(parts);

      expect(blocks.length, 3);
      expect((blocks[0] as SinglePartBlock).part, isA<TextPart>());
      expect(blocks[1], isA<ToolCallSetBlock>());
      final group = blocks[1] as ToolCallSetBlock;
      expect(group.parts.length, 2);
      expect(group.parts[0], isA<ToolPart>());
      expect(group.parts[1], isA<CommandOutputPart>());
      final tail = blocks[2] as SinglePartBlock;
      expect(tail.part, isA<TextPart>());
      expect((tail.part as TextPart).text, 'Conclusion');
    });

    test('does not group plain text-only messages', () {
      final parts = <Part>[_text('x1', 'One'), _text('x2', 'Two')];

      final blocks = buildMessagePartBlocks(parts);

      expect(blocks.length, 2);
      expect(blocks.every((block) => block is SinglePartBlock), isTrue);
    });

    test('can disable operational grouping', () {
      final parts = <Part>[_reasoning('r1'), _tool('t1')];

      final blocks = buildMessagePartBlocks(
        parts,
        groupOperationalParts: false,
      );

      expect(blocks.length, 2);
      expect(blocks.every((block) => block is SinglePartBlock), isTrue);
    });

    test('can group operational parts across multiple message ids', () {
      final parts = <Part>[
        _tool('t1', messageID: 'm1'),
        _tool('t2', messageID: 'm2'),
        _text('x1', 'Final answer'),
      ];

      final blocks = buildMessagePartBlocks(parts, groupByMessageID: false);

      expect(blocks.length, 2);
      final group = blocks.first as ToolCallSetBlock;
      expect(group.parts.length, 2);
      expect(group.toolCount, 2);
      expect(group.primaryTool, isNull);
      expect((blocks.last as SinglePartBlock).part, isA<TextPart>());
    });
  });
}

StepStartPart _stepStart(String id) {
  return StepStartPart(id: id, sessionID: 's', messageID: 'm');
}

StepFinishPart _stepFinish(String id, {required String reason}) {
  return StepFinishPart(
    id: id,
    sessionID: 's',
    messageID: 'm',
    reason: reason,
    cost: 0,
    inputTokens: 0,
    outputTokens: 0,
  );
}

ToolPart _tool(
  String id, {
  String status = 'completed',
  String messageID = 'm',
}) {
  return ToolPart(
    id: id,
    sessionID: 's',
    messageID: messageID,
    callID: 'c',
    tool: 'bash',
    state: <String, dynamic>{'status': status},
  );
}

ReasoningPart _reasoning(String id) {
  return ReasoningPart(
    id: id,
    sessionID: 's',
    messageID: 'm',
    text: 'thinking',
  );
}

CommandOutputPart _commandOutput(String id) {
  return CommandOutputPart(
    id: id,
    sessionID: 's',
    messageID: 'm',
    command: 'ls',
    cwd: '.',
    status: 'completed',
    exitCode: 0,
  );
}

TextPart _text(String id, String text) {
  return TextPart(
    id: id,
    sessionID: 's',
    messageID: 'm',
    synthetic: false,
    text: text,
  );
}
