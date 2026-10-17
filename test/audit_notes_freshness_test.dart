import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ensures docs/grokbot/audit_input/notes.md documents a HEAD that is
/// still an ancestor of (or equal to) the current git HEAD.
///
/// G25.2: notes.md is hand-written, so flutter test can catch a notes
/// file that was never updated after a later commit.
void main() {
  test('notes.md HEAD is ancestor of or equal to current HEAD', () {
    final notes = File('docs/grokbot/audit_input/notes.md');
    expect(notes.existsSync(), isTrue, reason: 'notes.md must exist');

    final text = notes.readAsStringSync();
    final match = RegExp(
      r'HEAD:\s*`([0-9a-f]{40})`',
      caseSensitive: false,
    ).firstMatch(text);
    expect(
      match,
      isNotNull,
      reason: 'notes.md must contain HEAD: `<40-hex>`',
    );
    final noted = match!.group(1)!;

    final headResult = Process.runSync('git', ['rev-parse', 'HEAD']);
    expect(headResult.exitCode, 0, reason: headResult.stderr.toString());
    final live = (headResult.stdout as String).trim();

    if (noted == live) {
      return; // equal is fine
    }

    final anc = Process.runSync('git', [
      'merge-base',
      '--is-ancestor',
      noted,
      'HEAD',
    ]);
    expect(
      anc.exitCode,
      0,
      reason:
          'notes.md HEAD `$noted` must be ancestor of or equal to '
          'current HEAD `$live` (merge-base --is-ancestor exit ${anc.exitCode})',
    );
  });
}
