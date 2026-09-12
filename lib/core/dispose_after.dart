import 'package:flutter/foundation.dart';

/// Ties a disposable's lifetime to the future of the thing that is using it.
///
/// Written for dialogs. A `TextEditingController` built inside a `State` has
/// `dispose` to live in; one built inside a plain function that calls
/// `showDialog` has nowhere, so it is usually just dropped — and a
/// `ChangeNotifier` that is dropped keeps its listeners, and its listeners keep
/// whatever they close over, for as long as the process runs. Dialogs are
/// opened over and over, so it accumulates.
///
/// `whenComplete` rather than `then`: a dialog dismissed by tapping outside
/// completes with null and must still clean up, and one that throws must not
/// leak on the way out.
extension DisposeAfter<T> on Future<T> {
  /// Disposes [disposable] once this future settles, and passes the result
  /// through untouched.
  ///
  ///     return showDialog<double>(...).disposing(controller);
  Future<T> disposing(ChangeNotifier disposable) =>
      whenComplete(disposable.dispose);
}
