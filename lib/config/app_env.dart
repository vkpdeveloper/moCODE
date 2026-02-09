import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  static String get accountApiBaseUrl =>
      _read('ACCOUNT_API_BASE_URL', fallback: 'https://mo-code.vercel.app');

  static String get googleServerClientId => _read('GOOGLE_SERVER_CLIENT_ID');

  static String? get dodoProductId {
    final value = _read('DODO_PRODUCT_ID');
    return value.isEmpty ? null : value;
  }

  static String _read(String key, {String fallback = ''}) {
    final value = dotenv.env[key]?.trim();
    if (value == null || value.isEmpty) {
      return fallback;
    }
    return value;
  }
}
