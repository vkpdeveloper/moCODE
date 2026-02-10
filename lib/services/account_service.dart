import 'package:dio/dio.dart';

import 'account_api_client.dart';
import '../utils/json_parser.dart';

class AccountService {
  final AccountApiClient _apiClient;

  AccountService(this._apiClient);

  Options _authOptions(String idToken) {
    return Options(headers: {'Authorization': 'Bearer $idToken'});
  }

  Future<Map<String, dynamic>> fetchMe(String idToken) async {
    final response = await _apiClient.dio.get(
      '/api/v1/auth/me',
      options: _authOptions(idToken),
    );
    return parseJsonObjectBytes(response.data as List<int>);
  }

  Future<Map<String, dynamic>> fetchBillingStatus(String idToken) async {
    final response = await _apiClient.dio.get(
      '/api/v1/billing/status',
      options: _authOptions(idToken),
    );
    return parseJsonObjectBytes(response.data as List<int>);
  }

  Future<String> createCheckoutSession(
    String idToken, {
    String? returnUrl,
    int quantity = 1,
  }) async {
    final payload = <String, dynamic>{'quantity': quantity};
    if (returnUrl != null && returnUrl.isNotEmpty) {
      payload['returnUrl'] = returnUrl;
    }

    try {
      final response = await _apiClient.dio.post(
        '/api/v1/billing/create-checkout-session',
        data: payload,
        options: _authOptions(idToken),
      );

      final map = parseJsonObjectBytes(response.data as List<int>);
      final checkoutUrl = map['checkoutUrl'] as String?;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw Exception('Checkout URL missing from server response');
      }

      return checkoutUrl;
    } on DioException {
      rethrow;
    }
  }
}
