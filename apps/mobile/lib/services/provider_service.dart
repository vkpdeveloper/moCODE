import '../models/provider.dart';

class ProviderService {
  Future<ProviderListResponse> listProviders({String? directory}) async {
    return const ProviderListResponse(providers: []);
  }
}
