import 'package:flutter/material.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/widgets/editor/tree_widgets/path2_waypoints_tree.dart';
import 'package:undo/undo.dart';

/// The Path2 editor sidebar.
///
/// Path2 currently supports waypoint configuration only. Keeping this tree
/// intentionally small avoids exposing legacy features that cannot be
/// represented by the new path format.
class Path2Tree extends StatelessWidget {
  final path2.Path path;
  final ValueChanged<int?>? onWaypointHovered;
  final ValueChanged<int?>? onWaypointSelected;
  final ValueChanged<int>? onWaypointDeleted;
  final VoidCallback? onSideSwapped;
  final VoidCallback? onPathChanged;
  final Path2WaypointsTreeController? waypointsTreeController;
  final int? initiallySelectedWaypoint;
  final ChangeStack undoStack;

  const Path2Tree({
    super.key,
    required this.path,
    required this.undoStack,
    this.onWaypointHovered,
    this.onWaypointSelected,
    this.onWaypointDeleted,
    this.onSideSwapped,
    this.onPathChanged,
    this.waypointsTreeController,
    this.initiallySelectedWaypoint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Tooltip(
                message: 'Move to Other Side',
                waitDuration: const Duration(milliseconds: 500),
                child: IconButton(
                  onPressed: onSideSwapped,
                  icon: const Icon(Icons.swap_horiz),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            child: Path2WaypointsTree(
              key: ValueKey('path2Waypoints${path.waypoints.length}'),
              path: path,
              undoStack: undoStack,
              controller: waypointsTreeController,
              initialSelectedWaypoint: initiallySelectedWaypoint,
              onWaypointHovered: onWaypointHovered,
              onWaypointSelected: onWaypointSelected,
              onWaypointDeleted: onWaypointDeleted,
              onPathChanged: onPathChanged,
            ),
          ),
        ),
      ],
    );
  }
}
