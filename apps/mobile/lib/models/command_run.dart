class CommandRun {
  final String id;
  final String command;
  final List<String> args;
  final String cwd;
  final String status;
  final String output;
  final int startedAt;
  final int? completedAt;
  final int? exitCode;

  const CommandRun({
    required this.id,
    required this.command,
    required this.args,
    required this.cwd,
    required this.status,
    required this.output,
    required this.startedAt,
    this.completedAt,
    this.exitCode,
  });

  CommandRun copyWith({
    String? status,
    String? output,
    int? completedAt,
    int? exitCode,
  }) {
    return CommandRun(
      id: id,
      command: command,
      args: args,
      cwd: cwd,
      status: status ?? this.status,
      output: output ?? this.output,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      exitCode: exitCode ?? this.exitCode,
    );
  }
}
