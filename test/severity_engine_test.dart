import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app1/core/triage/severity_engine.dart';

void main() {
  group('SeverityEngine Triage Tests', () {
    test('No matches should return Low tier with score 1', () {
      final result = SeverityEngine.triage(
        description: 'Hello, everything is fine here.',
        needType: 'none',
      );

      expect(result.score, equals(1));
      expect(result.tier, equals('Low'));
      expect(result.matchedKeywords, isEmpty);
      expect(result.explanation, contains('LOW/UNCLASSIFIED'));
    });

    test('Tier 3 keywords (Needs) should triage to Needs tier with score 4', () {
      final result = SeverityEngine.triage(
        description: 'We need some water and a blanket.',
        needType: 'medical',
      );

      expect(result.score, equals(4));
      expect(result.tier, equals('Needs'));
      expect(result.matchedKeywords, containsAll(['water', 'blanket']));
      expect(result.explanation, contains('NEEDS'));
    });

    test('Tier 2 keywords (Urgent) should triage to Urgent tier with score 7', () {
      final result = SeverityEngine.triage(
        description: 'Someone is injured and stranded in the water.',
        needType: 'medical',
      );

      // Note: 'injured' and 'stranded' are Tier 2. 'water' is Tier 3. Tier 2 wins.
      expect(result.score, equals(7));
      expect(result.tier, equals('Urgent'));
      expect(result.matchedKeywords, contains('injured'));
      expect(result.matchedKeywords, contains('stranded'));
      expect(result.explanation, contains('URGENT'));
    });

    test('Single Tier 1 keyword (Critical) should triage to Critical tier with score 9', () {
      final result = SeverityEngine.triage(
        description: 'There is a fire in the building.',
        needType: 'shelter',
      );

      expect(result.score, equals(9));
      expect(result.tier, equals('Critical'));
      expect(result.matchedKeywords, contains('fire'));
      expect(result.explanation, contains('CRITICAL'));
    });

    test('Multiple Tier 1 keywords should trigger override score of 10', () {
      final result = SeverityEngine.triage(
        description: 'A person is trapped and unconscious after the structure collapsed.',
        needType: 'medical',
      );

      expect(result.score, equals(10));
      expect(result.tier, equals('Critical'));
      expect(result.matchedKeywords, contains('trapped'));
      expect(result.matchedKeywords, contains('unconscious'));
      expect(result.matchedKeywords, contains('collapsed'));
      expect(result.explanation, contains('Multiple Tier 1 Override'));
    });

    test('Need category inclusion should trigger matching', () {
      // Input has no keywords, but need category is 'fire' (Tier 1 keyword)
      final result = SeverityEngine.triage(
        description: 'Everything is burning.',
        needType: 'fire',
      );

      expect(result.score, equals(9));
      expect(result.tier, equals('Critical'));
      expect(result.matchedKeywords, contains('fire'));
    });

    test('Lowercase normalization should ensure case-insensitive matching', () {
      final result = SeverityEngine.triage(
        description: 'TRAPPED AND BLEEDING HEAVILY!',
        needType: 'MEDICAL',
      );

      expect(result.score, equals(10));
      expect(result.tier, equals('Critical'));
      expect(result.matchedKeywords, contains('trapped'));
      expect(result.matchedKeywords, contains('bleeding heavily'));
    });
  });
}
