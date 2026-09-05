import 'dart:typed_data';

import 'package:bulkr/cubit/meal_editor/meal_editor_cubit.dart';
import 'package:bulkr/models/meal_draft.dart';
import 'package:bulkr/models/visibility.dart';
import 'package:flutter_test/flutter_test.dart';

/// Leaving a half-written meal should ask; leaving one you only looked at
/// should not. The difference is the baseline, and getting it backwards
/// produces either a confirmation nobody reads or silent data loss.
void main() {
  group('MealEditorState.hasUnsavedWork', () {
    test('a freshly opened new meal has nothing to lose', () {
      const MealEditorState state = MealEditorState(
        draft: MealDraft(visibility: ContentVisibility.private),
        baseline: MealDraft(visibility: ContentVisibility.private),
      );

      expect(state.hasUnsavedWork, isFalse);
    });

    test('typing a title is work', () {
      const MealEditorState state = MealEditorState(
        draft: MealDraft(title: 'Chicken and rice'),
        baseline: MealDraft(),
      );

      expect(state.hasUnsavedWork, isTrue);
    });

    // A meal opened for editing starts full, so "the draft has content" is not
    // the question — "has it moved" is.
    test('an untouched edit has nothing to lose', () {
      const MealDraft stored = MealDraft(title: 'Chicken and rice');
      const MealEditorState state =
          MealEditorState(draft: stored, baseline: stored);

      expect(state.hasUnsavedWork, isFalse);
    });

    test('changing an edit is work', () {
      const MealDraft stored = MealDraft(title: 'Chicken and rice');
      final MealEditorState state = MealEditorState(
        draft: stored.copyWith(title: 'Chicken and potatoes'),
        baseline: stored,
      );

      expect(state.hasUnsavedWork, isTrue);
    });

    // The one edit that leaves every field alone.
    test('a picked photo is work on its own', () {
      final MealEditorState state = MealEditorState(
        draft: const MealDraft(),
        baseline: const MealDraft(),
        imageBytes: Uint8List.fromList(const [1, 2, 3]),
      );

      expect(state.hasUnsavedWork, isTrue);
    });
  });
}
