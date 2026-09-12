import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Icon-only controls have to say what they are.
///
/// A `GestureDetector` wrapping nothing but an `Icon` is invisible to
/// VoiceOver and TalkBack: there is no text to read, so it announces as
/// "button" or as nothing at all. Bulkr had thirty of them — the nav bar, the
/// overflow menu on every post and every meal, every close button, every back
/// arrow, the favourite star, the water undo — against five labels in the
/// whole app.
///
/// This is a lint rather than a widget test on purpose. The failure is one of
/// omission: it is not that a screen is wrong, it is that a control was added
/// without a label, and no test of existing screens can catch the next one.
/// Same reasoning as `translation_keys_test.dart` — read the source, because
/// the mistake is invisible at runtime to everybody who can see.
///
/// ## Why it matches parentheses instead of counting lines
///
/// The first version took a fixed window of lines after the gesture. It was
/// wrong in both directions: `Semantics` *wraps* the control so it sits above
/// it, and a labelled button's `Text` often sits inside a `Row` further down
/// than the window reached. It reported two dozen controls that were correctly
/// labelled.
///
/// A test that cries wolf is a test somebody deletes, so this walks the actual
/// argument list and asks about the real subtree.
void main() {
  test('every icon-only tap target carries a semantic label', () {
    final List<String> unlabelled = <String>[];

    for (final File file in _dartFiles()) {
      final String source = file.readAsStringSync();

      for (final RegExpMatch match in _tapTarget.allMatches(source)) {
        final int open = source.indexOf('(', match.start);
        final int close = _matchingParen(source, open);
        if (close == -1) continue;

        final String subtree = source.substring(open, close);

        final bool hasIcon =
            subtree.contains('Icons.') || _iconWidget.hasMatch(subtree);
        if (!hasIcon) continue;

        // A control, not just a gesture. The photo viewer's double-tap-to-zoom
        // is a `GestureDetector` over an image with no `onTap` at all —
        // calling that a button and giving it a label would be describing
        // something that is not there.
        if (!subtree.contains('onTap:')) continue;

        // Anything a screen reader can actually read.
        final bool hasText =
            _textWidget.hasMatch(subtree) || subtree.contains('.tr()');

        // `Semantics` is the parent, so look at what encloses the control as
        // well as what it contains.
        final bool hasSemantics = subtree.contains('Semantics(') ||
            subtree.contains('semanticLabel') ||
            subtree.contains('tooltip:') ||
            _precededBySemantics(source, match.start);

        if (!hasText && !hasSemantics) {
          final int line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          unlabelled.add('${file.path}:$line');
        }
      }
    }

    expect(
      unlabelled,
      isEmpty,
      reason: 'these wrap an Icon in a tap target with nothing for a screen '
          'reader to announce. Wrap them in Semantics(button: true, label: '
          "'a11y_…'.tr()), or give the Icon a semanticLabel",
    );
  });

  group('the lint itself', () {
    // A source-scanning test passes just as happily when its pattern matches
    // nothing, so the pattern is pinned here.
    test('flags an unlabelled icon button', () {
      expect(
        _findUnlabelled('''
          GestureDetector(
            onTap: close,
            child: Icon(Icons.close),
          )
        '''),
        isNotEmpty,
      );
    });

    test('accepts one wrapped in Semantics', () {
      expect(
        _findUnlabelled('''
          Semantics(
            button: true,
            label: 'a11y_close'.tr(),
            child: GestureDetector(
              onTap: close,
              child: Icon(Icons.close),
            ),
          )
        '''),
        isEmpty,
      );
    });

    test('accepts one whose label is text further down a Row', () {
      // The false positive the line-window version produced. A labelled
      // button is labelled however deep the Text happens to sit.
      expect(
        _findUnlabelled('''
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: r),
              child: Row(
                children: [
                  Icon(Icons.add),
                  SizedBox(width: 8),
                  Text(label),
                ],
              ),
            ),
          )
        '''),
        isEmpty,
      );
    });

    test('ignores a tap target with no icon at all', () {
      expect(
        _findUnlabelled('GestureDetector(onTap: x, child: Container())'),
        isEmpty,
      );
    });
  });
}

final RegExp _tapTarget = RegExp(r'\b(?:GestureDetector|InkWell)\(');
final RegExp _iconWidget = RegExp(r'\bIcon\(');
final RegExp _textWidget = RegExp(r'\bText\(');

/// The six lines above [offset], where a wrapping `Semantics` would be.
bool _precededBySemantics(String source, int offset) {
  int start = offset;
  for (int seen = 0; start > 0 && seen < 6; start--) {
    if (source[start - 1] == '\n') seen++;
  }
  return source.substring(start, offset).contains('Semantics(');
}

/// Index of the parenthesis closing the one at [open], skipping string
/// literals and line comments so a `')'` inside either does not end it early.
int _matchingParen(String source, int open) {
  int depth = 0;

  for (int i = open; i < source.length; i++) {
    final String c = source[i];

    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      final int newline = source.indexOf('\n', i);
      if (newline == -1) return -1;
      i = newline;
      continue;
    }

    if (c == "'" || c == '"') {
      i = _endOfString(source, i);
      if (i == -1) return -1;
      continue;
    }

    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }

  return -1;
}

int _endOfString(String source, int start) {
  final String quote = source[start];

  for (int i = start + 1; i < source.length; i++) {
    if (source[i] == r'\') {
      i++;
      continue;
    }
    if (source[i] == quote) return i;
    // Single-quoted Dart strings do not span lines unless tripled, and
    // stopping at the newline keeps a stray apostrophe in a comment from
    // swallowing the rest of the file.
    if (source[i] == '\n') return i;
  }

  return -1;
}

/// The scan, over a snippet, for the lint's own tests.
List<String> _findUnlabelled(String source) {
  final List<String> found = <String>[];

  for (final RegExpMatch match in _tapTarget.allMatches(source)) {
    final int open = source.indexOf('(', match.start);
    final int close = _matchingParen(source, open);
    if (close == -1) continue;

    final String subtree = source.substring(open, close);
    if (!subtree.contains('Icons.') && !_iconWidget.hasMatch(subtree)) continue;
    if (!subtree.contains('onTap:')) continue;

    final bool hasText =
        _textWidget.hasMatch(subtree) || subtree.contains('.tr()');
    final bool hasSemantics = subtree.contains('Semantics(') ||
        subtree.contains('semanticLabel') ||
        subtree.contains('tooltip:') ||
        _precededBySemantics(source, match.start);

    if (!hasText && !hasSemantics) found.add('${match.start}');
  }

  return found;
}

List<File> _dartFiles() {
  final Directory lib = Directory('lib');
  expect(lib.existsSync(), isTrue,
      reason: 'this test reads the source, so it must run from the project '
          'root');

  return lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .toList();
}
