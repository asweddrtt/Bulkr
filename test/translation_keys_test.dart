import 'dart:convert';
import 'dart:io';

import 'package:bulkr/models/app_notification.dart';
import 'package:bulkr/models/meal_slot.dart';
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
}
