class ResourceItem {
  final String absolute;
  final String? extension;
  final String name;
  final String path;
  final double score;
  final String type;

  const ResourceItem({
    required this.absolute,
    required this.extension,
    required this.name,
    required this.path,
    required this.score,
    required this.type,
  });

  bool get isDirectory => type == 'directory';

  factory ResourceItem.fromJson(Map<String, dynamic> json) {
    return ResourceItem(
      absolute: json['absolute'] as String? ?? '',
      extension: json['extension'] as String?,
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      type: json['type'] as String? ?? 'file',
    );
  }
}
