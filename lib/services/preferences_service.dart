import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _kDefaultModelProvider = 'default_model_provider';
  static const String _kDefaultModelId = 'default_model_id';
  static const String _kSessionModelPrefix = 'session_model_';
  static const String _kSessionModePrefix = 'session_mode_';
  static const String _kProjectModelPrefix = 'project_model_';
  static const String _kActiveSessionPrefix = 'active_session_';

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

  Future<void> clearDefaultModel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDefaultModelProvider);
    await prefs.remove(_kDefaultModelId);
  }

  Future<void> saveSessionModel(
    String sessionId,
    String providerId,
    String modelId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_kSessionModelPrefix${sessionId}_provider',
      providerId,
    );
    await prefs.setString('$_kSessionModelPrefix${sessionId}_model', modelId);
  }

  Future<Map<String, String>?> getSessionModel(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final providerId = prefs.getString(
      '$_kSessionModelPrefix${sessionId}_provider',
    );
    final modelId = prefs.getString('$_kSessionModelPrefix${sessionId}_model');

    if (providerId != null && modelId != null) {
      return {'providerID': providerId, 'modelID': modelId};
    }
    return null;
  }

  Future<void> clearSessionModel(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kSessionModelPrefix${sessionId}_provider');
    await prefs.remove('$_kSessionModelPrefix${sessionId}_model');
  }

  Future<void> saveProjectModel(
    String projectId,
    String providerId,
    String modelId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_kProjectModelPrefix${projectId}_provider',
      providerId,
    );
    await prefs.setString('$_kProjectModelPrefix${projectId}_model', modelId);
  }

  Future<Map<String, String>?> getProjectModel(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final providerId = prefs.getString(
      '$_kProjectModelPrefix${projectId}_provider',
    );
    final modelId = prefs.getString('$_kProjectModelPrefix${projectId}_model');

    if (providerId != null && modelId != null) {
      return {'providerID': providerId, 'modelID': modelId};
    }
    return null;
  }

  Future<void> clearProjectModel(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kProjectModelPrefix${projectId}_provider');
    await prefs.remove('$_kProjectModelPrefix${projectId}_model');
  }

  Future<void> saveSessionMode(String sessionId, String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kSessionModePrefix$sessionId', mode);
  }

  Future<String?> getSessionMode(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_kSessionModePrefix$sessionId');
  }

  Future<void> markSessionActive(String sessionId, String directory) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kActiveSessionPrefix$sessionId', directory);
  }

  Future<void> clearSessionActive(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kActiveSessionPrefix$sessionId');
  }

  Future<Map<String, String>> getActiveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_kActiveSessionPrefix)) continue;
      final sessionId = key.substring(_kActiveSessionPrefix.length);
      final directory = prefs.getString(key);
      if (directory != null && directory.isNotEmpty) {
        entries[sessionId] = directory;
      }
    }
    return entries;
  }

  Future<void> clearActiveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_kActiveSessionPrefix))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
