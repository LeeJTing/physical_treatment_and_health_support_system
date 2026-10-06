import 'dart:io';

import 'package:video_player/video_player.dart';

import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/services/api_client.dart';
import 'package:physical_treatment_and_health_support_system/data/models/exercise.dart';
import 'package:physical_treatment_and_health_support_system/data/models/exercise_session.dart';

/// Length and frame size of a video file, read on the device.
class VideoInfo {
  final Duration duration;
  final int width;
  final int height;
  const VideoInfo(this.duration, this.width, this.height);
  int get shortSide => width < height ? width : height;
}

/// Reads [VideoInfo]. The real one opens the file with video_player; tests use a fake.
abstract interface class VideoProbe {
  Future<VideoInfo> probe(File file);
}

class VideoPlayerProbe implements VideoProbe {
  @override
  Future<VideoInfo> probe(File file) async {
    final c = VideoPlayerController.file(file);
    try {
      await c.initialize();
      final size = c.value.size;
      return VideoInfo(
        c.value.duration,
        size.width.round(),
        size.height.round(),
      );
    } finally {
      await c.dispose();
    }
  }
}

/// Outcome of the on-device checks (FR300_14 to FR300_16).
class VideoCheck {
  final bool ok;
  final String? message;
  const VideoCheck.passed() : ok = true, message = null;
  const VideoCheck.failed(this.message) : ok = false;
}

/// Uploads a recorded exercise clip to the AI server, where the pose model extracts the
/// landmarks and scores the posture (Table 4.76). Only the checks that can be made on the
/// device run here, so an invalid clip is never uploaded.
class PoseEstimationService {
  final ApiClient _api;
  final VideoProbe _probe;

  /// 720p floor checked before upload (FR300_15).
  final int minResolution = AppConstants.minVideoHeightPx;

  /// Returned by the server and stored with the session so scores stay comparable.
  String modelVersion = 'unknown';

  PoseEstimationService(this._api, {VideoProbe? probe})
    : _probe = probe ?? VideoPlayerProbe();

  /// Format, 10 to 30 s, at most 100 MB and at least 720p (FR300_14 to FR300_16).
  Future<VideoCheck> validateVideo(File v) async {
    final ext = v.path.split('.').last.toLowerCase();
    if (!AppConstants.allowedVideoExtensions.contains(ext)) {
      return const VideoCheck.failed(Messages.videoInvalid);
    }
    if (!await v.exists()) {
      return const VideoCheck.failed(Messages.videoInvalid);
    }
    if (await v.length() > AppConstants.maxVideoBytes) {
      return const VideoCheck.failed(Messages.videoInvalid);
    }
    final VideoInfo info;
    try {
      info = await _probe.probe(v);
    } catch (_) {
      return const VideoCheck.failed(Messages.videoInvalid);
    }
    final sec = info.duration.inMilliseconds / 1000;
    if (sec < AppConstants.minVideoSeconds - 0.5 ||
        sec > AppConstants.maxVideoSeconds + 0.5) {
      return const VideoCheck.failed(Messages.videoInvalid);
    }
    if (info.shortSide < minResolution) {
      return const VideoCheck.failed(Messages.deviceCompatibility);
    }
    return const VideoCheck.passed();
  }

  /// Uploads the clip and returns accuracy, repetitions and corrective guidance
  /// (FR300_06 to FR300_09). Server error codes map to the UC500 messages.
  Future<Result<PostureResult>> analyse(File v, Exercise e) async {
    final key = e.poseKey;
    if (key == null) {
      return const Failure(
        Messages.postureAnalyseFailed,
        code: 'unknown_exercise',
      );
    }
    final res = await _api.postFile(
      AppConstants.posePath,
      v,
      fields: {'exercise_key': key},
    );
    if (res is Failure<Map<String, dynamic>>) {
      final message = switch (res.code) {
        'invalid_video' => Messages.videoInvalid, // FR300_16
        'full_body_not_visible' => Messages.fullBodyNotVisible, // FR300_17
        'pose_not_detected' => Messages.poseDetectFailed, // FR300_25
        'unauthorised' => res.message,
        _ =>
          Messages
              .postureAnalyseFailed, // FR300_26 (no repetition, timeout, ...)
      };
      return Failure(message, code: res.code, cause: res.cause);
    }
    return guard(() async {
      final r = PostureResult.fromJson(res.dataOrNull!);
      modelVersion = r.modelVersion;
      return r;
    }, message: Messages.postureAnalyseFailed);
  }

  /// The server reports whether the whole body was in frame; re-record if not (FR300_17).
  bool isFullBodyVisible(PostureResult r) => r.fullBodyVisible;
}
