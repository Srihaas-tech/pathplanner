import 'package:flutter/material.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/item_count.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/tree_card_node.dart';
import 'package:pathplanner/widgets/number_text_field.dart';
import 'package:undo/undo.dart';

class Path2WaypointsTree extends StatefulWidget {
  final path2.Path path;
  final ValueChanged<int?>? onWaypointHovered;
  final ValueChanged<int?>? onWaypointSelected;
  final ValueChanged<int>? onWaypointDeleted;
  final VoidCallback? onPathChanged;
  final Path2WaypointsTreeController? controller;
  final int? initialSelectedWaypoint;
  final ChangeStack undoStack;

  const Path2WaypointsTree({
    super.key,
    required this.path,
    required this.undoStack,
    this.onWaypointHovered,
    this.onWaypointSelected,
    this.onWaypointDeleted,
    this.onPathChanged,
    this.controller,
    this.initialSelectedWaypoint,
  });

  @override
  State<Path2WaypointsTree> createState() => _Path2WaypointsTreeState();
}

class _Path2WaypointsTreeState extends State<Path2WaypointsTree> {
  List<Waypoint> get waypoints => widget.path.waypoints;

  late List<ExpansibleController> _controllers;
  late Path2WaypointsTreeController _treeController;
  final ExpansibleController _expansionController = ExpansibleController();
  int? _selectedWaypoint;
  bool _ignoreExpansionFromTile = false;

  @override
  void initState() {
    super.initState();
    _selectedWaypoint = widget.initialSelectedWaypoint;
    _controllers = _newControllers();
    _treeController = widget.controller ?? Path2WaypointsTreeController();
    _treeController._state = this;
  }

  @override
  void didUpdateWidget(covariant Path2WaypointsTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._state = null;
      _treeController = widget.controller ?? Path2WaypointsTreeController();
      _treeController._state = this;
    }
  }

  @override
  void dispose() {
    if (_treeController._state == this) {
      _treeController._state = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncControllers();

    return TreeCardNode(
      title: const Text('Waypoints'),
      leading: const Icon(Icons.location_on_rounded),
      trailing: ItemCount(count: waypoints.length),
      initiallyExpanded: widget.path.waypointsExpanded,
      controller: _expansionController,
      onExpansionChanged: (expanded) {
        if (expanded == null) {
          return;
        }
        widget.path.waypointsExpanded = expanded;
        if (!expanded) {
          _selectedWaypoint = null;
          widget.onWaypointSelected?.call(null);
        }
      },
      elevation: 1,
      children: [
        for (var index = 0; index < waypoints.length; index++)
          _buildWaypointNode(index),
      ],
    );
  }

  Widget _buildWaypointNode(int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final waypoint = waypoints[index];

    return TreeCardNode(
      onHoverStart: () => widget.onWaypointHovered?.call(index),
      onHoverEnd: () => widget.onWaypointHovered?.call(null),
      elevation: 4,
      controller: _controllers[index],
      initiallyExpanded: index == _selectedWaypoint,
      onExpansionChanged: (expanded) {
        if (_ignoreExpansionFromTile) {
          return;
        }
        if (expanded ?? false) {
          if (_selectedWaypoint != null &&
              _selectedWaypoint! < _controllers.length) {
            _controllers[_selectedWaypoint!].collapse();
          }
          _selectedWaypoint = index;
          widget.onWaypointSelected?.call(index);
        } else if (_selectedWaypoint == index) {
          _selectedWaypoint = null;
          widget.onWaypointSelected?.call(null);
        }
      },
      title: Row(
        children: [
          Icon(_waypointIcon(index, waypoint)),
          const SizedBox(width: 8),
          Text(_waypointName(index)),
          const Spacer(),
          if (waypoints.length > 1)
            Tooltip(
              message: 'Delete Waypoint',
              waitDuration: const Duration(seconds: 1),
              child: IconButton(
                onPressed: () => widget.onWaypointDeleted?.call(index),
                icon: const Icon(Icons.delete_forever),
                color: colorScheme.error,
              ),
            ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: NumberTextField(
                  key: ValueKey('path2Waypoint${index}X'),
                  initialValue: waypoint.position.x,
                  label: 'X Position (M)',
                  onSubmitted: (value) {
                    if (value != null) {
                      _addWaypointsChange(() {
                        final current = waypoints[index];
                        current.move(value, current.position.y);
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumberTextField(
                  key: ValueKey('path2Waypoint${index}Y'),
                  initialValue: waypoint.position.y,
                  label: 'Y Position (M)',
                  onSubmitted: (value) {
                    if (value != null) {
                      _addWaypointsChange(() {
                        final current = waypoints[index];
                        current.move(current.position.x, value);
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          title: const Text('Pose waypoint'),
          value: waypoint is PoseWaypoint,
          onChanged: (isPose) {
            _addWaypointsChange(() {
              waypoints[index] = waypoints[index]
                  .withRotation(isPose ? const Rotation2d() : null);
            });
          },
        ),
        if (waypoint is PoseWaypoint) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: NumberTextField(
              key: ValueKey('path2Waypoint${index}Heading'),
              initialValue: waypoint.rotation.degrees,
              label: 'Heading (Deg)',
              arrowKeyIncrement: 1,
              onSubmitted: (value) {
                if (value != null) {
                  _addWaypointsChange(() {
                    waypoints[index] = waypoints[index]
                        .withRotation(Rotation2d.fromDegrees(value));
                  });
                }
              },
            ),
          ),
        ],
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: NumberTextField(
                  key: ValueKey('path2Waypoint${index}MaxVelocity'),
                  initialValue: waypoint.maxVelocity,
                  label: 'Max Velocity (M/S)',
                  minValue: 0,
                  onSubmitted: (value) {
                    if (value != null) {
                      _addWaypointsChange(
                          () => waypoints[index].maxVelocity = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumberTextField(
                  key: ValueKey('path2Waypoint${index}HandoffDistance'),
                  initialValue: waypoint.handoffDistance,
                  label: 'Handoff Distance (M)',
                  minValue: 0,
                  onSubmitted: (value) {
                    if (value != null) {
                      _addWaypointsChange(
                          () => waypoints[index].handoffDistance = value);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: NumberTextField(
                  key: ValueKey('path2Waypoint${index}MaxAngularVelocity'),
                  initialValue: waypoint.maxAngularVelocity,
                  label: 'Max Angular Velocity (Deg/S)',
                  minValue: 0,
                  arrowKeyIncrement: 1,
                  onSubmitted: (value) {
                    if (value != null) {
                      _addWaypointsChange(
                          () => waypoints[index].maxAngularVelocity = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumberTextField(
                  key: ValueKey('path2Waypoint${index}MaxAngularAcceleration'),
                  initialValue: waypoint.maxAngularAcceleration,
                  label: 'Max Angular Acceleration (Deg/S²)',
                  minValue: 0,
                  arrowKeyIncrement: 1,
                  onSubmitted: (value) {
                    if (value != null) {
                      _addWaypointsChange(() =>
                          waypoints[index].maxAngularAcceleration = value);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        if (index < waypoints.length - 1) ...[
          const SizedBox(height: 8),
          Center(
            child: Tooltip(
              message: 'Create New Waypoint After',
              child: IconButton(
                onPressed: () => _addWaypointsChange(
                  () => widget.path.insertWaypointAfter(index),
                  clearSelection: true,
                ),
                icon: const Icon(Icons.add, size: 20),
              ),
            ),
          ),
        ],
      ],
    );
  }

  IconData _waypointIcon(int index, Waypoint waypoint) {
    if (index == 0) {
      return Icons.start_rounded;
    }
    if (index == waypoints.length - 1) {
      return Icons.flag_outlined;
    }
    return waypoint is PoseWaypoint ? Icons.explore_outlined : Icons.circle;
  }

  String _waypointName(int index) {
    if (index == 0) {
      return 'Start Point';
    }
    if (index == waypoints.length - 1) {
      return 'End Point';
    }
    return 'Waypoint $index';
  }

  void _addWaypointsChange(
    VoidCallback execute, {
    bool clearSelection = false,
  }) {
    final oldValue = _Path2WaypointEditSnapshot(
      _cloneWaypoints(waypoints),
      widget.path.snapshotAnnotations(),
    );
    widget.undoStack.add(Change<_Path2WaypointEditSnapshot>(
      oldValue,
      () => _applyChange(
        () {
          execute();
          if (clearSelection) {
            _clearSelection();
          }
        },
      ),
      (oldValue) => _applyChange(
        () {
          widget.path.waypoints = _cloneWaypoints(oldValue.waypoints);
          widget.path.restoreAnnotations(oldValue.annotations);
          if (clearSelection) {
            _clearSelection();
          }
        },
      ),
    ));
  }

  void _applyChange(VoidCallback mutation) {
    void apply() {
      mutation();
      widget.onPathChanged?.call();
    }

    // Inserting a waypoint changes this widget's key. The undo closure can
    // therefore outlive this State even though its parent editor is still
    // active. Apply through the parent callback in that case without trying
    // to rebuild a disposed State.
    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _clearSelection() {
    _selectedWaypoint = null;
    widget.onWaypointHovered?.call(null);
    widget.onWaypointSelected?.call(null);
  }

  void _setSelectedWaypoint(int? index) {
    _syncControllers();
    _ignoreExpansionFromTile = true;
    if (_selectedWaypoint != null &&
        _selectedWaypoint! < _controllers.length &&
        widget.path.waypointsExpanded) {
      _controllers[_selectedWaypoint!].collapse();
    }
    _selectedWaypoint = index;
    if (index != null &&
        index < _controllers.length &&
        widget.path.waypointsExpanded) {
      _controllers[index].expand();
    }
    _ignoreExpansionFromTile = false;
  }

  List<ExpansibleController> _newControllers() => List.generate(
        waypoints.length,
        (_) => ExpansibleController(),
      );

  void _syncControllers() {
    if (_controllers.length != waypoints.length) {
      _controllers = _newControllers();
      if (_selectedWaypoint != null && _selectedWaypoint! >= waypoints.length) {
        _selectedWaypoint = null;
      }
    }
  }

  static List<Waypoint> _cloneWaypoints(List<Waypoint> waypoints) =>
      waypoints.map((waypoint) => waypoint.clone()).toList();
}

class _Path2WaypointEditSnapshot {
  final List<Waypoint> waypoints;
  final path2.PathAnnotationSnapshot annotations;

  const _Path2WaypointEditSnapshot(this.waypoints, this.annotations);
}

class Path2WaypointsTreeController {
  _Path2WaypointsTreeState? _state;

  void setSelectedWaypoint(int? waypointIndex) {
    assert(_state != null);
    _state?._setSelectedWaypoint(waypointIndex);
  }
}
