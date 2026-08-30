class TriageResult {
  final int score;
  final String tier; // 'Critical', 'Urgent', 'Needs', 'Low'
  final List<String> matchedKeywords;
  final String explanation;

  TriageResult({
    required this.score,
    required this.tier,
    required this.matchedKeywords,
    required this.explanation,
  });
}

class SeverityEngine {
  // Keyword Lists as defined in Section 11 of the Crisis Mesh Spec
  static const List<String> tier1Keywords = [
    'trapped',
    "can't breathe",
    'bleeding heavily',
    'unconscious',
    'not breathing',
    'drowning',
    'fire',
    'collapsed',
    'buried',
    'heart attack',
    'severe injury',
    'dying',
    'child trapped',
    'no pulse',
    'crushed'
  ];

  static const List<String> tier2Keywords = [
    'injured',
    'broken bone',
    'hospital',
    'medical help',
    'elderly',
    'pregnant',
    'disabled',
    'stranded',
    'flooding',
    'smoke',
    'stuck',
    "can't move",
    'lost child',
    'separated'
  ];

  static const List<String> tier3Keywords = [
    'water',
    'food',
    'shelter',
    'blanket',
    'medicine needed',
    'power out',
    'phone dying',
    'supplies',
    'cold',
    'hungry'
  ];

  /// Triages message content and need category returning score, tier, and explanation.
  static TriageResult triage({
    required String description,
    required String needType,
  }) {
    // Normalize input string: convert to lowercase
    final String combinedInput = '$needType $description'.toLowerCase();

    final List<String> matchedTier1 = [];
    final List<String> matchedTier2 = [];
    final List<String> matchedTier3 = [];

    // Find all matches
    for (final keyword in tier1Keywords) {
      if (combinedInput.contains(keyword)) {
        matchedTier1.add(keyword);
      }
    }

    for (final keyword in tier2Keywords) {
      if (combinedInput.contains(keyword)) {
        matchedTier2.add(keyword);
      }
    }

    for (final keyword in tier3Keywords) {
      if (combinedInput.contains(keyword)) {
        matchedTier3.add(keyword);
      }
    }

    // Determine results based on priority hierarchy
    if (matchedTier1.isNotEmpty) {
      final int score = matchedTier1.length >= 2 ? 10 : 9;
      final String tier = 'Critical';
      final String explanation = matchedTier1.length >= 2
          ? '${matchedTier1.join(" + ")} (Multiple Tier 1 Override) -> CRITICAL'
          : '${matchedTier1.first} -> CRITICAL';
      return TriageResult(
        score: score,
        tier: tier,
        matchedKeywords: matchedTier1,
        explanation: explanation,
      );
    } else if (matchedTier2.isNotEmpty) {
      final String tier = 'Urgent';
      final String explanation = '${matchedTier2.join(" + ")} -> URGENT';
      return TriageResult(
        score: 7, // default score for urgent (6-8 range)
        tier: tier,
        matchedKeywords: matchedTier2,
        explanation: explanation,
      );
    } else if (matchedTier3.isNotEmpty) {
      final String tier = 'Needs';
      final String explanation = '${matchedTier3.join(" + ")} -> NEEDS';
      return TriageResult(
        score: 4, // default score for needs (3-5 range)
        tier: tier,
        matchedKeywords: matchedTier3,
        explanation: explanation,
      );
    } else {
      final String tier = 'Low';
      final String explanation = 'No critical keywords matched -> LOW/UNCLASSIFIED';
      return TriageResult(
        score: 1, // default score for low (1-2 range)
        tier: tier,
        matchedKeywords: const [],
        explanation: explanation,
      );
    }
  }
}
