class EditedFileEntry {
  final String path;
  final int updatedAt;
  final String? kind;

  const EditedFileEntry({
    required this.path,
    required this.updatedAt,
    this.kind,
  });

  EditedFileEntry copyWith({String? path, int? updatedAt, String? kind}) {
    return EditedFileEntry(
      path: path ?? this.path,
      updatedAt: updatedAt ?? this.updatedAt,
      kind: kind ?? this.kind,
    );
  }
}
