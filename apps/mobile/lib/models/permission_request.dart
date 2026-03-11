class PermissionToolInfo {
  final String messageID;
  final String callID;

  PermissionToolInfo({required this.messageID, required this.callID});

  factory PermissionToolInfo.fromJson(Map<String, dynamic> json) {
    return PermissionToolInfo(
      messageID: json['messageID'] as String,
      callID: json['callID'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'messageID': messageID, 'callID': callID};
  }
}

class PermissionRequest {
  final String id;
  final String sessionID;
  final String permission;
  final List<String> patterns;
  final Map<String, dynamic> metadata;
  final List<String> always;
  final PermissionToolInfo? tool;

  PermissionRequest({
    required this.id,
    required this.sessionID,
    required this.permission,
    required this.patterns,
    required this.metadata,
    required this.always,
    this.tool,
  });

  factory PermissionRequest.fromJson(Map<String, dynamic> json) {
    return PermissionRequest(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      permission: json['permission'] as String? ?? '',
      patterns:
          (json['patterns'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      metadata:
          (json['metadata'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      always:
          (json['always'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      tool: json['tool'] != null
          ? PermissionToolInfo.fromJson(json['tool'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'permission': permission,
      'patterns': patterns,
      'metadata': metadata,
      'always': always,
      if (tool != null) 'tool': tool!.toJson(),
    };
  }
}
