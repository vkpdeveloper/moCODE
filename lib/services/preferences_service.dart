import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _kDefaultModelProvider = 'default_model_provider';
  static const String _kDefaultModelId = 'default_model_id';
  static const String _kSessionModelPrefix = 'session_model_';

  Future<void> saveDefaultModel(String providerId, String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultModelProvider, providerId);
    await prefs.setString(_kDefaultModelId, modelId);
  }

  Future<Map<String, String>?> getDefaultModel() async {
    final prefs = await SharedPreferences.getInstance();
    final providerId = prefs.getString(_kDefaultModelProvider);
    final modelId = prefs.getString(_kDefaultModelId);

    if (providerId != null && modelId != null) {
      return {'providerID': providerId, 'modelID': modelId};
    }
    return null;
  }

  Future<void> saveSessionModel(
    String sessionId,
    String providerId,
    String modelId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${_kSessionModelPrefix}${sessionId}_provider',
      providerId,
    );
    await prefs.setString('${_kSessionModelPrefix}${sessionId}_model', modelId);
  }

  Future<Map<String, String>?> getSessionModel(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final providerId = prefs.getString(
      '${_kSessionModelPrefix}${sessionId}_provider',
    );
    final modelId = prefs.getString(
      '${_kSessionModelPrefix}${sessionId}_model',
    );

    if (providerId != null && modelId != null) {
      return {'providerID': providerId, 'modelID': modelId};
    }
    return null;
  }

  Future<void> clearSessionModel(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_kSessionModelPrefix}${sessionId}_provider');
    await prefs.remove('${_kSessionModelPrefix}${sessionId}_model');
  }
}
