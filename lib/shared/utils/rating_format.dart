import 'package:intl/intl.dart';

/// The formatter for a reputation rating, for [locale]: the node's average to
/// two decimals, no trailing zeros (`4.97`, `4.9`, `5`; `4,97` in Spanish).
///
/// Every screen that shows a rating goes through this or [formatRating]
/// (DS-L10N-5). Rounded to one decimal, the Account card once showed `5,0`
/// for a user the order book showed at `4,97`.
NumberFormat ratingFormat(String locale) => NumberFormat('0.##', locale);

/// [rating] as every screen shows it: see [ratingFormat].
String formatRating(double rating, String locale) =>
    ratingFormat(locale).format(rating);
