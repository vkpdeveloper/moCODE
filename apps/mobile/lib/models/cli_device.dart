class DiscoveredCliDevice {
  final String host;
  final int port;
  final String deviceName;
  final String? deviceModel;
  final String? platform;
  final bool isPaired;
  final String? token;
  final String? pairedDeviceId;

  const DiscoveredCliDevice({
    required this.host,
    required this.port,
    required this.deviceName,
    this.deviceModel,
    this.platform,
    this.isPaired = false,
    this.token,
    this.pairedDeviceId,
  });

  String get baseUrl => 'http://$host:$port';

  String get subtitle {
    final parts = <String>[];
    if (deviceModel != null && deviceModel!.isNotEmpty) {
      parts.add(deviceModel!);
    }
    if (platform != null && platform!.isNotEmpty) {
      parts.add(platform!);
    }
    parts.add(host);
    return parts.join(' • ');
  }

  DiscoveredCliDevice copyWith({
    String? host,
    int? port,
    String? deviceName,
    String? deviceModel,
    String? platform,
    bool? isPaired,
    String? token,
    String? pairedDeviceId,
  }) {
    return DiscoveredCliDevice(
      host: host ?? this.host,
      port: port ?? this.port,
      deviceName: deviceName ?? this.deviceName,
      deviceModel: deviceModel ?? this.deviceModel,
      platform: platform ?? this.platform,
      isPaired: isPaired ?? this.isPaired,
      token: token ?? this.token,
      pairedDeviceId: pairedDeviceId ?? this.pairedDeviceId,
    );
  }

  factory DiscoveredCliDevice.fromStored(Map<String, dynamic> json) {
    return DiscoveredCliDevice(
      host: json['host'] as String? ?? '',
      port: int.tryParse(json['port']?.toString() ?? '') ?? 4058,
      deviceName:
          json['deviceName'] as String? ?? json['host'] as String? ?? '',
      isPaired: true,
      token: json['token'] as String?,
      pairedDeviceId: json['deviceId'] as String?,
      deviceModel: json['deviceModel'] as String?,
      platform: json['platform'] as String?,
    );
  }

  Map<String, dynamic> toStored() {
    return {
      'deviceId': pairedDeviceId,
      'deviceName': deviceName,
      'deviceModel': deviceModel,
      'platform': platform,
      'host': host,
      'port': port.toString(),
      'token': token,
    };
  }
}
