import 'dart:convert';

dynamic parseJsonBytes(List<int> bytes) {
  return jsonDecode(utf8.decode(bytes));
}

Map<String, dynamic> parseJsonObjectBytes(List<int> bytes) {
  return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
}

List<dynamic> parseJsonListBytes(List<int> bytes) {
  return jsonDecode(utf8.decode(bytes)) as List<dynamic>;
}
