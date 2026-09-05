import 'dart:convert';
import 'dart:io';

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

  test('no translation value is empty', () {
    final List<String> blank = [
      for (final MapEntry<String, dynamic> entry in translations.entries)
        if ('${entry.value}'.trim().isEmpty) entry.key,
    ];

    expect(blank, isEmpty, reason: 'these keys render as nothing at all');
  });
}
