import 'package:dio/dio.dart';

import 'api_client.dart';

class AccountService {
  final ApiClient _apiClient;

  AccountService(this._apiClient);

  Options _authOptions(String idToken) {
    return Options(headers: {'Authorization': 'Bearer $idToken'});
  }

  Future<Map<String, dynamic>> fetchMe(String idToken) async {
    final response = await _apiClient.dio.get(
      '/api/v1/auth/me',
      options: _authOptions(idToken),
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchBillingStatus(String idToken) async {
    final response = await _apiClient.dio.get(
      '/api/v1/billing/status',
      options: _authOptions(idToken),
    );
    return response.data as Map<String, dynamic>;
  }

  Future<String> createCheckoutSession(
    String idToken, {
    String? productId,
    int quantity = 1,
  }) async {
    final response = await _apiClient.dio.post(
      '/api/v1/billing/create-checkout-session',
      data: {'productId': productId, 'quantity': quantity},
      options: _authOptions(idToken),
    );

    final map = response.data as Map<String, dynamic>;
    final checkoutUrl = map['checkoutUrl'] as String?;
    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      throw Exception('Checkout URL missing from server response');
    }

    return checkoutUrl;
  }
}
