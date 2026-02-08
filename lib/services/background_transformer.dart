import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// A [Transformer] that performs JSON decoding in a background isolate using [compute].
class BackgroundTransformer extends BackgroundTransformerBase {
  BackgroundTransformer() : super(jsonDecodeCallback: _decodeJson);
}

/// A base class for background transformers to allow easier testing if needed.
/// This implementation focuses on offloading the JSON decoding.
class BackgroundTransformerBase extends DefaultTransformer {
  final FutureOr<dynamic> Function(String) jsonDecodeCallback;

  BackgroundTransformerBase({required this.jsonDecodeCallback});

  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody responseBody,
  ) async {
    final responseType = options.responseType;

    // Do not handle stream responses, let the default transformer handle it or pass it through.
    if (responseType == ResponseType.stream) {
      return responseBody;
    }

    final transformed = await super.transformResponse(
      options.copyWith(responseType: ResponseType.plain),
      responseBody,
    );

    if (transformed == null) return null;
    if (transformed is! String) return transformed;

    final body = transformed;
    if (body.isEmpty) return null;

    if (responseType == ResponseType.json) {
      // Execute the decoding in a background isolate
      return compute(jsonDecodeCallback, body);
    }

    return body;
  }
}

/// The top-level function used by [compute] for decoding.
dynamic _decodeJson(String encoded) {
  return json.decode(encoded);
}
