@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards how the production web server lets a browser keep what it serves
/// (`docker/nginx.conf`, shipped by `Dockerfile.web`).
///
/// A Flutter web build writes its files under the same names every time
/// with different contents: the scripts, and the assets too — the icon font
/// is cut down to the icons that build draws. A file a browser may reuse
/// without asking is, after a deploy, the previous build's file under the
/// new build's screens. `/assets/` was kept for a day, and for that day
/// every icon a deploy added came out blank in browsers that had the app
/// open before it: the price control's minus sign, which nothing drew
/// until then.
void main() {
  final conf = File('docker/nginx.conf').readAsStringSync();

  /// The `Cache-Control` each `location` block sends, by its matcher; null
  /// for a block that sends none.
  Map<String, String?> cacheControlByLocation() => {
    for (final block in RegExp(
      r'location\s+([^{]+?)\s*\{([^}]*)\}',
    ).allMatches(conf))
      block.group(1)!: RegExp(
        r'add_header\s+Cache-Control\s+"([^"]*)"',
      ).firstMatch(block.group(2)!)?.group(1),
  };

  test('reads every location of the server', () {
    // The parser found the blocks it is about to judge, the assets' among
    // them: an empty map would pass everything below.
    final locations = cacheControlByLocation();
    expect(locations.keys, contains('/assets/'));
    expect(locations.length, greaterThanOrEqualTo(5));
  });

  test('nothing is reused by a browser without asking the server', () {
    cacheControlByLocation().forEach((location, cacheControl) {
      expect(cacheControl, isNotNull, reason: 'location $location');
      // `no-cache` is "keep it, but ask before using it": unchanged, the
      // answer is a 304 and nothing is transferred.
      expect(cacheControl, contains('no-cache'), reason: 'location $location');
      expect(
        cacheControl,
        isNot(contains('max-age')),
        reason: 'location $location',
      );
    });
  });

  test('the server sends what a browser needs to ask with', () {
    // Revalidation is a conditional request, and needs the validator.
    expect(conf, matches(RegExp(r'^\s*etag on;', multiLine: true)));
  });
}
