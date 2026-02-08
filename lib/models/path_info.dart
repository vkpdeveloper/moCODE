class PathInfo {
  final String home;
  final String state;
  final String config;
  final String worktree;
  final String directory;

  const PathInfo({
    required this.home,
    required this.state,
    required this.config,
    required this.worktree,
    required this.directory,
  });

  factory PathInfo.fromJson(Map<String, dynamic> json) {
    return PathInfo(
      home: json['home'] as String? ?? '',
      state: json['state'] as String? ?? '',
      config: json['config'] as String? ?? '',
      worktree: json['worktree'] as String? ?? '',
      directory: json['directory'] as String? ?? '',
    );
  }
}
