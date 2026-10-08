import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/src/rust/api/types.dart';

RatingInfo _rating({required int score, required bool isMine}) =>
    RatingInfo(tradeId: 't1', score: score, isMine: isMine, createdAt: 0);

void main() {
  test('the score the user gave is the one shown', () {
    expect(myRatingScore(_rating(score: 4, isMine: true)), 4);
  });

  test('a closed rating step without a known score shows no score', () {
    // Rehydrated from `rated_at` (a restart, a replayed rate-received, a
    // restored trade): Rust carries a placeholder 0, never a real note.
    expect(myRatingScore(_rating(score: 0, isMine: true)), isNull);
  });

  test("the counterpart's rating is not the user's", () {
    expect(myRatingScore(_rating(score: 5, isMine: false)), isNull);
    expect(myRatingScore(null), isNull);
  });
}
