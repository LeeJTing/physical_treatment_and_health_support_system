import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/camera_gallery/meal_image_picker.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/plan_change.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/food_recognition_service/food_recognition_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/food_recognition_service/recognition_result.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/i_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/i_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';

/// Where the meal being logged is in UC800.
enum MealStep { idle, recognising, review, saving }

/// Meal capture, recognition, correction and the running daily totals (Table 4.69; UC800 View Food
/// Information, and the verdicts of UC900 BF-4 to BF-7).
class MealLogViewModel extends BaseViewModel {
  final IMealRepository _mealRepo;
  final FoodRecognitionService _recogniser;
  final SuitabilityService _suitability;
  final IFoodRepository _foods;
  final RiskAssessmentService _risk;
  final IAuthRepository _auth;
  final MealImageSource _camera;
  final DateTime Function() _now;

  /// For the "follow your diet plan" alerts: the plan check and the phone's notifications.
  final DietPlannerService? _planner;
  final LocalNotificationService? _alerts;

  MealLogViewModel(
    this._mealRepo,
    this._recogniser,
    this._foods,
    this._risk,
    this._auth,
    this._camera, [
    this._suitability = const SuitabilityService(),
    DateTime Function()? now,
    this._planner,
    this._alerts,
  ]) : _now = now ?? DateTime.now;

  /// The last meal logged was not the planned one (shown on the Diet tab until dismissed).
  PlanAlert? planAlert;

  void dismissPlanAlert() {
    planAlert = null;
    notifyListeners();
  }

  String? _accountId;

  /// UC1000 for the daily targets and the declared conditions (UC800 BF-3, UC900 BF-2).
  DietContext ctx = DietContext(limit: SafetyLimit.mostRestrictive());
  ProfileStatus profileStatus = ProfileStatus.complete;

  /// Today's logged meals, newest first, and their running totals (FR700_013, C9).
  List<MealLog> today = const [];
  Nutrients dailyTotals = Nutrients.zero;

  /// Meal awaiting confirmation (FR700_009).
  MealLog? draft;
  Uint8List? draftImage;

  /// The photo just taken or chosen, shown on the waiting screen while it is checked and identified.
  Uint8List? pendingPhoto;

  /// Each recognition gets a number; a result that arrives after the patient left is ignored.
  int _recognition = 0;

  /// Meal photos by meal id: downloaded for the history, or kept from the camera when saved.
  final Map<String, Uint8List> _photos = {};
  final Set<String> _photoRequests = {};

  /// Meals shown in today's list before the database has confirmed them ("UI first").
  final Set<String> _saving = {};
  RecognitionResult? lastResult;
  MealStep step = MealStep.idle;

  /// Prompt for manual entry (A2 low confidence, E1 service down).
  bool manualEntryPrompt = false;

  /// One-off message for a SnackBar or the review screen.
  String? _message;
  String? takeMessage() {
    final m = _message;
    _message = null;
    return m;
  }

  String? get messagePeek => _message;

  /// Allowance left for the day (FR700_039).
  Nutrients get remaining => ctx.remaining(dailyTotals);

  /// UC900 A1: every logged item today is Suitable.
  bool get allTodaySuitable =>
      today.isNotEmpty && today.every((m) => m.worstVerdict() == Verdict.suitable);

  Future<void> load() async {
    _accountId ??= (await _auth.currentAccount()).dataOrNull?.accountId;
    final snap = await _risk.retrieve();
    if (snap case Success(:final data)) {
      ctx = DietContext.from(data);
      profileStatus = data.status;
      if (data.status == ProfileStatus.error) _message = Messages.dietProfileUnavailable; // E1 M4
    } else {
      ctx = DietContext(limit: SafetyLimit.mostRestrictive(), failSafe: true);
      profileStatus = ProfileStatus.error;
    }
    await _loadToday();
    await _checkPlan();
  }

  /// Checks today against the diet plan in force: a meal just logged that is not the planned one
  /// raises an alert (in the app, on the phone and in the notification history), and the planned
  /// meals not logged yet get their "follow your diet plan" alert at their time. Without a plan,
  /// nothing happens; a failure never stops the meal from being logged.
  Future<void> _checkPlan([MealLog? justLogged]) async {
    final planner = _planner;
    final id = _accountId;
    if (planner == null || id == null) return;
    try {
      final n = _now();
      final day = DateTime(n.year, n.month, n.day);
      final plan =
          (await _mealRepo.planFor(id, PlanType.daily, day)).dataOrNull ??
          (await _mealRepo.planFor(id, PlanType.weekly, day)).dataOrNull;
      if (plan == null) return;
      final todays = today.where((m) => m.consumedAt.year == n.year && m.consumedAt.month == n.month && m.consumedAt.day == n.day).toList();
      if (justLogged != null) {
        final a = planner.offPlanAlertFor(justLogged, plan, ctx, todays, n);
        if (a != null) {
          planAlert = a;
          notifyListeners();
          await _alerts?.planAlert(id, a);
        }
      }
      await _alerts?.schedulePlanAlerts(planner.missedMealAlerts(plan, todays, n));
    } catch (_) {
      // The plan check is a help, not part of logging the meal.
    }
  }

  Future<void> _loadToday() async {
    final id = _accountId;
    if (id == null) return;
    final n = _now();
    final start = DateTime(n.year, n.month, n.day);
    final end = DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
    final res = await _mealRepo.findMeals(id, start, end);
    final stored = res.dataOrNull;
    if (stored != null) {
      // A meal still being saved stays on the list until the database has it.
      final ids = {for (final m in stored) m.mealId};
      final waiting = today.where((m) => _saving.contains(m.mealId) && !ids.contains(m.mealId));
      // Stored verdicts are re-derived so the reasons and alternatives match the current profile.
      today = [
        ...waiting,
        for (final m in stored) m.copyWith(items: [for (final i in m.items) _judge(i)]),
      ];
    }
    _retotal();
    notifyListeners();
  }

  MealItem _judge(MealItem i) => i.withVerdicts(_suitability.assess(i, ctx));

  // ------------------------------------------------------------- capture and recognition

  /// Takes a photograph of the meal (FR700_001).
  Future<void> captureImage() async {
    final bytes = await pickPhoto(camera: true);
    if (bytes != null) await recognise(bytes);
  }

  /// Selects an existing image (FR700_002).
  Future<void> pickFromGallery() async {
    final bytes = await pickPhoto(camera: false);
    if (bytes != null) await recognise(bytes);
  }

  /// Opens the camera or the gallery and returns the photo, or null when the patient cancelled
  /// (A7, nothing kept) or the camera was refused (A6, with a message). The Diet screen then opens
  /// the waiting screen at once and calls [recognise].
  Future<Uint8List?> pickPhoto({required bool camera}) async {
    try {
      return await (camera ? _camera.capture() : _camera.pickFromGallery());
    } on PlatformException catch (_) {
      _message = Messages.cameraPermissionRequired; // A6 M4
      notifyListeners();
      return null;
    } catch (_) {
      _message = Messages.invalidImage;
      notifyListeners();
      return null;
    }
  }

  /// Identifies the items, or prompts manual entry below 60 % (FR700_003, FR700_005).
  Future<void> recognise(Uint8List original) async {
    final run = ++_recognition;
    step = MealStep.recognising;
    manualEntryPrompt = false;
    pendingPhoto = original;
    draft = null;
    notifyListeners();
    final prepared = await _recogniser.prepare(original);
    if (run != _recognition) return; // the patient left the waiting screen
    if (prepared case Failure(:final message)) {
      step = MealStep.idle;
      pendingPhoto = null;
      _message = message; // A1 M1
      notifyListeners();
      return;
    }
    final img = prepared.dataOrNull!;
    draftImage = img.upload;
    notifyListeners(); // the reduced photo replaces the original on the waiting screen
    final res = await _recogniser.recognise(
      img,
      ctx.conditionCodes,
      restrictionCodes: ctx.restrictionCodes,
      limitationCodes: ctx.limitationCodes,
    );
    if (run != _recognition) return;
    final now = _now();
    if (res case Failure(:final message)) {
      // E1: recognition unavailable, manual entry instead (FR700_050).
      lastResult = null;
      draft = _newDraft(EntryMethod.manual, now);
      manualEntryPrompt = true;
      _message = message;
      step = MealStep.review;
      notifyListeners();
      return;
    }
    final r = res.dataOrNull!;
    lastResult = r;
    draft = MealLog(
      mealId: newId(),
      accountId: _accountId ?? '',
      mealType: MealSlot.forTime(now),
      entryMethod: EntryMethod.recognition,
      recognitionConfidence: r.confidence,
      modelVersion: r.modelVersion, // FR700_008
      consumedAt: now,
      items: r.needsManualEntry
          ? const []
          : [
              for (final it in r.items)
                _judge(
                  MealItem.of(
                    it.food,
                    confidence: it.confidence,
                    candidateKeys: it.candidates.map((c) => c.foodKey).toList(),
                  ),
                ),
            ],
    );
    if (r.needsManualEntry) {
      manualEntryPrompt = true;
      _message = Messages.lowConfidence; // A2 M2
    }
    step = MealStep.review;
    notifyListeners();
  }

  MealLog _newDraft(EntryMethod m, DateTime now) => MealLog(
    mealId: newId(),
    accountId: _accountId ?? '',
    mealType: MealSlot.forTime(now),
    entryMethod: m,
    consumedAt: now,
  );

  /// Manual entry without a photo, also while the recognition service is down (FR700_050).
  void startManual() {
    _recognition++;
    draftImage = null;
    pendingPhoto = null;
    lastResult = null;
    draft = _newDraft(EntryMethod.manual, _now());
    manualEntryPrompt = false;
    step = MealStep.review;
    notifyListeners();
  }

  /// Stops waiting for the recogniser and lets the patient enter the foods; the photo already
  /// checked is kept with the meal (FR700_050).
  void enterManually() {
    _recognition++;
    lastResult = null;
    pendingPhoto = null;
    draft = _newDraft(EntryMethod.manual, _now());
    manualEntryPrompt = false;
    step = MealStep.review;
    notifyListeners();
  }

  /// The other foods the recogniser thought likely, for a one-tap correction.
  Future<List<FoodItem>> candidatesFor(MealItem i) async {
    final out = <FoodItem>[];
    for (final k in i.candidateKeys) {
      final f = (await _foods.byKey(k)).dataOrNull;
      if (f != null) out.add(f);
    }
    return out;
  }

  Future<List<FoodItem>> searchFoods(String term) async =>
      (await _foods.search(term)).dataOrNull ?? const [];

  /// Adds a food chosen by search (A2 step 2, manual entry).
  void addFood(FoodItem f, {double? grams}) {
    final d = draft;
    if (d == null) return;
    draft = d.addItem(_judge(MealItem.of(f, grams: grams)));
    manualEntryPrompt = false;
    notifyListeners();
  }

  /// Replaces a misidentified food (FR700_006, A3); nutrients are re-estimated (FR700_010).
  void correctItem(MealItem i, FoodItem f) {
    final d = draft;
    if (d == null) return;
    draft = d.copyWith(
      items: [
        for (final x in d.items)
          x.mealItemId == i.mealItemId ? _judge(MealItem.of(f, corrected: true)) : x,
      ],
    );
    notifyListeners();
  }

  /// Rescales the nutrients to a new portion (FR700_007, FR700_011, A4 M3).
  void adjustPortion(MealItem i, double grams) {
    final d = draft;
    if (d == null || grams <= 0) return;
    draft = d.copyWith(
      items: [for (final x in d.items) x.mealItemId == i.mealItemId ? _judge(x.scaleTo(grams)) : x],
    );
    _message = Messages.portionUpdated;
    notifyListeners();
  }

  void removeItem(MealItem i) {
    final d = draft;
    if (d == null) return;
    draft = d.removeItem(i);
    notifyListeners();
  }

  void setSlot(MealSlot s) {
    final d = draft;
    if (d == null) return;
    draft = d.copyWith(mealType: s);
    notifyListeners();
  }

  /// Alternatives for a flagged item, closest first (C3; FR700_020, FR700_027).
  Future<List<FoodItem>> alternativesFor(MealItem i) async {
    final same = (await _foods.alternativesTo(i.food, ctx.restrictionCodes)).dataOrNull ?? const [];
    return _suitability.rankAlternatives(i, same, ctx).take(3).toList();
  }

  /// Stores the meal, the image and the verdicts (FR700_009, FR700_012), then the running totals
  /// (FR700_013). The photo is kept whenever the meal started from one, also when the patient then
  /// entered or corrected the foods by hand. UI first: the meal appears in today's list, marked as
  /// saving, before the database answers; on a failure it is taken out again and the draft is kept
  /// so the patient may retry (E2, M8).
  Future<bool> confirmMeal() async {
    final d = draft;
    if (d == null || d.items.isEmpty) {
      _message = Messages.emptyField;
      notifyListeners();
      return false;
    }
    step = MealStep.saving;
    final image = draftImage;
    final meal = d.copyWith(accountId: _accountId);
    _saving.add(meal.mealId);
    if (image != null) _photos[meal.mealId] = image;
    today = [meal, ...today.where((m) => m.mealId != meal.mealId)];
    _retotal();
    notifyListeners();
    final res = await _mealRepo.saveMeal(meal, image: image);
    _saving.remove(meal.mealId);
    if (res is Failure) {
      today = today.where((m) => m.mealId != meal.mealId).toList();
      _photos.remove(meal.mealId);
      _retotal();
      step = MealStep.review;
      _message = Messages.mealSaveFailed;
      notifyListeners();
      return false;
    }
    draft = null;
    draftImage = null;
    pendingPhoto = null;
    lastResult = null;
    step = MealStep.idle;
    _message = Messages.mealLogged; // M5
    await _loadToday();
    await _checkPlan(meal);
    return true;
  }

  /// Discards the unsaved image and the draft (A7).
  void cancel() {
    _recognition++;
    draft = null;
    draftImage = null;
    pendingPhoto = null;
    lastResult = null;
    manualEntryPrompt = false;
    step = MealStep.idle;
    notifyListeners();
  }

  void _retotal() => dailyTotals = Nutrients.sum(today.map((m) => m.totals)).rounded(); // C9

  /// True while a meal shown in today's list is still being saved.
  bool isSaving(MealLog m) => _saving.contains(m.mealId);

  /// Whether the meal has a photo (stored, or still being saved).
  bool hasPhoto(MealLog m) => _photos.containsKey(m.mealId) || (m.imageUri?.isNotEmpty ?? false);

  /// The meal's photo when it is already on the phone, otherwise null (see [fetchPhoto]).
  Uint8List? photoOf(MealLog m) => _photos[m.mealId];

  /// Downloads the stored photo of a meal once; the screen redraws when it has arrived. A failure
  /// leaves the placeholder, and the photo is asked for again the next time the meal is shown.
  Future<void> fetchPhoto(MealLog m) async {
    final uri = m.imageUri;
    if (uri == null || uri.isEmpty || _photos.containsKey(m.mealId)) return;
    if (!_photoRequests.add(m.mealId)) return;
    final res = await _mealRepo.mealPhoto(uri);
    _photoRequests.remove(m.mealId);
    if (res case Success(:final data)) {
      _photos[m.mealId] = data;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- history

  List<MealLog> history = const [];
  DateTime historyFrom = DateTime.now().subtract(const Duration(days: 6));
  DateTime historyTo = DateTime.now();

  /// Dietary history filtered by a date range (FR700_014, A5).
  Future<bool> loadHistory(DateTime from, DateTime to) async {
    if (from.isAfter(to)) {
      _message = Messages.invalidDateRange;
      notifyListeners();
      return false;
    }
    final id = _accountId;
    if (id == null) return false;
    historyFrom = DateTime(from.year, from.month, from.day);
    historyTo = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
    setLoading(true);
    final res = await _mealRepo.findMeals(id, historyFrom, historyTo);
    history = [
      for (final m in res.dataOrNull ?? const <MealLog>[])
        m.copyWith(items: [for (final i in m.items) _judge(i)]),
    ];
    if (res is Failure) _message = Messages.historyRetrievalFailed;
    setLoading(false);
    return res.isSuccess;
  }

  /// Removes the meal and its image (FR700_015, FR700_016), then the totals (FR700_013). UI first:
  /// the meal leaves the lists at once and comes back if the database could not delete it.
  Future<bool> deleteMeal(MealLog m) async {
    final keptHistory = history;
    final keptToday = today;
    history = history.where((x) => x.mealId != m.mealId).toList();
    today = today.where((x) => x.mealId != m.mealId).toList();
    _retotal();
    notifyListeners();
    final res = await _mealRepo.deleteMeal(m);
    if (res is Failure) {
      history = keptHistory;
      today = keptToday;
      _retotal();
      _message = Messages.deletionFailed;
      notifyListeners();
      return false;
    }
    _photos.remove(m.mealId);
    await _loadToday();
    return true;
  }
}
