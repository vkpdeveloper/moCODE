class AppConfig {
  final String? theme;
  final String? model;
  final String? smallModel;
  final String? defaultAgent;
  final String? username;

  AppConfig({
    this.theme,
    this.model,
    this.smallModel,
    this.defaultAgent,
    this.username,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      theme: json['theme'] as String?,
      model: json['model'] as String?,
      smallModel: json['small_model'] as String?,
      defaultAgent: json['default_agent'] as String?,
      username: json['username'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (theme != null) 'theme': theme,
      if (model != null) 'model': model,
      if (smallModel != null) 'small_model': smallModel,
      if (defaultAgent != null) 'default_agent': defaultAgent,
      if (username != null) 'username': username,
    };
  }
}
