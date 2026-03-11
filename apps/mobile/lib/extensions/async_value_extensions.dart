import 'package:flutter_riverpod/flutter_riverpod.dart';

extension AsyncValueExtension<T> on AsyncValue<T> {
  T? get valueOrNull {
    if (hasValue) {
      return value;
    }
    return null;
  }
}
