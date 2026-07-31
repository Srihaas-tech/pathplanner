import 'package:flutter/material.dart';

class ChoreoEventMarkersTree extends StatelessWidget {
  final List<num> eventMarkerTimes;

  const ChoreoEventMarkersTree({
    super.key,
    required this.eventMarkerTimes,
  });

  @override
  Widget build(BuildContext context) {
    final markerTimes = [...eventMarkerTimes]..sort((a, b) => a.compareTo(b));

    return ExpansionTile(
      title: const Text('Event Markers'),
      initiallyExpanded: true,
      children: [
        if (markerTimes.isEmpty)
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
                for (int i = 0; i < markerTimes.length; i++)
                  ListTile(
                    dense: true,
                    title: Text('Marker ${i + 1}'),
                    trailing: Text(
                      '${markerTimes[i].toDouble().toStringAsFixed(2)} s',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
