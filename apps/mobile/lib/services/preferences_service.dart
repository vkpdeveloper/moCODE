import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _kDefaultModelProvider = 'default_model_provider';
  static const String _kDefaultModelId = 'default_model_id';
  static const String _kSessionModelPrefix = 'session_model_';
  static const String _kSessionModePrefix = 'session_mode_';
  static const String _kProjectModelPrefix = 'project_model_';
  static const String _kActiveSessionPrefix = 'active_session_';
  static const String _kUseNerdFont = 'use_nerd_font';
  static const String _kPairedCliDevices = 'paired_cli_devices';
  static const String _kSelectedCliDevice = 'selected_cli_device';
  static const String _kCliResetRequested = 'cli_reset_requested';
  static const String _kSelectedAgentPrefix = 'selected_agent_';

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

  // Favourite Models
  static const String _kFavouriteModelsKey = 'favourite_models';

  Future<void> addFavouriteModel(Map<String, dynamic> favouriteJson) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_kFavouriteModelsKey) ?? [];
    final key = '${favouriteJson['providerId']}:${favouriteJson['modelId']}';

    // Check if already exists
    final alreadyExists = existing.any((jsonStr) {
      final parsed = _parseJson(jsonStr);
      if (parsed == null) return false;
      return '${parsed['providerId']}:${parsed['modelId']}' == key;
    });

    if (!alreadyExists) {
      existing.add(_encodeJson(favouriteJson));
      await prefs.setStringList(_kFavouriteModelsKey, existing);
    }
  }

  Future<void> removeFavouriteModel(String providerId, String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_kFavouriteModelsKey) ?? [];
    final key = '$providerId:$modelId';

    final updated = existing.where((jsonStr) {
      final parsed = _parseJson(jsonStr);
      if (parsed == null) return false;
      return '${parsed['providerId']}:${parsed['modelId']}' != key;
    }).toList();

    await prefs.setStringList(_kFavouriteModelsKey, updated);
  }

  Future<List<Map<String, dynamic>>> getFavouriteModels() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_kFavouriteModelsKey) ?? [];
    return stored
        .map(_parseJson)
        .where((m) => m != null)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  Future<bool> isFavourite(String providerId, String modelId) async {
    final favourites = await getFavouriteModels();
    return favourites.any(
      (f) => f['providerId'] == providerId && f['modelId'] == modelId,
    );
  }

  Future<void> setUseNerdFont(bool useNerdFont) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseNerdFont, useNerdFont);
  }

  Future<bool> getUseNerdFont() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kUseNerdFont) ?? true;
  }

  Future<List<Map<String, dynamic>>> getPairedCliDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_kPairedCliDevices) ?? [];
    return stored
        .map(_parseJson)
        .where((item) => item != null)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  Future<void> savePairedCliDevice(Map<String, dynamic> device) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getPairedCliDevices();
    final normalized = <String, dynamic>{
      'deviceId': device['deviceId'],
      'deviceName': device['deviceName'],
      'host': device['host'],
      'port': device['port'],
      'token': device['token'],
    };

    final next =
        existing
            .where(
              (item) =>
                  item['deviceId'] != normalized['deviceId'] &&
                  !(item['host'] == normalized['host'] &&
                      item['port'] == normalized['port']),
            )
            .toList()
          ..add(normalized);

    await prefs.setStringList(
      _kPairedCliDevices,
      next.map(_encodeJson).toList(),
    );
  }

  Future<Map<String, dynamic>?> getSelectedCliDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kSelectedCliDevice);
    if (stored == null || stored.isEmpty) {
      return null;
    }
    return _parseJson(stored);
  }

  Future<void> selectCliDevice(Map<String, dynamic> device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedCliDevice, _encodeJson(device));
  }

  Future<void> clearSelectedCliDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSelectedCliDevice);
  }

  Future<void> saveSelectedAgent(
    String connectionKey, {
    required String agentId,
    required String agentName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _agentStorageKey(connectionKey),
      _encodeJson({
        'agentId': agentId,
        'agentName': agentName,
      }),
    );
  }

  Future<Map<String, dynamic>?> getSelectedAgent(String connectionKey) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_agentStorageKey(connectionKey));
    if (stored == null || stored.isEmpty) {
      return null;
    }
    return _parseJson(stored);
  }

  Future<void> clearSelectedAgent(String connectionKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_agentStorageKey(connectionKey));
  }

  Future<void> requestCliReselectionOnNextLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCliResetRequested, true);
  }

  Future<bool> consumeCliReselectionRequest() async {
    final prefs = await SharedPreferences.getInstance();
    final shouldReset = prefs.getBool(_kCliResetRequested) ?? false;
    if (!shouldReset) {
      return false;
    }
    await prefs.remove(_kCliResetRequested);
    await clearSelectedCliDevice();
    return true;
  }

  String _agentStorageKey(String connectionKey) {
    return '$_kSelectedAgentPrefix${Uri.encodeComponent(connectionKey)}';
  }

  String _encodeJson(Map<String, dynamic> json) {
    return json.entries.map((e) => '${e.key}=${e.value ?? ''}').join('|');
  }

  Map<String, dynamic>? _parseJson(String encoded) {
    try {
      final map = <String, dynamic>{};
      for (final part in encoded.split('|')) {
        final idx = part.indexOf('=');
        if (idx == -1) continue;
        final key = part.substring(0, idx);
        final value = part.substring(idx + 1);
        if (value == 'true') {
          map[key] = true;
        } else if (value == 'false') {
          map[key] = false;
        } else if (value.isEmpty) {
          map[key] = null;
        } else {
          map[key] = value;
        }
      }
      return map.isNotEmpty ? map : null;
    } catch (_) {
      return null;
    }
  }
}
