import 'dart:convert';

/// Represents a favourite model with complete provider and model details
/// for proper display in the favourites section.
class FavouriteModel {
  final String providerId;
  final String? providerName;
  final String modelId;
  final String? modelName;
  final String? family;
  final String? status;
  final bool? reasoning;

  const FavouriteModel({
    required this.providerId,
    this.providerName,
    required this.modelId,
    this.modelName,
    this.family,
    this.status,
    this.reasoning,
  });

  /// Unique key for identifying this favourite
  String get key => '$providerId:$modelId';

  factory FavouriteModel.fromJson(Map<String, dynamic> json) {
    return FavouriteModel(
      providerId: json['providerId'] as String,
      providerName: json['providerName'] as String?,
      modelId: json['modelId'] as String,
      modelName: json['modelName'] as String?,
      family: json['family'] as String?,
      status: json['status'] as String?,
      reasoning: json['reasoning'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'providerId': providerId,
      if (providerName != null) 'providerName': providerName,
      'modelId': modelId,
      if (modelName != null) 'modelName': modelName,
      if (family != null) 'family': family,
      if (status != null) 'status': status,
      if (reasoning != null) 'reasoning': reasoning,
    };
  }

  /// Serialize the entire model to a JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from a JSON string
  factory FavouriteModel.fromJsonString(String jsonString) {
    return FavouriteModel.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FavouriteModel &&
        other.providerId == providerId &&
        other.modelId == modelId;
  }

  @override
  int get hashCode => Object.hash(providerId, modelId);
}
