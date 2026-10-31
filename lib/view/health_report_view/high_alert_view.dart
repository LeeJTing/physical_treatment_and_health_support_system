import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';

/// Full-screen warning for a High severity anomaly (UC600 A3, C8: red full screen; FR600_010),
/// with the advice to consult a healthcare professional (FR600_012, M3).
class HighAlertView extends StatelessWidget {
  final AnomalyEvent alert;
  const HighAlertView({super.key, required this.alert});

  static Future<void> show(BuildContext context, AnomalyEvent a) => Navigator.of(context).push(
    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => HighAlertView(alert: a)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFB3261E),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 88),
            const SizedBox(height: 16),
            const Text(
              'High severity health alert',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      Messages.consultProfessional,
                      style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      alert.explanationText,
                      style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 60,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFB3261E),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('I understand'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
