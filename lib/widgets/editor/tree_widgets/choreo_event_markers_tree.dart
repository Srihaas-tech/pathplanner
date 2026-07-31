import 'package:flutter/material.dart';
import 'package:pathplanner/path/choreo_path.dart';

class ChoreoEventMarkersTree extends StatelessWidget {
  final List<ChoreoEventMarker> eventMarkers;

  const ChoreoEventMarkersTree({
    super.key,
    required this.eventMarkers,
  });

  @override
  Widget build(BuildContext context) {
    final markers = [...eventMarkers]..sort((a, b) => a.time.compareTo(b.time));

    return ExpansionTile(
      title: const Text('Event Markers'),
      initiallyExpanded: true,
      children: [
        if (markers.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('No Choreo event markers found.'),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                for (final marker in markers)
                  ListTile(
                    dense: true,
                    title: Text(
                      marker.name.isEmpty ? 'Unnamed marker' : marker.name,
                    ),
                    trailing: Text(
                      '${marker.time.toDouble().toStringAsFixed(2)} s',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
