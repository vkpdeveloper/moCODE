class SshCredentials {
  final String host;
  final int port;
  final String username;
  final String password;
  final String workingDirectory;

  SshCredentials({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.workingDirectory,
  });

  factory SshCredentials.fromJson(Map<String, dynamic> json) {
    return SshCredentials(
      host: json['host'] as String,
      port: json['port'] as int,
      username: json['username'] as String,
      password: json['password'] as String,
      workingDirectory: json['workingDirectory'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'workingDirectory': workingDirectory,
    };
  }

  SshCredentials copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? workingDirectory,
  }) {
    return SshCredentials(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      workingDirectory: workingDirectory ?? this.workingDirectory,
    );
  }
}
