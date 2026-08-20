import 'package:bulkr/models/auth_user.dart';
import 'package:bulkr/models/user_profile.dart';
import 'package:bulkr/services/nutrition_calculator.dart';
import 'package:bulkr/services/profile_storage.dart';
import 'package:bulkr/state/profile_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NutritionCalculator', () {
    test('derives the daily goal from baseline, activity and surplus', () {
      const UserProfile profile = UserProfile(
        userId: 'u1',
        displayName: 'Athlete',
        provider: AuthProvider.google,
        ageYears: 28,
        heightCm: 180,
        activityLevel: ActivityLevel.moderatelyActive,
        bulkPlan: BulkPlan.standard,
      );
      final UserProfile withWeight = profile.copyWith(
        weighIns: [WeighIn(date: DateTime(2026, 1, 1), kg: 85)],
      );

      final NutritionPlan? plan = const NutritionCalculator().planFor(withWeight);

      // Mifflin-St Jeor: 10*85 + 6.25*180 - 5*28 - 78 = 1757 kcal
      expect(plan!.bmrKcal, 1757);
      expect(plan.maintenanceKcal, 2720); // 1757 * 1.55, to the nearest 10
      expect(plan.dailyGoalKcal, 3220); // + 500 standard bulk surplus
    });

    test('a heavier surplus raises the goal by its own margin', () {
      final UserProfile lean = UserProfile(
        userId: 'u1',
        displayName: 'Athlete',
        provider: AuthProvider.google,
        bulkPlan: BulkPlan.lean,
        weighIns: [WeighIn(date: DateTime(2026, 1, 1), kg: 85)],
      );

      final int leanGoal = const NutritionCalculator().planFor(lean)!.dailyGoalKcal;
      final int aggressiveGoal = const NutritionCalculator()
          .planFor(lean.copyWith(bulkPlan: BulkPlan.aggressive))!
          .dailyGoalKcal;

      expect(aggressiveGoal - leanGoal, 400);
    });

    test('has nothing to calculate from before the first weigh-in', () {
      const UserProfile profile = UserProfile(
        userId: 'u1',
        displayName: 'Athlete',
        provider: AuthProvider.google,
      );

      expect(const NutritionCalculator().planFor(profile), isNull);
    });
  });

  group('ProfileController', () {
    test('signing in seeds a profile and onboarding starts incomplete', () async {
      final ProfileController controller = ProfileController();

      await controller.signIn(AuthProvider.google, fallbackName: 'Athlete');

      expect(controller.isSignedIn, isTrue);
      expect(controller.profile!.provider, AuthProvider.google);
      expect(controller.profile!.displayName, 'Athlete');
      expect(controller.isOnboardingComplete, isFalse);
      expect(controller.nutritionPlan, isNull);
    });

    test('the baseline is stored and logged as the first weigh-in', () async {
      final ProfileController controller = ProfileController();
      await controller.signIn(AuthProvider.apple);

      await controller.saveBaseline(
        ageYears: 31,
        heightCm: 182,
        currentWeightKg: 88.5,
        targetWeightKg: 95,
      );

      final UserProfile profile = controller.profile!;
      expect(profile.ageYears, 31);
      expect(profile.heightCm, 182);
      expect(profile.currentWeightKg, 88.5);
      expect(profile.targetWeightKg, 95);
      expect(profile.weighIns, hasLength(1));
      expect(profile.remainingKg, closeTo(6.5, 0.001));
      expect(controller.nutritionPlan, isNotNull);
    });

    test('a second weigh-in on the same day replaces the first', () async {
      final ProfileController controller = ProfileController();
      await controller.signIn(AuthProvider.email);
      await controller.saveBaseline(
        ageYears: 28,
        heightCm: 180,
        currentWeightKg: 85,
        targetWeightKg: 95,
      );

      await controller.logWeighIn(86.4);

      expect(controller.profile!.weighIns, hasLength(1));
      expect(controller.profile!.currentWeightKg, 86.4);
    });

    test('logging a weight moves the calorie goal with it', () async {
      final ProfileController controller = ProfileController();
      await controller.signIn(AuthProvider.email);
      await controller.saveBaseline(
        ageYears: 28,
        heightCm: 180,
        currentWeightKg: 85,
        targetWeightKg: 95,
      );
      final int before = controller.nutritionPlan!.dailyGoalKcal;

      await controller.logWeighIn(90);

      expect(controller.nutritionPlan!.dailyGoalKcal, greaterThan(before));
    });

    test('the profile survives a restart', () async {
      final ProfileController first = ProfileController();
      await first.signIn(AuthProvider.google, fallbackName: 'Max Gains');
      await first.saveBaseline(
        ageYears: 28,
        heightCm: 180,
        currentWeightKg: 85,
        targetWeightKg: 95,
      );
      await first.setActivityLevel(ActivityLevel.veryActive);
      await first.setBulkPlan(BulkPlan.aggressive);
      await first.completeOnboarding();

      final ProfileController restarted = ProfileController();
      await restarted.load();

      final UserProfile profile = restarted.profile!;
      expect(profile.displayName, 'Max Gains');
      expect(profile.activityLevel, ActivityLevel.veryActive);
      expect(profile.bulkPlan, BulkPlan.aggressive);
      expect(profile.currentWeightKg, 85);
      expect(restarted.isOnboardingComplete, isTrue);
      expect(
        restarted.nutritionPlan!.dailyGoalKcal,
        first.nutritionPlan!.dailyGoalKcal,
      );
    });

    test('signing out clears the stored profile', () async {
      final ProfileController controller = ProfileController();
      await controller.signIn(AuthProvider.google);
      await controller.saveBaseline(
        ageYears: 28,
        heightCm: 180,
        currentWeightKg: 85,
        targetWeightKg: 95,
      );

      await controller.signOut();

      expect(controller.isSignedIn, isFalse);
      expect(await const ProfileStorage().load(), isNull);
    });
  });

  group('UserProfile', () {
    test('reports the trend across the progress window', () {
      final DateTime now = DateTime.now();
      final UserProfile profile = UserProfile(
        userId: 'u1',
        displayName: 'Athlete',
        provider: AuthProvider.google,
        weighIns: [
          WeighIn(date: now.subtract(const Duration(days: 28)), kg: 84.3),
          WeighIn(date: now.subtract(const Duration(days: 14)), kg: 86.1),
          WeighIn(date: now, kg: 88.5),
        ],
      );

      expect(profile.weightDelta(30), closeTo(4.2, 0.001));
      expect(profile.recentWeighIns(30), hasLength(3));
      // Only points inside the window count towards the trend.
      expect(profile.recentWeighIns(20), hasLength(2));
    });

    test('has no trend to report from a single weigh-in', () {
      final UserProfile profile = UserProfile(
        userId: 'u1',
        displayName: 'Athlete',
        provider: AuthProvider.google,
        weighIns: [WeighIn(date: DateTime.now(), kg: 85)],
      );

      expect(profile.weightDelta(30), isNull);
    });
  });
}
