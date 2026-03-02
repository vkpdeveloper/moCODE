enum ServerType { openCode, codex }

extension ServerTypeX on ServerType {
  String get storageValue => switch (this) {
    ServerType.openCode => 'opencode',
    ServerType.codex => 'codex',
  };

  static ServerType fromStorage(String? value) {
    if (value == 'codex') return ServerType.codex;
    return ServerType.openCode;
  }

  static ServerType? fromStorageNullable(String? value) {
    if (value == null || value.isEmpty) return null;
    return fromStorage(value);
  }
}
