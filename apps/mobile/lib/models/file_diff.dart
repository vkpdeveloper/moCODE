class FileDiff {
  final String file;
  final String before;
  final String after;
  final int additions;
  final int deletions;
  final String? status;

  FileDiff({
    required this.file,
    required this.before,
    required this.after,
    required this.additions,
    required this.deletions,
    this.status,
  });

  factory FileDiff.fromJson(Map<String, dynamic> json) {
    return FileDiff(
      file: json['file'] as String,
      before: json['before'] as String,
      after: json['after'] as String,
      additions: json['additions'] as int,
      deletions: json['deletions'] as int,
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file': file,
      'before': before,
      'after': after,
      'additions': additions,
      'deletions': deletions,
      if (status != null) 'status': status,
    };
  }
}
