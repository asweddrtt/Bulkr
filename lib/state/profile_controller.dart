import 'package:flutter/foundation.dart';

import '../models/auth_user.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/nutrition_calculator.dart';
import '../services/profile_storage.dart';

/// Single source of truth for the signed-in athlete. Every mutation persists
/// immediately and notifies listeners, so the router and screens stay in sync.
class ProfileController extends ChangeNotifier {
  final AuthService _auth;
  final ProfileStorage _storage;
  final NutritionCalculator _calculator;

  ProfileController({
    AuthService auth = const LocalAuthService(),
    ProfileStorage storage = const ProfileStorage(),
    NutritionCalculator calculator = const NutritionCalculator(),
  })  : _auth = auth,
        _storage = storage,
        _calculator = calculator;

  UserProfile? _profile;
  bool _isLoaded = false;

  UserProfile? get profile => _profile;

  /// True once the stored profile has been read, so the router can wait.
  bool get isLoaded => _isLoaded;

  bool get isSignedIn => _profile != null;

  bool get isOnboardingComplete => _profile?.onboardingComplete ?? false;

  /// Null until the athlete has logged a weight.
  NutritionPlan? get nutritionPlan {
    final UserProfile? profile = _profile;
    return profile == null ? null : _calculator.planFor(profile);
  }

  Future<void> load() async {
    _profile = await _storage.load();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> signIn(AuthProvider provider, {String? fallbackName}) async {
    final AuthUser user = await _auth.signIn(provider);
    // A returning athlete keeps the profile already stored on the device.
    final UserProfile? stored = _profile ?? await _storage.load();
    if (stored != null && stored.userId == user.id) {
      _profile = stored;
    } else {
      _profile = UserProfile(
        userId: user.id,
        displayName: user.displayName.isNotEmpty
            ? user.displayName
            : (fallbackName ?? 'Athlete'),
        provider: user.provider,
      );
    }
    await _persist();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _storage.clear();
    _profile = null;
    notifyListeners();
  }

  Future<void> saveBaseline({
    required int ageYears,
    required int heightCm,
    required double currentWeightKg,
    required double targetWeightKg,
  }) async {
    final UserProfile? profile = _profile;
    if (profile == null) return;

    _profile = _withWeighIn(
      profile.copyWith(
        ageYears: ageYears,
        heightCm: heightCm,
        targetWeightKg: targetWeightKg,
      ),
      currentWeightKg,
    );
    await _persist();
  }

  Future<void> setActivityLevel(ActivityLevel level) async {
    await _update((profile) => profile.copyWith(activityLevel: level));
  }

  Future<void> setBulkPlan(BulkPlan plan) async {
    await _update((profile) => profile.copyWith(bulkPlan: plan));
  }

  Future<void> setDisplayName(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _update((profile) => profile.copyWith(displayName: trimmed));
  }

  Future<void> setTargetWeight(double kg) async {
    await _update((profile) => profile.copyWith(targetWeightKg: kg));
  }

  /// Records today's weight, replacing an earlier entry from the same day.
  Future<void> logWeighIn(double kg) async {
    await _update((profile) => _withWeighIn(profile, kg));
  }

  Future<void> completeOnboarding() async {
    await _update((profile) => profile.copyWith(onboardingComplete: true));
  }

  UserProfile _withWeighIn(UserProfile profile, double kg) {
    final WeighIn entry = WeighIn(date: DateTime.now(), kg: kg);
    final List<WeighIn> updated = profile.weighIns
        .where((w) => w.day != entry.day)
        .toList()
      ..add(entry);
    updated.sort((a, b) => a.date.compareTo(b.date));
    return profile.copyWith(weighIns: updated);
  }

  Future<void> _update(UserProfile Function(UserProfile profile) change) async {
    final UserProfile? profile = _profile;
    if (profile == null) return;
    _profile = change(profile);
    await _persist();
  }

  Future<void> _persist() async {
    final UserProfile? profile = _profile;
    if (profile != null) await _storage.save(profile);
    notifyListeners();
  }
}
