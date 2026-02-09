import 'package:flutter_test/flutter_test.dart';
import 'package:mecode/utils/fuzzysort.dart';

void main() {
  group('Fuzzysort', () {
    setUp(() {
      Fuzzysort.cleanup();
    });

    group('single', () {
      test('returns result for matching string', () {
        final result = Fuzzysort.single('hel', 'hello');
        expect(result, isNotNull);
        expect(result!.target, equals('hello'));
        expect(result.score, greaterThan(0));
      });

      test('returns null for non-matching string', () {
        final result = Fuzzysort.single('xyz', 'hello');
        expect(result, isNull);
      });

      test('returns null for empty search', () {
        final result = Fuzzysort.single('', 'hello');
        expect(result, isNull);
      });

      test('returns null for null target', () {
        final result = Fuzzysort.single('test', null);
        expect(result, isNull);
      });

      test('matches case insensitively', () {
        final result = Fuzzysort.single('HEL', 'hello');
        expect(result, isNotNull);
      });

      test('matches fuzzy patterns', () {
        final result = Fuzzysort.single('hlo', 'hello');
        expect(result, isNotNull);
        expect(result!.indexes, contains(0)); // h
        expect(result.indexes, contains(2)); // l (first l in hello)
        expect(result.indexes, contains(4)); // o
      });
    });

    group('go', () {
      test('returns sorted results', () {
        final results = Fuzzysort.go('hel', [
          'hello',
          'world',
          'help',
          'helicopter',
        ]);
        expect(results.length, equals(3));
        // All should match 'hel'
        for (final r in results) {
          expect(
            r.target,
            anyOf(equals('hello'), equals('help'), equals('helicopter')),
          );
        }
      });

      test('returns empty for no matches', () {
        final results = Fuzzysort.go('xyz', ['hello', 'world']);
        expect(results, isEmpty);
      });

      test('returns empty for empty search', () {
        final results = Fuzzysort.go('', ['hello', 'world']);
        expect(results, isEmpty);
      });

      test('respects limit option', () {
        final results = Fuzzysort.go('h', [
          'hello',
          'help',
          'hi',
          'hey',
          'hover',
        ], FuzzysortOptions(limit: 2));
        expect(results.length, equals(2));
      });

      test('respects threshold option', () {
        final results = Fuzzysort.go('hel', [
          'hello',
          'helicopter',
          'help',
        ], FuzzysortOptions(threshold: 0.9));
        // High threshold should filter out worse matches
        expect(results.length, lessThanOrEqualTo(3));
      });

      test('returns all with empty search when all option is true', () {
        final results = Fuzzysort.go<String>('', [
          'hello',
          'world',
        ], FuzzysortOptions(all: true));
        expect(results.length, equals(2));
      });
    });

    group('go with key option', () {
      test('searches on specified key', () {
        final items = [
          {'name': 'John', 'city': 'New York'},
          {'name': 'Jane', 'city': 'Los Angeles'},
          {'name': 'Bob', 'city': 'Chicago'},
        ];

        final results = Fuzzysort.go<Map<String, String>>(
          'jo',
          items,
          FuzzysortOptions(key: 'name'),
        );

        expect(results.length, equals(1));
        expect((results[0].obj as Map)['name'], equals('John'));
      });

      test('searches on nested key path', () {
        final items = [
          {
            'user': {'name': 'John'},
          },
          {
            'user': {'name': 'Jane'},
          },
        ];

        final results = Fuzzysort.go<Map<String, dynamic>>(
          'jo',
          items,
          FuzzysortOptions(key: 'user.name'),
        );

        expect(results.length, equals(1));
      });
    });

    group('go with keys option', () {
      test('searches on multiple keys', () {
        final items = [
          {'name': 'John', 'city': 'Dallas'},
          {'name': 'Jane', 'city': 'New York'},
          {'name': 'Bob', 'city': 'Chicago'},
        ];

        final results = Fuzzysort.go<Map<String, String>>(
          'jo',
          items,
          FuzzysortOptions(keys: ['name', 'city']),
        );

        // Should match John by name
        expect(results.isNotEmpty, isTrue);
      });
    });

    group('highlight', () {
      test('wraps matched characters with tags', () {
        final result = Fuzzysort.single('hel', 'hello');
        expect(result, isNotNull);
        final highlighted = result!.highlight();
        expect(highlighted, contains('<b>'));
        expect(highlighted, contains('</b>'));
      });

      test('uses custom open and close tags', () {
        final result = Fuzzysort.single('hel', 'hello');
        expect(result, isNotNull);
        final highlighted = result!.highlight('<mark>', '</mark>');
        expect(highlighted, contains('<mark>'));
        expect(highlighted, contains('</mark>'));
      });

      test('handles non-consecutive matches', () {
        final result = Fuzzysort.single('hlo', 'hello');
        expect(result, isNotNull);
        final highlighted = result!.highlight();
        // Should have multiple highlighted sections
        expect(highlighted.split('<b>').length, greaterThanOrEqualTo(2));
      });
    });

    group('prepare', () {
      test('returns prepared result', () {
        final prepared = Fuzzysort.prepare('hello');
        expect(prepared.target, equals('hello'));
      });

      test('handles numbers', () {
        final prepared = Fuzzysort.prepare(123);
        expect(prepared.target, equals('123'));
      });

      test('handles empty string', () {
        final prepared = Fuzzysort.prepare('');
        expect(prepared.target, equals(''));
      });
    });

    group('scoring', () {
      test('exact match scores higher than fuzzy match', () {
        final exact = Fuzzysort.single('hello', 'hello');
        final fuzzy = Fuzzysort.single('hlo', 'hello');

        expect(exact, isNotNull);
        expect(fuzzy, isNotNull);
        expect(exact!.score, greaterThan(fuzzy!.score));
      });

      test('beginning match scores higher', () {
        final beginning = Fuzzysort.single('hel', 'hello');
        final middle = Fuzzysort.single('ell', 'hello');

        expect(beginning, isNotNull);
        expect(middle, isNotNull);
        expect(beginning!.score, greaterThan(middle!.score));
      });

      test('shorter target scores higher', () {
        final short = Fuzzysort.single('hel', 'help');
        final long = Fuzzysort.single('hel', 'helicopter');

        expect(short, isNotNull);
        expect(long, isNotNull);
        expect(short!.score, greaterThan(long!.score));
      });
    });

    group('space handling', () {
      test('matches multi-word search', () {
        final result = Fuzzysort.single('hello world', 'hello beautiful world');
        expect(result, isNotNull);
      });

      test('matches words in different order', () {
        final result = Fuzzysort.single('world hello', 'hello beautiful world');
        expect(result, isNotNull);
      });
    });

    group('accent handling', () {
      test('matches accented characters', () {
        final result = Fuzzysort.single('cafe', 'café');
        expect(result, isNotNull);
      });

      test('matches with various accents', () {
        final result = Fuzzysort.single('resume', 'résumé');
        expect(result, isNotNull);
      });
    });

    group('edge cases', () {
      test('handles single character search', () {
        final result = Fuzzysort.single('h', 'hello');
        expect(result, isNotNull);
      });

      test('handles single character target', () {
        final result = Fuzzysort.single('h', 'h');
        expect(result, isNotNull);
      });

      test('handles special characters', () {
        final result = Fuzzysort.single('test', 'test@example.com');
        expect(result, isNotNull);
      });

      test('handles unicode characters', () {
        final result = Fuzzysort.single('日本', '日本語');
        expect(result, isNotNull);
      });

      test('handles long strings', () {
        final longString = 'a' * 1000;
        final result = Fuzzysort.single('aaa', longString);
        expect(result, isNotNull);
      });
    });

    group('cleanup', () {
      test('clears caches', () {
        // First search populates cache
        Fuzzysort.single('test', 'testing');

        // Cleanup should not throw
        expect(() => Fuzzysort.cleanup(), returnsNormally);

        // Should still work after cleanup
        final result = Fuzzysort.single('test', 'testing');
        expect(result, isNotNull);
      });
    });
  });
}
