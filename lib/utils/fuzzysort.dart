/// Fuzzysort v3.0.2 - Dart port
/// https://github.com/farzher/fuzzysort
///
/// A fast, accurate fuzzy search library ported from JavaScript.
library;

import 'dart:math' as math;

// Constants
const double _negativeInfinity = double.negativeInfinity;

/// Result of a fuzzy search match
class FuzzysortResult {
  /// The original target string
  final String target;

  /// Internal score (higher is better match, but negative)
  double _score;

  /// Internal indexes array with length tracking
  List<int> _indexes;
  int _indexesLen;

  /// The original object (for key-based searches)
  Object? obj;

  // Internal cached data
  final String _targetLower;
  final List<int> _targetLowerCodes;
  List<int>? _nextBeginningIndexes;
  final int _bitflags;

  FuzzysortResult({
    required this.target,
    double? score,
    List<int>? indexes,
    this.obj,
    String? targetLower,
    List<int>? targetLowerCodes,
    List<int>? nextBeginningIndexes,
    int? bitflags,
  }) : _score = score ?? _negativeInfinity,
       _indexes = indexes ?? [],
       _indexesLen = indexes?.length ?? 0,
       _targetLower = targetLower ?? '',
       _targetLowerCodes = targetLowerCodes ?? [],
       _nextBeginningIndexes = nextBeginningIndexes,
       _bitflags = bitflags ?? 0;

  /// Get the normalized score (0-1, higher is better)
  double get score => _normalizeScore(_score);

  /// Set score from normalized value
  set score(double normalizedScore) {
    _score = _denormalizeScore(normalizedScore);
  }

  /// Get the matched character indexes, sorted
  List<int> get indexes {
    final result = _indexes.sublist(0, _indexesLen);
    result.sort();
    return result;
  }

  /// Highlight matched characters in the target string
  ///
  /// [open] - Opening tag (default: '<b>')
  /// [close] - Closing tag (default: '</b>')
  String highlight([String open = '<b>', String close = '</b>']) {
    final targetLen = target.length;
    final sortedIndexes = indexes;
    var highlighted = StringBuffer();
    var indexesI = 0;
    var opened = false;

    for (var i = 0; i < targetLen; ++i) {
      final char = target[i];
      if (indexesI < sortedIndexes.length && sortedIndexes[indexesI] == i) {
        ++indexesI;
        if (!opened) {
          opened = true;
          highlighted.write(open);
        }

        if (indexesI == sortedIndexes.length) {
          highlighted.write(char);
          highlighted.write(close);
          highlighted.write(target.substring(i + 1));
          break;
        }
      } else {
        if (opened) {
          opened = false;
          highlighted.write(close);
        }
      }
      highlighted.write(char);
    }

    return highlighted.toString();
  }

  /// Highlight with a callback function
  List<dynamic> highlightCallback(
    String Function(String matched, int matchIndex) callback,
  ) {
    final targetLen = target.length;
    final sortedIndexes = indexes;
    var highlighted = StringBuffer();
    var matchI = 0;
    var indexesI = 0;
    var opened = false;
    final parts = <dynamic>[];

    for (var i = 0; i < targetLen; ++i) {
      final char = target[i];
      if (indexesI < sortedIndexes.length && sortedIndexes[indexesI] == i) {
        ++indexesI;
        if (!opened) {
          opened = true;
          parts.add(highlighted.toString());
          highlighted = StringBuffer();
        }

        if (indexesI == sortedIndexes.length) {
          highlighted.write(char);
          parts.add(callback(highlighted.toString(), matchI++));
          parts.add(target.substring(i + 1));
          break;
        }
      } else {
        if (opened) {
          opened = false;
          parts.add(callback(highlighted.toString(), matchI++));
          highlighted = StringBuffer();
        }
      }
      highlighted.write(char);
    }

    return parts;
  }

  FuzzysortResult _copy() {
    return FuzzysortResult(
      target: target,
      score: _score,
      indexes: List<int>.from(_indexes),
      obj: obj,
      targetLower: _targetLower,
      targetLowerCodes: List<int>.from(_targetLowerCodes),
      nextBeginningIndexes: _nextBeginningIndexes != null
          ? List<int>.from(_nextBeginningIndexes!)
          : null,
      bitflags: _bitflags,
    ).._indexesLen = _indexesLen;
  }
}

/// Result for multi-key searches
class KeysResult extends FuzzysortResult {
  final List<FuzzysortResult?> _keyResults;

  KeysResult(int keysLen)
    : _keyResults = List<FuzzysortResult?>.filled(keysLen, null),
      super(target: '');

  FuzzysortResult? operator [](int index) => _keyResults[index];
  void operator []=(int index, FuzzysortResult? value) =>
      _keyResults[index] = value;

  int get length => _keyResults.length;
}

/// Prepared search query
class _PreparedSearch {
  final List<int> lowerCodes;
  final String lower;
  final bool containsSpace;
  final int bitflags;
  final List<_PreparedSearch> spaceSearches;

  _PreparedSearch({
    required this.lowerCodes,
    required this.lower,
    required this.containsSpace,
    required this.bitflags,
    this.spaceSearches = const [],
  });
}

/// Lower info for string preparation
class _LowerInfo {
  final List<int> lowerCodes;
  final int bitflags;
  final bool containsSpace;
  final String lower;

  _LowerInfo({
    required this.lowerCodes,
    required this.bitflags,
    required this.containsSpace,
    required this.lower,
  });
}

/// Search options
class FuzzysortOptions<T> {
  /// Single key to search on objects
  final String? key;

  /// Multiple keys to search on objects
  final List<String>? keys;

  /// Minimum score threshold (0-1)
  final double threshold;

  /// Maximum number of results
  final int limit;

  /// Return all targets when search is empty
  final bool all;

  /// Custom scoring function
  final double Function(KeysResult)? scoreFn;

  /// Function to get value from object (for complex key paths)
  final dynamic Function(T obj, String key)? getValue;

  const FuzzysortOptions({
    this.key,
    this.keys,
    this.threshold = 0,
    this.limit = 0x7FFFFFFF, // max int
    this.all = false,
    this.scoreFn,
    this.getValue,
  });
}

/// Main Fuzzysort class with static methods
class Fuzzysort {
  // Caches
  static final Map<String, FuzzysortResult> _preparedCache = {};
  static final Map<String, _PreparedSearch> _preparedSearchCache = {};

  // Reusable arrays to reduce garbage collection
  static final List<int> _matchesSimple = List<int>.filled(256, 0);
  static final List<int> _matchesStrict = List<int>.filled(256, 0);
  static final List<int> _nextBeginningIndexesChanges = List<int>.filled(
    2048,
    0,
  );
  static final List<double> _keysSpacesBestScores = List<double>.filled(32, 0);
  static final List<double> _allowPartialMatchScores = List<double>.filled(
    32,
    0,
  );

  // Priority queue for results
  static final _FastPriorityQueue _q = _FastPriorityQueue();

  // Empty target placeholder
  static final FuzzysortResult _noTarget = prepare('');

  /// Search a single target
  static FuzzysortResult? single(String? search, dynamic target) {
    if (search == null || search.isEmpty || target == null) return null;

    final preparedSearch = _getPreparedSearch(search);
    FuzzysortResult prepared;
    if (target is FuzzysortResult) {
      prepared = target;
    } else {
      prepared = _getPrepared(target.toString());
    }

    final searchBitflags = preparedSearch.bitflags;
    if ((searchBitflags & prepared._bitflags) != searchBitflags) return null;

    return _algorithm(preparedSearch, prepared);
  }

  /// Search multiple targets
  static List<FuzzysortResult> go<T>(
    String? search,
    List<T> targets, [
    FuzzysortOptions<T>? options,
  ]) {
    if (search == null || search.isEmpty) {
      if (options?.all == true) {
        return _all(targets, options);
      }
      return [];
    }

    final preparedSearch = _getPreparedSearch(search);
    final searchBitflags = preparedSearch.bitflags;
    final containsSpace = preparedSearch.containsSpace;

    final threshold = _denormalizeScore(options?.threshold ?? 0);
    final limit = options?.limit ?? 0x7FFFFFFF;

    var resultsLen = 0;
    var limitedCount = 0;
    final targetsLen = targets.length;

    void pushResult(FuzzysortResult result) {
      if (resultsLen < limit) {
        _q.add(result);
        ++resultsLen;
      } else {
        ++limitedCount;
        if (result._score > _q.peek()!._score) {
          _q.replaceTop(result);
        }
      }
    }

    // Temporary arrays for keys search
    final tmpTargets = List<FuzzysortResult?>.filled(32, null);
    final tmpResults = List<FuzzysortResult?>.filled(32, null);

    // options.key
    if (options?.key != null) {
      final key = options!.key!;
      for (var i = 0; i < targetsLen; ++i) {
        final obj = targets[i];
        final targetValue = _getValue(obj, key, options.getValue);
        if (targetValue == null) continue;

        FuzzysortResult target;
        if (targetValue is FuzzysortResult) {
          target = targetValue;
        } else {
          target = _getPrepared(targetValue.toString());
        }

        if ((searchBitflags & target._bitflags) != searchBitflags) continue;
        final result = _algorithm(preparedSearch, target);
        if (result == null) continue;
        if (result._score < threshold) continue;

        result.obj = obj;
        pushResult(result);
      }

      // options.keys
    } else if (options?.keys != null) {
      final keys = options!.keys!;
      final keysLen = keys.length;

      outer:
      for (var i = 0; i < targetsLen; ++i) {
        final obj = targets[i];

        // Early out based on bitflags
        var keysBitflags = 0;
        for (var keyI = 0; keyI < keysLen; ++keyI) {
          final key = keys[keyI];
          final targetValue = _getValue(obj, key, options.getValue);
          if (targetValue == null) {
            tmpTargets[keyI] = _noTarget;
            continue;
          }

          FuzzysortResult target;
          if (targetValue is FuzzysortResult) {
            target = targetValue;
          } else {
            target = _getPrepared(targetValue.toString());
          }
          tmpTargets[keyI] = target;
          keysBitflags |= target._bitflags;
        }

        if ((searchBitflags & keysBitflags) != searchBitflags) continue;

        if (containsSpace) {
          for (var j = 0; j < preparedSearch.spaceSearches.length; j++) {
            _keysSpacesBestScores[j] = _negativeInfinity;
          }
        }

        for (var keyI = 0; keyI < keysLen; ++keyI) {
          final target = tmpTargets[keyI]!;
          if (identical(target, _noTarget)) {
            tmpResults[keyI] = _noTarget;
            continue;
          }

          final result = _algorithm(
            preparedSearch,
            target,
            allowSpaces: false,
            allowPartialMatch: containsSpace,
          );
          if (result == null) {
            tmpResults[keyI] = _noTarget;
            continue;
          }
          tmpResults[keyI] = result;

          if (containsSpace) {
            for (var j = 0; j < preparedSearch.spaceSearches.length; j++) {
              if (_allowPartialMatchScores[j] > -1000) {
                if (_keysSpacesBestScores[j] > _negativeInfinity) {
                  final tmp =
                      (_keysSpacesBestScores[j] + _allowPartialMatchScores[j]) /
                      4;
                  if (tmp > _keysSpacesBestScores[j]) {
                    _keysSpacesBestScores[j] = tmp;
                  }
                }
              }
              if (_allowPartialMatchScores[j] > _keysSpacesBestScores[j]) {
                _keysSpacesBestScores[j] = _allowPartialMatchScores[j];
              }
            }
          }
        }

        if (containsSpace) {
          for (var j = 0; j < preparedSearch.spaceSearches.length; j++) {
            if (_keysSpacesBestScores[j] == _negativeInfinity) continue outer;
          }
        } else {
          var hasAtLeast1Match = false;
          for (var j = 0; j < keysLen; j++) {
            if (tmpResults[j]!._score != _negativeInfinity) {
              hasAtLeast1Match = true;
              break;
            }
          }
          if (!hasAtLeast1Match) continue;
        }

        final objResults = KeysResult(keysLen);
        for (var j = 0; j < keysLen; j++) {
          objResults[j] = tmpResults[j];
        }

        double score;
        if (containsSpace) {
          score = 0;
          for (var j = 0; j < preparedSearch.spaceSearches.length; j++) {
            score += _keysSpacesBestScores[j];
          }
        } else {
          score = _negativeInfinity;
          for (var j = 0; j < keysLen; j++) {
            final result = objResults[j];
            if (result != null && result._score > -1000) {
              if (score > _negativeInfinity) {
                final tmp = (score + result._score) / 4;
                if (tmp > score) score = tmp;
              }
            }
            if (result != null && result._score > score) score = result._score;
          }
        }

        objResults.obj = obj;
        objResults._score = score;

        if (options.scoreFn != null) {
          final newScore = options.scoreFn!(objResults);
          if (newScore == 0) continue;
          score = _denormalizeScore(newScore);
          objResults._score = score;
        }

        if (score < threshold) continue;
        pushResult(objResults);
      }

      // no keys
    } else {
      for (var i = 0; i < targetsLen; ++i) {
        final targetValue = targets[i];
        if (targetValue == null) continue;

        FuzzysortResult target;
        if (targetValue is FuzzysortResult) {
          target = targetValue;
        } else {
          target = _getPrepared(targetValue.toString());
        }

        if ((searchBitflags & target._bitflags) != searchBitflags) continue;
        final result = _algorithm(preparedSearch, target);
        if (result == null) continue;
        if (result._score < threshold) continue;

        pushResult(result);
      }
    }

    if (resultsLen == 0) return [];

    final results = <FuzzysortResult>[];
    for (var i = resultsLen - 1; i >= 0; --i) {
      results.add(_q.poll()!);
    }

    return results.reversed.toList();
  }

  /// Prepare a target string for faster repeated searches
  static FuzzysortResult prepare(dynamic target) {
    String targetStr;
    if (target is num) {
      targetStr = target.toString();
    } else if (target is String) {
      targetStr = target;
    } else {
      targetStr = '';
    }

    final info = _prepareLowerInfo(targetStr);
    return FuzzysortResult(
      target: targetStr,
      targetLower: info.lower,
      targetLowerCodes: info.lowerCodes,
      bitflags: info.bitflags,
    );
  }

  /// Clear all caches
  static void cleanup() {
    _preparedCache.clear();
    _preparedSearchCache.clear();
  }

  // ============ Internal methods ============

  static dynamic _getValue<T>(
    T obj,
    String prop,
    dynamic Function(T, String)? customGetter,
  ) {
    if (customGetter != null) {
      return customGetter(obj, prop);
    }

    if (obj is Map) {
      // Try direct access first
      var tmp = obj[prop];
      if (tmp != null) return tmp;

      // Try nested path
      if (prop.contains('.')) {
        final segs = prop.split('.');
        dynamic current = obj;
        for (final seg in segs) {
          if (current is Map) {
            current = current[seg];
          } else {
            return null;
          }
          if (current == null) return null;
        }
        return current;
      }
    }

    return null;
  }

  static FuzzysortResult _getPrepared(String target) {
    if (target.length > 999) return prepare(target);
    var prepared = _preparedCache[target];
    if (prepared != null) return prepared;
    prepared = prepare(target);
    _preparedCache[target] = prepared;
    return prepared;
  }

  static _PreparedSearch _getPreparedSearch(String search) {
    if (search.length > 999) return _prepareSearch(search);
    var prepared = _preparedSearchCache[search];
    if (prepared != null) return prepared;
    prepared = _prepareSearch(search);
    _preparedSearchCache[search] = prepared;
    return prepared;
  }

  static _PreparedSearch _prepareSearch(String search) {
    search = search.trim();

    final info = _prepareLowerInfo(search);
    final spaceSearches = <_PreparedSearch>[];

    if (info.containsSpace) {
      var searches = search.split(RegExp(r'\s+'));
      searches = searches.toSet().toList(); // distinct

      for (var i = 0; i < searches.length; i++) {
        if (searches[i].isEmpty) continue;
        final subInfo = _prepareLowerInfo(searches[i]);
        spaceSearches.add(
          _PreparedSearch(
            lowerCodes: subInfo.lowerCodes,
            lower: searches[i].toLowerCase(),
            containsSpace: false,
            bitflags: subInfo.bitflags,
          ),
        );
      }
    }

    return _PreparedSearch(
      lowerCodes: info.lowerCodes,
      lower: info.lower,
      containsSpace: info.containsSpace,
      bitflags: info.bitflags,
      spaceSearches: spaceSearches,
    );
  }

  static String _removeAccents(String str) {
    // Handle Latin script characters - normalize and remove combining marks
    final buffer = StringBuffer();
    final normalized = str.replaceAllMapped(
      RegExp(r'[\u0041-\u024F]+'), // Latin characters range
      (match) => match.group(0)!.replaceAllMapped(
        RegExp(r'[àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ]', caseSensitive: false),
        (m) {
          const accented =
              'àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞ';
          const plain =
              'aaaaaaaceeeeiiiidnoooooouuuuyyyssAAAAAAABCEEEEIIIIDNOOOOOOUUUUYY';
          final idx = accented.indexOf(m.group(0)!);
          return idx >= 0 ? plain[idx] : m.group(0)!;
        },
      ),
    );
    buffer.write(normalized);
    return buffer.toString();
  }

  static _LowerInfo _prepareLowerInfo(String str) {
    str = _removeAccents(str);
    final strLen = str.length;
    final lower = str.toLowerCase();
    final lowerCodes = <int>[];
    var bitflags = 0;
    var containsSpace = false;

    for (var i = 0; i < strLen; ++i) {
      final lowerCode = lower.codeUnitAt(i);
      lowerCodes.add(lowerCode);

      if (lowerCode == 32) {
        // space
        containsSpace = true;
        continue;
      }

      int bit;
      if (lowerCode >= 97 && lowerCode <= 122) {
        // a-z
        bit = lowerCode - 97;
      } else if (lowerCode >= 48 && lowerCode <= 57) {
        // 0-9
        bit = 26;
      } else if (lowerCode <= 127) {
        // other ascii
        bit = 30;
      } else {
        // other utf8
        bit = 31;
      }
      bitflags |= 1 << bit;
    }

    return _LowerInfo(
      lowerCodes: lowerCodes,
      bitflags: bitflags,
      containsSpace: containsSpace,
      lower: lower,
    );
  }

  static List<int> _prepareBeginningIndexes(String target) {
    final targetLen = target.length;
    final beginningIndexes = <int>[];
    var wasUpper = false;
    var wasAlphanum = false;

    for (var i = 0; i < targetLen; ++i) {
      final targetCode = target.codeUnitAt(i);
      final isUpper = targetCode >= 65 && targetCode <= 90;
      final isAlphanum =
          isUpper ||
          (targetCode >= 97 && targetCode <= 122) ||
          (targetCode >= 48 && targetCode <= 57);
      final isBeginning = (isUpper && !wasUpper) || !wasAlphanum || !isAlphanum;
      wasUpper = isUpper;
      wasAlphanum = isAlphanum;
      if (isBeginning) beginningIndexes.add(i);
    }

    return beginningIndexes;
  }

  static List<int> _prepareNextBeginningIndexes(String target) {
    target = _removeAccents(target);
    final targetLen = target.length;
    final beginningIndexes = _prepareBeginningIndexes(target);
    final nextBeginningIndexes = List<int>.filled(targetLen, targetLen);

    if (beginningIndexes.isEmpty) return nextBeginningIndexes;

    var lastIsBeginning = beginningIndexes[0];
    var lastIsBeginningI = 0;

    for (var i = 0; i < targetLen; ++i) {
      if (lastIsBeginning > i) {
        nextBeginningIndexes[i] = lastIsBeginning;
      } else {
        lastIsBeginningI++;
        if (lastIsBeginningI < beginningIndexes.length) {
          lastIsBeginning = beginningIndexes[lastIsBeginningI];
          nextBeginningIndexes[i] = lastIsBeginning;
        } else {
          nextBeginningIndexes[i] = targetLen;
        }
      }
    }

    return nextBeginningIndexes;
  }

  static FuzzysortResult? _algorithm(
    _PreparedSearch preparedSearch,
    FuzzysortResult prepared, {
    bool allowSpaces = false,
    bool allowPartialMatch = false,
  }) {
    if (!allowSpaces && preparedSearch.containsSpace) {
      return _algorithmSpaces(preparedSearch, prepared, allowPartialMatch);
    }

    final searchLower = preparedSearch.lower;
    final searchLowerCodes = preparedSearch.lowerCodes;
    var searchLowerCode = searchLowerCodes[0];
    final targetLowerCodes = prepared._targetLowerCodes;
    final searchLen = searchLowerCodes.length;
    final targetLen = targetLowerCodes.length;
    var searchI = 0;
    var targetI = 0;
    var matchesSimpleLen = 0;

    // Very basic fuzzy match - find sequential matches
    for (;;) {
      final isMatch = searchLowerCode == targetLowerCodes[targetI];
      if (isMatch) {
        _matchesSimple[matchesSimpleLen++] = targetI;
        ++searchI;
        if (searchI == searchLen) break;
        searchLowerCode = searchLowerCodes[searchI];
      }
      ++targetI;
      if (targetI >= targetLen) return null; // Failed to find searchI
    }

    searchI = 0;
    var successStrict = false;
    var matchesStrictLen = 0;

    var nextBeginningIndexes = prepared._nextBeginningIndexes;
    if (nextBeginningIndexes == null) {
      nextBeginningIndexes = _prepareNextBeginningIndexes(prepared.target);
      prepared._nextBeginningIndexes = nextBeginningIndexes;
    }

    targetI = _matchesSimple[0] == 0
        ? 0
        : nextBeginningIndexes[_matchesSimple[0] - 1];

    // Try strict matching
    var backtrackCount = 0;
    if (targetI != targetLen) {
      for (;;) {
        if (targetI >= targetLen) {
          if (searchI <= 0) break;

          ++backtrackCount;
          if (backtrackCount > 200) break;

          --searchI;
          final lastMatch = _matchesStrict[--matchesStrictLen];
          targetI = nextBeginningIndexes[lastMatch];
        } else {
          final isMatch =
              searchLowerCodes[searchI] == targetLowerCodes[targetI];
          if (isMatch) {
            _matchesStrict[matchesStrictLen++] = targetI;
            ++searchI;
            if (searchI == searchLen) {
              successStrict = true;
              break;
            }
            ++targetI;
          } else {
            targetI = nextBeginningIndexes[targetI];
          }
        }
      }
    }

    // Check for substring match
    final substringSearchStart = _matchesSimple[0];
    var substringIndex = searchLen <= 1
        ? -1
        : prepared._targetLower.indexOf(searchLower, substringSearchStart);
    var isSubstring = substringIndex != -1;
    var isSubstringBeginning = !isSubstring
        ? false
        : substringIndex == 0 ||
              nextBeginningIndexes[substringIndex - 1] == substringIndex;

    // Try to find substring at beginning index
    if (isSubstring && !isSubstringBeginning) {
      for (
        var i = 0;
        i < nextBeginningIndexes.length;
        i = nextBeginningIndexes[i]
      ) {
        if (i <= substringIndex) continue;

        var s = 0;
        for (; s < searchLen; s++) {
          if (i + s >= targetLowerCodes.length ||
              searchLowerCodes[s] != prepared._targetLowerCodes[i + s]) {
            break;
          }
        }
        if (s == searchLen) {
          substringIndex = i;
          isSubstringBeginning = true;
          break;
        }
      }
    }

    // Calculate score
    double calculateScore(List<int> matches, int matchesLen) {
      var score = 0.0;
      var extraMatchGroupCount = 0;

      for (var i = 1; i < searchLen; ++i) {
        if (matches[i] - matches[i - 1] != 1) {
          score -= matches[i];
          ++extraMatchGroupCount;
        }
      }

      final unmatchedDistance =
          matches[searchLen - 1] - matches[0] - (searchLen - 1);
      score -= (12 + unmatchedDistance) * extraMatchGroupCount;

      if (matches[0] != 0) {
        score -= matches[0] * matches[0] * 0.2;
      }

      if (!successStrict) {
        score *= 1000;
      } else {
        var uniqueBeginningIndexes = 1;
        for (
          var i = nextBeginningIndexes![0];
          i < targetLen;
          i = nextBeginningIndexes[i]
        ) {
          ++uniqueBeginningIndexes;
        }
        if (uniqueBeginningIndexes > 24) {
          score *= (uniqueBeginningIndexes - 24) * 10;
        }
      }

      score -= (targetLen - searchLen) / 2;

      if (isSubstring) {
        score /= 1 + searchLen * searchLen * 1;
      }
      if (isSubstringBeginning) {
        score /= 1 + searchLen * searchLen * 1;
      }

      score -= (targetLen - searchLen) / 2;

      return score;
    }

    List<int> matchesBest;
    double score;

    if (!successStrict) {
      if (isSubstring) {
        for (var i = 0; i < searchLen; ++i) {
          _matchesSimple[i] = substringIndex + i;
        }
      }
      matchesBest = _matchesSimple;
      score = calculateScore(matchesBest, matchesSimpleLen);
    } else {
      if (isSubstringBeginning) {
        for (var i = 0; i < searchLen; ++i) {
          _matchesSimple[i] = substringIndex + i;
        }
        matchesBest = _matchesSimple;
        score = calculateScore(_matchesSimple, searchLen);
      } else {
        matchesBest = _matchesStrict;
        score = calculateScore(_matchesStrict, matchesStrictLen);
      }
    }

    final result = FuzzysortResult(
      target: prepared.target,
      score: score,
      targetLower: prepared._targetLower,
      targetLowerCodes: prepared._targetLowerCodes,
      nextBeginningIndexes: prepared._nextBeginningIndexes,
      bitflags: prepared._bitflags,
    );
    result._score = score;

    for (var i = 0; i < searchLen; ++i) {
      result._indexes.add(matchesBest[i]);
    }
    result._indexesLen = searchLen;

    return result;
  }

  static FuzzysortResult? _algorithmSpaces(
    _PreparedSearch preparedSearch,
    FuzzysortResult target,
    bool allowPartialMatch,
  ) {
    final seenIndexes = <int>{};
    var score = 0.0;
    FuzzysortResult? result;

    var firstSeenIndexLastSearch = 0;
    final searches = preparedSearch.spaceSearches;
    final searchesLen = searches.length;
    var changesLen = 0;

    // Save original next beginning indexes for restoration
    List<int>? originalNextBeginningIndexes;
    if (target._nextBeginningIndexes != null) {
      originalNextBeginningIndexes = List<int>.from(
        target._nextBeginningIndexes!,
      );
    }

    void resetNextBeginningIndexes() {
      if (originalNextBeginningIndexes != null) {
        target._nextBeginningIndexes = originalNextBeginningIndexes;
      }
    }

    var hasAtLeast1Match = false;
    for (var i = 0; i < searchesLen; ++i) {
      _allowPartialMatchScores[i] = _negativeInfinity;
      final search = searches[i];

      result = _algorithm(search, target);
      if (allowPartialMatch) {
        if (result == null) continue;
        hasAtLeast1Match = true;
      } else {
        if (result == null) {
          resetNextBeginningIndexes();
          return null;
        }
      }

      // Mutate _nextBeginningIndexes for next search
      final isTheLastSearch = i == searchesLen - 1;
      if (!isTheLastSearch && result != null) {
        final indexes = result._indexes;
        final indexesLen = result._indexesLen;

        var indexesIsConsecutiveSubstring = true;
        for (var j = 0; j < indexesLen - 1; j++) {
          if (indexes[j + 1] - indexes[j] != 1) {
            indexesIsConsecutiveSubstring = false;
            break;
          }
        }

        if (indexesIsConsecutiveSubstring &&
            target._nextBeginningIndexes != null) {
          final newBeginningIndex = indexes[indexesLen - 1] + 1;
          if (newBeginningIndex > 0 &&
              newBeginningIndex - 1 < target._nextBeginningIndexes!.length) {
            final toReplace =
                target._nextBeginningIndexes![newBeginningIndex - 1];
            for (var j = newBeginningIndex - 1; j >= 0; j--) {
              if (toReplace != target._nextBeginningIndexes![j]) break;
              target._nextBeginningIndexes![j] = newBeginningIndex;
              _nextBeginningIndexesChanges[changesLen * 2 + 0] = j;
              _nextBeginningIndexesChanges[changesLen * 2 + 1] = toReplace;
              changesLen++;
            }
          }
        }
      }

      if (result != null) {
        score += result._score / searchesLen;
        _allowPartialMatchScores[i] = result._score / searchesLen;

        // Dock points based on order
        if (result._indexes.isNotEmpty &&
            result._indexes[0] < firstSeenIndexLastSearch) {
          score -= (firstSeenIndexLastSearch - result._indexes[0]) * 2;
        }
        if (result._indexes.isNotEmpty) {
          firstSeenIndexLastSearch = result._indexes[0];
        }

        for (var j = 0; j < result._indexesLen; ++j) {
          seenIndexes.add(result._indexes[j]);
        }
      }
    }

    if (allowPartialMatch && !hasAtLeast1Match) return null;

    resetNextBeginningIndexes();

    // Try exact substring match
    final allowSpacesResult = _algorithm(
      preparedSearch,
      target,
      allowSpaces: true,
    );
    if (allowSpacesResult != null && allowSpacesResult._score > score) {
      if (allowPartialMatch) {
        for (var i = 0; i < searchesLen; ++i) {
          _allowPartialMatchScores[i] = allowSpacesResult._score / searchesLen;
        }
      }
      return allowSpacesResult;
    }

    if (allowPartialMatch) {
      result = target._copy();
    }
    if (result == null) return null;

    result._score = score;

    result._indexes.clear();
    for (final index in seenIndexes) {
      result._indexes.add(index);
    }
    result._indexesLen = seenIndexes.length;

    return result;
  }

  static List<FuzzysortResult> _all<T>(
    List<T> targets,
    FuzzysortOptions<T>? options,
  ) {
    final results = <FuzzysortResult>[];
    final limit = options?.limit ?? 0x7FFFFFFF;

    if (options?.key != null) {
      for (var i = 0; i < targets.length; i++) {
        final obj = targets[i];
        final targetValue = _getValue(obj, options!.key!, options.getValue);
        if (targetValue == null) continue;

        FuzzysortResult target;
        if (targetValue is FuzzysortResult) {
          target = targetValue;
        } else {
          target = _getPrepared(targetValue.toString());
        }

        final result = FuzzysortResult(
          target: target.target,
          score: target._score,
        );
        result.obj = obj;
        results.add(result);
        if (results.length >= limit) return results;
      }
    } else if (options?.keys != null) {
      for (var i = 0; i < targets.length; i++) {
        final obj = targets[i];
        final objResults = KeysResult(options!.keys!.length);

        for (var keyI = options.keys!.length - 1; keyI >= 0; --keyI) {
          final targetValue = _getValue(
            obj,
            options.keys![keyI],
            options.getValue,
          );
          if (targetValue == null) {
            objResults[keyI] = _noTarget;
            continue;
          }

          FuzzysortResult target;
          if (targetValue is FuzzysortResult) {
            target = targetValue;
          } else {
            target = _getPrepared(targetValue.toString());
          }
          target._score = _negativeInfinity;
          target._indexesLen = 0;
          objResults[keyI] = target;
        }

        objResults.obj = obj;
        objResults._score = _negativeInfinity;
        results.add(objResults);
        if (results.length >= limit) return results;
      }
    } else {
      for (var i = 0; i < targets.length; i++) {
        final targetValue = targets[i];
        if (targetValue == null) continue;

        FuzzysortResult target;
        if (targetValue is FuzzysortResult) {
          target = targetValue;
        } else {
          target = _getPrepared(targetValue.toString());
        }
        target._score = _negativeInfinity;
        target._indexesLen = 0;
        results.add(target);
        if (results.length >= limit) return results;
      }
    }

    return results;
  }
}

// Score normalization functions
double _normalizeScore(double score) {
  if (score == _negativeInfinity) return 0;
  if (score > 1) return score;
  return math.exp((math.pow((-score + 1), 0.04307) - 1) * -2);
}

double _denormalizeScore(double normalizedScore) {
  if (normalizedScore == 0) return _negativeInfinity;
  if (normalizedScore > 1) return normalizedScore;
  return 1 -
      math.pow((math.log(normalizedScore) / -2 + 1), 1 / 0.04307).toDouble();
}

/// Fast min-heap priority queue for results
class _FastPriorityQueue {
  final List<FuzzysortResult?> _heap = [];
  int _size = 0;

  void add(FuzzysortResult result) {
    var pos = _size;
    if (_heap.length <= _size) {
      _heap.add(result);
    } else {
      _heap[_size] = result;
    }
    _size++;

    // Bubble up
    while (pos > 0) {
      final parent = (pos - 1) >> 1;
      if (result._score < _heap[parent]!._score) {
        _heap[pos] = _heap[parent];
        pos = parent;
      } else {
        break;
      }
    }
    _heap[pos] = result;
  }

  FuzzysortResult? poll() {
    if (_size == 0) return null;
    final result = _heap[0];
    _size--;
    if (_size > 0) {
      _heap[0] = _heap[_size];
      _siftDown();
    }
    return result;
  }

  FuzzysortResult? peek() {
    if (_size == 0) return null;
    return _heap[0];
  }

  void replaceTop(FuzzysortResult result) {
    _heap[0] = result;
    _siftDown();
  }

  void _siftDown() {
    var pos = 0;
    final value = _heap[0]!;

    while (true) {
      final left = (pos << 1) + 1;
      final right = left + 1;

      if (left >= _size) break;

      var smallest = left;
      if (right < _size && _heap[right]!._score < _heap[left]!._score) {
        smallest = right;
      }

      if (_heap[smallest]!._score < value._score) {
        _heap[pos] = _heap[smallest];
        pos = smallest;
      } else {
        break;
      }
    }
    _heap[pos] = value;
  }
}
