import 'package:flutter/widgets.dart';

import 'profile_controller.dart';

/// Exposes the [ProfileController] to the widget tree and rebuilds dependents
/// whenever the signed-in athlete's data changes.
class ProfileScope extends InheritedNotifier<ProfileController> {
  const ProfileScope({
    super.key,
    required ProfileController controller,
    required super.child,
  }) : super(notifier: controller);

  static ProfileController of(BuildContext context) {
    final ProfileScope? scope =
        context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    assert(scope != null, 'No ProfileScope found in the widget tree');
    return scope!.notifier!;
  }

  /// Reads the controller without subscribing to changes, for callbacks.
  static ProfileController read(BuildContext context) {
    final ProfileScope? scope =
        context.getInheritedWidgetOfExactType<ProfileScope>();
    assert(scope != null, 'No ProfileScope found in the widget tree');
    return scope!.notifier!;
  }
}
