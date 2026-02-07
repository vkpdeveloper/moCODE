class HealthInfo {
  final bool healthy;
  final String version;

  HealthInfo({
    required this.healthy,
    required this.version,
  });

  factory HealthInfo.fromJson(Map<String, dynamic> json) {
    return HealthInfo(
      healthy: json['healthy'] as bool,
      version: json['version'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'healthy': healthy,
      'version': version,
    };
  }
}
