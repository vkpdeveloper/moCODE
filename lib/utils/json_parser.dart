import 'package:crimson/crimson.dart';

dynamic parseJsonBytes(List<int> bytes) {
  final crimson = Crimson(bytes);
  return crimson.read();
}

Map<String, dynamic> parseJsonObjectBytes(List<int> bytes) {
  final crimson = Crimson(bytes);
  return crimson.readObject();
}

List<dynamic> parseJsonListBytes(List<int> bytes) {
  final crimson = Crimson(bytes);
  return crimson.readArray();
}
