import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_insights.dart';

class HealthTimeline extends StatefulWidget {
  final List<HealthTimelineEvent> events;
  final ValueChanged<HealthTimelineEvent> onSelected;
  final String? selectedId;
  const HealthTimeline({
    super.key,
    required this.events,
    required this.onSelected,
    this.selectedId,
  });
  @override
  State<HealthTimeline> createState() => _HealthTimelineState();
}

class _HealthTimelineState extends State<HealthTimeline> {
  double zoom = 1;
  static const colors = [
    Color(0xFF4775B0),
    Color(0xFF137A69),
    Color(0xFFBA4747),
    Color(0xFF8064A2),
    Color(0xFFA66C23),
  ];
  static const icons = [
    Icons.event_note,
    Icons.restaurant,
    Icons.favorite,
    Icons.accessibility_new,
    Icons.self_improvement,
  ];
  static const labels = [
    'Planned',
    'Meals',
    'Readings',
    'Exercise',
    'Recovery',
  ];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'A day at a glance',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          IconButton(
            tooltip: 'Zoom out timeline',
            onPressed: zoom <= 1
                ? null
                : () => setState(() => zoom = (zoom / 2).clamp(1, 4)),
            icon: const Icon(Icons.zoom_out),
          ),
          Text('${zoom.toInt()}×'),
          IconButton(
            tooltip: 'Zoom in timeline',
            onPressed: zoom >= 4
                ? null
                : () => setState(() => zoom = (zoom * 2).clamp(1, 4)),
            icon: const Icon(Icons.zoom_in),
          ),
        ],
      ),
      const Text(
        'Zoom and scroll sideways. Tap a marker or a record below. Planned meal times are suggested positions.',
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, box) {
          final width = (box.maxWidth < 600 ? 600.0 : box.maxWidth) * zoom;
          final selected = widget.events
              .where((e) => e.id == widget.selectedId)
              .firstOrNull;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width + 90,
              height: 290,
              child: Stack(
                children: [
                  if (selected != null)
                    Positioned(
                      key: const ValueKey('timeline-selected-line'),
                      left:
                          90 +
                          ((selected.at.hour * 60 + selected.at.minute) /
                                  1440) *
                              (width - 28) +
                          4,
                      top: 27,
                      bottom: 20,
                      child: const VerticalDivider(
                        color: Color(0xFF23796C),
                        thickness: 2,
                        width: 2,
                      ),
                    ),
                  for (var i = 0; i < labels.length; i++)
                    Positioned(
                      left: 0,
                      top: 43 + i * 44,
                      width: 84,
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          color: colors[i],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  for (var h = 0; h <= 24; h += 3)
                    Positioned(
                      left: 90 + h / 24 * (width - 28),
                      top: 5,
                      bottom: 20,
                      child: Column(
                        children: [
                          Text(
                            '${h.toString().padLeft(2, '0')}:00',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const Expanded(
                            child: VerticalDivider(color: Color(0xFFE4E9EB)),
                          ),
                        ],
                      ),
                    ),
                  for (final e in widget.events)
                    Positioned(
                      left:
                          90 +
                          ((e.at.hour * 60 + e.at.minute) / 1440) *
                              (width - 28) -
                          14,
                      top: 30 + e.kind.index * 44,
                      width: 36,
                      height: 40,
                      child: IconButton(
                        key: ValueKey('timeline-${e.id}'),
                        padding: EdgeInsets.zero,
                        tooltip: '${DateFormat.Hm().format(e.at)} ${e.title}',
                        style: IconButton.styleFrom(
                          backgroundColor: widget.selectedId == e.id
                              ? colors[e.kind.index]
                              : colors[e.kind.index].withValues(alpha: .13),
                          foregroundColor: widget.selectedId == e.id
                              ? Colors.white
                              : colors[e.kind.index],
                        ),
                        onPressed: () => widget.onSelected(e),
                        icon: Icon(icons[e.kind.index], size: 20),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ],
  );
}
