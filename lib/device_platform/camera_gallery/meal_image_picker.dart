import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Device Platform layer: the camera and the gallery for a meal photo (UC800 C2; FR700_001,
/// FR700_002). Returns the original bytes, which the FoodRecognitionService checks and reduces.
/// Null when the patient cancels (UC800 A7).
abstract interface class MealImageSource {
  Future<Uint8List?> capture();
  Future<Uint8List?> pickFromGallery();
}

class PluginMealImageSource implements MealImageSource {
  final ImagePicker _picker = ImagePicker();

  Future<Uint8List?> _pick(ImageSource s) async {
    final f = await _picker.pickImage(source: s, requestFullMetadata: false);
    return f == null ? null : await f.readAsBytes();
  }

  @override
  Future<Uint8List?> capture() => _pick(ImageSource.camera);

  @override
  Future<Uint8List?> pickFromGallery() => _pick(ImageSource.gallery);
}
