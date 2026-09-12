import 'dart:convert';
import 'dart:io';

import 'package:bulkr/models/app_notification.dart';
import 'package:bulkr/models/meal_slot.dart';
import 'package:bulkr/models/post_label.dart';
import 'package:bulkr/models/post_report.dart';
import 'package:bulkr/screens/main_screen.dart';
import 'package:bulkr/widgets/bulkr_nav_bar.dart';
import 'package:flutter_test/flutter_test.dart';

/// The translation file is the app's only source of user-facing words, and
/// easy_localization's failure mode is silent: `'nav_feed'.tr()` with no such
/// key renders the string `nav_feed`. A key that happens to *be* the English
/// word therefore looks perfect in English and is untranslated everywhere
/// else, which is exactly the bug this file exists to catch — four of the five
/// nav labels were 'Dashboard', 'Meals', 'Feed' and 'Tracker'.
void main() {
  late Map<String, dynamic> translations;

  setUpAll(() {
    final File file = File('assets/translations/en-US.json');
    expect(file.existsSync(), isTrue,
        reason: 'the translation file has moved');
    translations = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  test('every nav label is a real translation key', () {
    for (final NavDestination destination in MainScreen.destinations) {
      expect(
        translations.containsKey(destination.labelKey),
        isTrue,
        reason: '"${destination.labelKey}" is not in en-US.json, so the nav '
            'bar would render the key itself',
      );
    }
  });

  test('the nav labels are keys rather than the words themselves', () {
    for (final NavDestination destination in MainScreen.destinations) {
      final String value = '${translations[destination.labelKey]}';
      expect(
        destination.labelKey,
        isNot(equalsIgnoringCase(value)),
        reason: 'a key equal to its own English value is what a missing key '
            'looks like in English',
      );
    }
  });

  // Same class of bug as the nav labels, in the two other places where a
  // translation key is carried on an enum rather than written at the call site
  // — so nothing in `lib/` mentions the string and no search for it finds the
  // gap.
  test('every notification kind has a real message key', () {
    for (final NotificationKind kind in NotificationKind.values) {
      expect(
        translations.containsKey(kind.messageKey),
        isTrue,
        reason: '"${kind.messageKey}" is not in en-US.json',
      );
      expect(
        '${translations[kind.messageKey]}',
        contains('{name}'),
        reason: 'every one of these sentences names who did it',
      );
    }
  });

  test('every meal slot has a real label key', () {
    for (final MealSlot slot in MealSlot.values) {
      expect(
        translations.containsKey(slot.labelKey),
        isTrue,
        reason: '"${slot.labelKey}" is not in en-US.json',
      );
    }
  });

  test('no translation value is empty', () {
    final List<String> blank = [
      for (final MapEntry<String, dynamic> entry in translations.entries)
        if ('${entry.value}'.trim().isEmpty) entry.key,
    ];

    expect(blank, isEmpty, reason: 'these keys render as nothing at all');
  });

  // --- The two directions -----------------------------------------------
  //
  // The tests above check the handful of keys carried on an enum, because
  // nothing in `lib/` mentions those strings and no search finds the gap. The
  // two below check every other key, in both directions at once:
  //
  //   a key used but not defined  renders as the key itself, in every language
  //   a key defined but not used  is a string a translator will be paid for
  //
  // Both are read off the source rather than the running app, because the
  // failure is silent at runtime and there is no screen that reports it.

  test('every key used in lib/ is defined in en-US.json', () {
    final Map<String, String> firstUse = _literalTrKeys();
    final List<String> missing = [
      for (final MapEntry<String, String> use in firstUse.entries)
        if (!translations.containsKey(use.key)) '${use.key}  (${use.value})',
    ];

    expect(
      missing,
      isEmpty,
      reason: 'these are written as \'key\'.tr() in lib/ but have no entry in '
          'en-US.json, so they render as the key itself',
    );
  });

  test('every key defined in en-US.json is used somewhere', () {
    final String source = _libSource();

    // Keys built by interpolation — `'post_label_$column'` — never appear in
    // the source as a whole string, so they are derived from the enums that
    // build them rather than allow-listed by hand. An allow-list would go
    // stale the moment a label is added; this cannot.
    final Set<String> derived = <String>{
      for (final PostLabel label in PostLabel.values) ...[
        label.labelKey,
        label.promptKey,
      ],
      for (final PostReportReason reason in PostReportReason.values) ...[
        reason.labelKey,
        reason.helperKey,
      ],
    };

    // Any quoted occurrence counts, not just `.tr()`: several keys are passed
    // as named arguments — `titleKey: 'insight_protein_title'` — and are used
    // exactly as much as the ones that are called directly.
    final List<String> unused = [
      for (final String key in translations.keys)
        if (!derived.contains(key) && !source.contains("'$key'")) key,
    ];

    expect(
      unused,
      isEmpty,
      reason: 'nothing in lib/ refers to these keys. Delete them, or find the '
          'call site that was meant to use them',
    );
  });
}

/// Every `'some_key'.tr()` written literally in `lib/`, mapped to where the
/// first one was found so a failure names a file instead of just a key.
Map<String, String> _literalTrKeys() {
  final RegExp call = RegExp(r"'([A-Za-z0-9_]+)'\.tr\(");
  final Map<String, String> found = <String, String>{};

  for (final File file in _libFiles()) {
    final List<String> lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      for (final RegExpMatch match in call.allMatches(lines[i])) {
        found.putIfAbsent(match.group(1)!, () => '${file.path}:${i + 1}');
      }
    }
  }

  return found;
}

String _libSource() =>
    _libFiles().map((File file) => file.readAsStringSync()).join('\n');

List<File> _libFiles() {
  final Directory lib = Directory('lib');
  expect(lib.existsSync(), isTrue,
      reason: 'these tests read the source, so they must run from the project '
          'root');

  return lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .toList();
}
