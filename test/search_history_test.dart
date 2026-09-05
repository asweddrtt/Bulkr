import 'package:bulkr/data/app_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = AppPreferences(preferences: await SharedPreferences.getInstance());
  });

  test('starts empty', () async {
    expect(await prefs.searchHistory(), isEmpty);
  });

  test('newest first', () async {
    await prefs.rememberSearch('sara');
    await prefs.rememberSearch('omar');

    expect(await prefs.searchHistory(), ['omar', 'sara']);
  });

  test('searching the same term again moves it rather than duplicating', () async {
    await prefs.rememberSearch('sara');
    await prefs.rememberSearch('omar');
    await prefs.rememberSearch('sara');

    expect(await prefs.searchHistory(), ['sara', 'omar']);
  });

  test('matching is case-insensitive, and the new casing wins', () async {
    // Typing "Sara" after "sara" is the same search, not a second one.
    await prefs.rememberSearch('sara');
    await prefs.rememberSearch('Sara');

    expect(await prefs.searchHistory(), ['Sara']);
  });

  test('terms are trimmed, and blank ones are not recorded', () async {
    await prefs.rememberSearch('  sara  ');
    await prefs.rememberSearch('   ');
    await prefs.rememberSearch('');

    expect(await prefs.searchHistory(), ['sara']);
  });

  test('the list is capped, dropping the oldest', () async {
    for (int i = 0; i < AppPreferences.maxSearchHistory + 3; i++) {
      await prefs.rememberSearch('term$i');
    }

    final List<String> history = await prefs.searchHistory();
    expect(history, hasLength(AppPreferences.maxSearchHistory));
    expect(history.first, 'term${AppPreferences.maxSearchHistory + 2}');
    expect(history, isNot(contains('term0')));
  });

  test('forgetting one leaves the rest', () async {
    await prefs.rememberSearch('sara');
    await prefs.rememberSearch('omar');

    expect(await prefs.forgetSearch('sara'), ['omar']);
    expect(await prefs.searchHistory(), ['omar']);
  });

  test('clearing removes everything', () async {
    await prefs.rememberSearch('sara');
    await prefs.clearSearchHistory();

    expect(await prefs.searchHistory(), isEmpty);
  });

  test('signing out takes the history with it', () async {
    // The next person to sign in on this device should not be looking at what
    // the last one searched for.
    await prefs.setCompletedOnboarding('u1');
    await prefs.rememberSearch('sara');

    await prefs.clear();

    expect(await prefs.searchHistory(), isEmpty);
    expect(await prefs.hasCompletedOnboarding('u1'), isFalse);
  });
}
