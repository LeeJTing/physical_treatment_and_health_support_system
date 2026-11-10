import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/food_recognition_service/recognition_result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_recognition_details.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/i_food_repository.dart';

/// A meal photo checked against UC800 C3 and reduced for upload (C4).
class PreparedImage {
  /// JPEG, 1024 px on the long edge, quality 80: what is uploaded and, once confirmed, stored.
  final Uint8List upload;
  final int width;
  final int height;

  const PreparedImage(this.upload, this.width, this.height);
}

/// Sends a meal photo to /recognise and maps the labels onto catalogue foods (Table 4.94).
/// Only the photo and the declared condition codes leave the phone (FR700_046); the request
/// carries the session token (FR700_047) and is abandoned after 30 s (FR700_048).
class FoodRecognitionService {
  final ApiClient _api;
  final IFoodRepository _foods;

  /// Below this the patient is prompted for manual entry (FR700_005).
  final double confidenceFloor = AppConstants.recognitionConfidenceFloor;

  /// Version of the model of the last result (FR700_008).
  String modelVersion = '';

  FoodRecognitionService(this._api, this._foods);

  /// Checks the photo (JPEG or PNG, at most 10 MB, at least 224 x 224) and reduces it to 1024 px on
  /// the long edge as JPEG quality 80 (UC800 C3, C4). Runs off the UI thread (ASR_03).
  Future<Result<PreparedImage>> prepare(Uint8List original) async {
    if (original.length > AppConstants.maxImageBytes) {
      return const Failure(Messages.invalidImage, code: 'image_too_large');
    }
    try {
      final out = await Isolate.run(() => _prepare(original));
      if (out == null) {
        return const Failure(Messages.invalidImage, code: 'invalid_image');
      }
      return Success(out);
    } catch (e) {
      return Failure(Messages.invalidImage, code: 'invalid_image', cause: e);
    }
  }

  static PreparedImage? _prepare(Uint8List bytes) {
    final format = img.findFormatForData(bytes);
    if (format != img.ImageFormat.jpg && format != img.ImageFormat.png) {
      return null;
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final im = img.bakeOrientation(decoded);
    if (im.width < AppConstants.minImageSidePx || im.height < AppConstants.minImageSidePx) {
      return null;
    }
    const edge = AppConstants.uploadLongEdgePx;
    final resized = im.width >= im.height
        ? (im.width > edge ? img.copyResize(im, width: edge, interpolation: img.Interpolation.average) : im)
        : (im.height > edge ? img.copyResize(im, height: edge, interpolation: img.Interpolation.average) : im);
    final jpg = img.encodeJpg(resized, quality: AppConstants.uploadJpegQuality);
    return PreparedImage(Uint8List.fromList(jpg), resized.width, resized.height);
  }

  /// Identifies the foods present (FR700_003, FR700_004).
  /// Only the photo and the profile codes are sent (FR700_046); the verdicts shown are worked out
  /// again on the phone from the same rules.
  Future<Result<RecognitionResult>> recognise(
    PreparedImage image,
    List<String> conditionCodes, {
    List<String> restrictionCodes = const [],
    List<String> limitationCodes = const [],
  }) async {
    final res = await _api.postBytes(
      AppConstants.recognisePath,
      image.upload,
      filename: 'meal.jpg',
      fields: {
        'conditions': conditionCodes.join(','),
        'restrictions': restrictionCodes.join(','),
        'limitations': limitationCodes.join(','),
      },
      timeout: AppConstants.recogniseTimeout,
    );
    if (res case Failure(:final code, :final cause)) {
      final msg = code == 'invalid_image' || code == 'image_too_small' || code == 'image_too_large'
          ? Messages.invalidImage
          : Messages.recognitionUnavailable; // M7, E1
      return Failure(msg, code: code, cause: cause);
    }
    final body = res.dataOrNull!;
    modelVersion = (body['model_version'] ?? '') as String;
    final items = <RecognisedFood>[];
    for (final raw in (body['items'] as List? ?? const [])) {
      final it = Map<String, dynamic>.from(raw as Map);
      final food = await mapToCatalogue(it['food_key'] as String);
      if (food == null) continue;
      final cands = <FoodItem>[];
      for (final c in (it['candidates'] as List? ?? const [])) {
        final f = await mapToCatalogue((c as Map)['food_key'] as String);
        if (f != null) cands.add(f);
      }
      items.add(
        RecognisedFood(
          food: food,
          confidence: ((it['confidence'] ?? 0) as num).toDouble(),
          primary: (it['primary'] ?? true) as bool,
          candidates: cands,
          portionG: switch (it['portion_g']) {
            final num g when g.isFinite && g >= AppConstants.portionMinG && g <= AppConstants.portionMaxG =>
              g.toDouble(),
            _ => null,
          },
          details: body['provider'] == 'gemini' ? FoodRecognitionDetails.fromJson(it) : null,
        ),
      );
    }
    return Success(
      RecognitionResult(
        items: items,
        confidence: ((body['confidence'] ?? 0) as num).toDouble(),
        isFood: (body['is_food'] ?? true) as bool,
        modelVersion: modelVersion,
        elapsedMs: ((body['elapsed_ms'] ?? 0) as num).toInt(),
        warnings: (body['warnings'] as List? ?? const []).whereType<String>().toList(),
        provider: body['provider'] as String? ?? 'local',
      ),
    );
  }

  /// Resolves a raw label onto a catalogue food.
  Future<FoodItem?> mapToCatalogue(String label) async => (await _foods.byKey(label)).dataOrNull;

  /// Whether the result may be used without manual confirmation.
  bool isConfident(double c) => c >= confidenceFloor;
}
