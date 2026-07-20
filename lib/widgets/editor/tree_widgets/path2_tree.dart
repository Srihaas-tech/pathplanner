import 'package:flutter/material.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/widgets/editor/tree_widgets/path2_constraint_zones_tree.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_event_markers_tree.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_path_configuration_tree.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_point_towards_zones_tree.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_waypoints_tree.dart';
import 'package:undo/undo.dart';

/// The Path2 editor sidebar.
class Path2Tree extends StatelessWidget {
  final path2.Path path;
  final ValueChanged<int?>? onWaypointHovered;
  final ValueChanged<int?>? onWaypointSelected;
  final ValueChanged<int>? onWaypointDeleted;
  final ValueChanged<int?>? onMarkerHovered;
  final ValueChanged<int?>? onMarkerSelected;
  final ValueChanged<int?>? onConstraintZoneHovered;
  final ValueChanged<int?>? onConstraintZoneSelected;
  final ValueChanged<int?>? onPointZoneHovered;
  final ValueChanged<int?>? onPointZoneSelected;
  final VoidCallback? onSideSwapped;
  final VoidCallback? onPathChanged;
  final VoidCallback? onPathChangedNoSim;
  final Path2WaypointsTreeController? waypointsTreeController;
  final int? initiallySelectedWaypoint;
  final int? initiallySelectedMarker;
  final int? initiallySelectedConstraintZone;
  final int? initiallySelectedPointZone;
  final Widget? runtimeDisplay;
  final ChangeStack undoStack;

  const Path2Tree({
    super.key,
    required this.path,
    required this.undoStack,
    this.onWaypointHovered,
    this.onWaypointSelected,
    this.onWaypointDeleted,
    this.onMarkerHovered,
    this.onMarkerSelected,
    this.onConstraintZoneHovered,
    this.onConstraintZoneSelected,
    this.onPointZoneHovered,
    this.onPointZoneSelected,
    this.onSideSwapped,
    this.onPathChanged,
    this.onPathChangedNoSim,
    this.waypointsTreeController,
    this.initiallySelectedWaypoint,
    this.initiallySelectedMarker,
    this.initiallySelectedConstraintZone,
    this.initiallySelectedPointZone,
    this.runtimeDisplay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (runtimeDisplay != null) runtimeDisplay!,
              const Spacer(),
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
            child: Column(
              children: [
                Path2WaypointsTree(
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
                Path2EventMarkersTree(
                  path: path,
                  undoStack: undoStack,
                  onPathChanged: onPathChanged,
                  onPathChangedNoSim: onPathChangedNoSim,
                  onMarkerHovered: onMarkerHovered,
                  onMarkerSelected: onMarkerSelected,
                  initiallySelectedMarker: initiallySelectedMarker,
                ),
                Path2PointTowardsZonesTree(
                  path: path,
                  undoStack: undoStack,
                  onPathChanged: onPathChanged,
                  onPathChangedNoSim: onPathChangedNoSim,
                  onZoneHovered: onPointZoneHovered,
                  onZoneSelected: onPointZoneSelected,
                  initiallySelectedZone: initiallySelectedPointZone,
                ),
                Path2PathConfigurationTree(
                  path: path,
                  undoStack: undoStack,
                  onPathChanged: onPathChanged,
                ),
                Path2ConstraintZonesTree(
                  path: path,
                  undoStack: undoStack,
                  onPathChanged: onPathChanged,
                  onPathChangedNoSim: onPathChangedNoSim,
                  onZoneHovered: onConstraintZoneHovered,
                  onZoneSelected: onConstraintZoneSelected,
                  initiallySelectedZone: initiallySelectedConstraintZone,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
