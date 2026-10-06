import 'package:flutter/material.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';

/// Temporary home screen so each module can be opened while it is built.
/// Replace with the real home design when the UI is agreed.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Health Profile', Icons.person_outline, Routes.healthProfile),
      ('Treatment Planning', Icons.assignment_outlined, Routes.treatmentPlanning),
      ('Physical Treatment', Icons.accessibility_new, Routes.physicalTreatment),
      ('Reminders', Icons.notifications_outlined, Routes.reminders),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (label, icon, route) in items)
            Card(
              child: ListTile(
                minVerticalPadding: 20,
                leading: Icon(icon, size: 32),
                title: Text(label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, route),
              ),
            ),
        ],
      ),
    );
  }
}

/// Placeholder for a route whose View has not been written yet.
class ComingSoonView extends StatelessWidget {
  final String title;
  const ComingSoonView(this.title, {super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: Text('Coming soon')));
}
