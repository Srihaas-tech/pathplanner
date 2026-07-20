import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/simulation/path2_simulator.dart';
import 'package:pathplanner/path2/simulation/simulation_state.dart';
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/services/log.dart';
import 'package:pathplanner/services/pplib_telemetry.dart';
import 'package:pathplanner/trajectory/config.dart';
import 'package:pathplanner/util/path_painter_util.dart';
import 'package:pathplanner/util/prefs.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/widgets/editor/path2_painter.dart';
import 'package:pathplanner/widgets/editor/preview_seekbar.dart';
import 'package:pathplanner/widgets/editor/runtime_display.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_tree.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_waypoints_tree.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undo/undo.dart';

class SplitPath2Editor extends StatefulWidget {
  final SharedPreferences prefs;
  final path2.Path path;
  final FieldImage fieldImage;
  final ChangeStack undoStack;
  final PPLibTelemetry? telemetry;
  final bool hotReload;
  final VoidCallback? onPathChanged;

  const SplitPath2Editor({
    super.key,
    required this.prefs,
    required this.path,
    required this.fieldImage,
    required this.undoStack,
    this.telemetry,
    this.hotReload = false,
    this.onPathChanged,
  });

  @override
  State<SplitPath2Editor> createState() => _SplitPath2EditorState();
}

class _SplitPath2EditorState extends State<SplitPath2Editor>
    with TickerProviderStateMixin {
  final MultiSplitViewController _splitController = MultiSplitViewController();
  final Path2WaypointsTreeController _waypointsTreeController =
      Path2WaypointsTreeController();

  late AnimationController _previewController;
  late bool _treeOnRight;
  int? _hoveredWaypoint;
  int? _selectedWaypoint;
  int? _hoveredMarker;
  int? _selectedMarker;
  int? _hoveredConstraintZone;
  int? _selectedConstraintZone;
  int? _hoveredPointZone;
  int? _selectedPointZone;
  Waypoint? _draggedWaypoint;
  Waypoint? _dragOldValue;
  int? _draggedRotationWaypoint;
  Rotation2d? _dragRotationOldValue;
  int? _draggedPointZone;
  Translation2d? _dragPointZoneOldValue;
  Offset? _panDownPosition;
  late final Size _robotSize;
  late final Translation2d _bumperOffset;
  Path2SimulationResult? _simulation;
  RuntimeDisplay? _runtimeDisplay;
  bool _paused = false;
  int _simulationGeneration = 0;

  List<Waypoint> get waypoints => widget.path.waypoints;

  @override
  void initState() {
    super.initState();
    _previewController = AnimationController(vsync: this, value: 0);
    _treeOnRight =
        widget.prefs.getBool(PrefsKeys.treeOnRight) ?? Defaults.treeOnRight;
    _robotSize = Size(
      widget.prefs.getDouble(PrefsKeys.robotWidth) ?? Defaults.robotWidth,
      widget.prefs.getDouble(PrefsKeys.robotLength) ?? Defaults.robotLength,
    );
    _bumperOffset = Translation2d(
      widget.prefs.getDouble(PrefsKeys.bumperOffsetX) ?? Defaults.bumperOffsetX,
      widget.prefs.getDouble(PrefsKeys.bumperOffsetY) ?? Defaults.bumperOffsetY,
    );

    final treeWeight = widget.prefs.getDouble(PrefsKeys.editorTreeWeight) ??
        Defaults.editorTreeWeight;
    _splitController.areas = [
      Area(
        weight: _treeOnRight ? 1 - treeWeight : treeWeight,
        minimalWeight: 0.4,
      ),
      Area(
        weight: _treeOnRight ? treeWeight : 1 - treeWeight,
        minimalWeight: 0.4,
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) => _simulatePath());
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Center(
          child: InteractiveViewer(
            maxScale: 10,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _handleTapDown,
              onDoubleTapDown: _handleDoubleTap,
              onPanDown: (details) {
                _panDownPosition = details.localPosition;
              },
              onPanStart: _handlePanStart,
              onPanUpdate: _handlePanUpdate,
              onPanEnd: (_) => _finishDrag(),
              onPanCancel: _finishDrag,
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Stack(
                  children: [
                    widget.fieldImage.getWidget(),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: Path2Painter(
                          colorScheme: colorScheme,
                          paths: [widget.path],
                          fieldImage: widget.fieldImage,
                          prefs: widget.prefs,
                          hoveredWaypoint: _hoveredWaypoint,
                          selectedWaypoint: _selectedWaypoint,
                          hoveredMarker: _hoveredMarker,
                          selectedMarker: _selectedMarker,
                          hoveredConstraintZone: _hoveredConstraintZone,
                          selectedConstraintZone: _selectedConstraintZone,
                          hoveredPointZone: _hoveredPointZone,
                          selectedPointZone: _selectedPointZone,
                          simulation: _simulation,
                          animation: _previewController.view,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        MultiSplitViewTheme(
          data: MultiSplitViewThemeData(
            dividerPainter: DividerPainters.grooved1(
              color: colorScheme.surfaceContainerHighest,
              highlightedColor: colorScheme.primary,
            ),
          ),
          child: MultiSplitView(
            axis: Axis.horizontal,
            controller: _splitController,
            onWeightChange: _saveTreeWeight,
            children: [
              if (_treeOnRight) _buildSeekbar(),
              Card(
                margin: EdgeInsets.zero,
                elevation: 4,
                color: colorScheme.surface,
                surfaceTintColor: colorScheme.surfaceTint,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft:
                        _treeOnRight ? const Radius.circular(12) : Radius.zero,
                    topRight:
                        _treeOnRight ? Radius.zero : const Radius.circular(12),
                    bottomLeft:
                        _treeOnRight ? const Radius.circular(12) : Radius.zero,
                    bottomRight:
                        _treeOnRight ? Radius.zero : const Radius.circular(12),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Path2Tree(
                    path: widget.path,
                    undoStack: widget.undoStack,
                    initiallySelectedWaypoint: _selectedWaypoint,
                    initiallySelectedMarker: _selectedMarker,
                    initiallySelectedConstraintZone: _selectedConstraintZone,
                    initiallySelectedPointZone: _selectedPointZone,
                    waypointsTreeController: _waypointsTreeController,
                    onPathChanged: () {
                      setState(_saveAndNotify);
                    },
                    onPathChangedNoSim: () {
                      setState(_saveAndNotifyNoSim);
                    },
                    onWaypointDeleted: _deleteWaypoint,
                    onSideSwapped: _swapTreeSide,
                    onWaypointHovered: (index) {
                      setState(() => _hoveredWaypoint = index);
                    },
                    onWaypointSelected: (index) {
                      setState(() => _selectedWaypoint = index);
                    },
                    onMarkerHovered: (index) {
                      setState(() => _hoveredMarker = index);
                    },
                    onMarkerSelected: (index) {
                      setState(() => _selectedMarker = index);
                    },
                    onConstraintZoneHovered: (index) {
                      setState(() => _hoveredConstraintZone = index);
                    },
                    onConstraintZoneSelected: (index) {
                      setState(() => _selectedConstraintZone = index);
                    },
                    onPointZoneHovered: (index) {
                      setState(() => _hoveredPointZone = index);
                    },
                    onPointZoneSelected: (index) {
                      setState(() => _selectedPointZone = index);
                    },
                    runtimeDisplay: _runtimeDisplay,
                  ),
                ),
              ),
              if (!_treeOnRight) _buildSeekbar(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeekbar() {
    return PreviewSeekbar(
      previewController: _previewController,
      onPauseStateChanged: (paused) => _paused = paused,
      totalPathTime: _simulation?.totalTimeSeconds ?? 0,
      enabled: _simulation != null,
    );
  }

  void _handleTapDown(TapDownDetails details) {
    FocusManager.instance.primaryFocus?.unfocus();

    final x = _xPixelsToMeters(details.localPosition.dx);
    final y = _yPixelsToMeters(details.localPosition.dy);
    final hitRadius = _pixelsToMeters(
      PathPainterUtil.uiPointSizeToPixels(
        25,
        Path2Painter.scale,
        widget.fieldImage,
      ),
    );

    if (_pointZoneTargetHitTest(x, y) != null) {
      _setSelectedWaypoint(null);
      return;
    }

    for (var index = waypoints.length - 1; index >= 0; index--) {
      if (waypoints[index].isPointInAnchor(x, y, hitRadius)) {
        _setSelectedWaypoint(index);
        return;
      }
    }

    final rotationIndex = _rotationHandleHitTest(x, y);
    if (rotationIndex != null) {
      _setSelectedWaypoint(rotationIndex);
      return;
    }
    _setSelectedWaypoint(null);
  }

  void _handleDoubleTap(TapDownDetails details) {
    final oldWaypoints = _cloneWaypoints(waypoints);
    final position = Translation2d(
      _xPixelsToMeters(details.localPosition.dx),
      _yPixelsToMeters(details.localPosition.dy),
    );

    widget.undoStack.add(Change<List<Waypoint>>(
      oldWaypoints,
      () {
        setState(() {
          widget.path.addWaypoint(position);
          _saveAndNotify();
        });
      },
      (oldValue) {
        setState(() {
          widget.path.waypoints = _cloneWaypoints(oldValue);
          _clearWaypointSelection();
          _saveAndNotify();
        });
      },
    ));
  }

  void _handlePanStart(DragStartDetails details) {
    final startPosition = _panDownPosition ?? details.localPosition;
    _panDownPosition = null;
    final x = _xPixelsToMeters(startPosition.dx);
    final y = _yPixelsToMeters(startPosition.dy);
    final hitRadius = _pixelsToMeters(
      PathPainterUtil.uiPointSizeToPixels(
        25,
        Path2Painter.scale,
        widget.fieldImage,
      ),
    );

    final pointZoneIndex = _pointZoneTargetHitTest(x, y);
    if (pointZoneIndex != null) {
      _draggedPointZone = pointZoneIndex;
      _dragPointZoneOldValue =
          widget.path.pointTowardsZones[pointZoneIndex].fieldPosition;
      _setSelectedWaypoint(null);
      return;
    }

    for (var index = waypoints.length - 1; index >= 0; index--) {
      final waypoint = waypoints[index];
      if (waypoint.startDragging(x, y, hitRadius)) {
        _draggedWaypoint = waypoint;
        _dragOldValue = waypoint.clone();
        _setSelectedWaypoint(index);
        return;
      }
    }

    final rotationIndex = _rotationHandleHitTest(x, y);
    if (rotationIndex != null) {
      final waypoint = waypoints[rotationIndex] as PoseWaypoint;
      _draggedRotationWaypoint = rotationIndex;
      _dragRotationOldValue = waypoint.rotation;
      _setSelectedWaypoint(rotationIndex);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final draggedPointZone = _draggedPointZone;
    if (draggedPointZone != null) {
      if (draggedPointZone >= widget.path.pointTowardsZones.length) {
        return;
      }
      final target = _clampedFieldPosition(details.localPosition);
      setState(() {
        widget.path.pointTowardsZones[draggedPointZone].fieldPosition = target;
      });
      return;
    }

    final dragged = _draggedWaypoint;
    if (dragged == null) {
      final rotationIndex = _draggedRotationWaypoint;
      if (rotationIndex == null || rotationIndex >= waypoints.length) {
        return;
      }
      final waypoint = waypoints[rotationIndex];
      if (waypoint is! PoseWaypoint) {
        return;
      }

      final x = _xPixelsToMeters(details.localPosition.dx);
      final y = _yPixelsToMeters(details.localPosition.dy);
      setState(() {
        waypoint.rotation = Rotation2d.fromComponents(
          x - waypoint.position.x,
          y - waypoint.position.y,
        );
      });
      return;
    }

    final target = _clampedFieldPosition(details.localPosition);
    num targetX = target.x;
    num targetY = target.y;

    final snapSetting = widget.prefs.getBool(PrefsKeys.snapToGuidelines) ??
        Defaults.snapToGuidelines;
    final ctrlHeld = HardwareKeyboard.instance.logicalKeysPressed
            .contains(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed
            .contains(LogicalKeyboardKey.controlRight);

    if (snapSetting ^ ctrlHeld) {
      num? closestX;
      num? closestY;
      for (final waypoint in waypoints) {
        if (waypoint == dragged) {
          continue;
        }
        if (closestX == null ||
            (targetX - waypoint.position.x).abs() <
                (targetX - closestX).abs()) {
          closestX = waypoint.position.x;
        }
        if (closestY == null ||
            (targetY - waypoint.position.y).abs() <
                (targetY - closestY).abs()) {
          closestY = waypoint.position.y;
        }
      }
      if (closestX != null && (targetX - closestX).abs() < 0.1) {
        targetX = closestX;
      }
      if (closestY != null && (targetY - closestY).abs() < 0.1) {
        targetY = closestY;
      }
    }

    setState(() => dragged.dragUpdate(targetX, targetY));
  }

  void _finishDrag() {
    _panDownPosition = null;
    if (_draggedPointZone != null) {
      _finishPointZoneDrag();
    } else if (_draggedWaypoint != null) {
      _finishWaypointDrag();
    } else if (_draggedRotationWaypoint != null) {
      _finishRotationDrag();
    }
  }

  void _finishPointZoneDrag() {
    final index = _draggedPointZone;
    final oldValue = _dragPointZoneOldValue;
    _draggedPointZone = null;
    _dragPointZoneOldValue = null;
    if (index == null ||
        oldValue == null ||
        index >= widget.path.pointTowardsZones.length) {
      return;
    }

    final endValue = widget.path.pointTowardsZones[index].fieldPosition;
    if (endValue == oldValue) {
      return;
    }

    widget.undoStack.add(Change<Translation2d>(
      oldValue,
      () {
        setState(() {
          widget.path.pointTowardsZones[index].fieldPosition = endValue;
          _saveAndNotify();
        });
      },
      (previousValue) {
        setState(() {
          widget.path.pointTowardsZones[index].fieldPosition = previousValue;
          _saveAndNotify();
        });
      },
    ));
  }

  void _finishWaypointDrag() {
    final dragged = _draggedWaypoint;
    final oldValue = _dragOldValue;
    if (dragged == null || oldValue == null) {
      return;
    }

    dragged.stopDragging();
    final index = waypoints.indexOf(dragged);
    if (index < 0) {
      _draggedWaypoint = null;
      _dragOldValue = null;
      return;
    }
    final endValue = dragged.clone();

    widget.undoStack.add(Change<Waypoint>(
      oldValue,
      () {
        setState(() {
          if (waypoints[index] != dragged) {
            waypoints[index] = endValue.clone();
          }
          _saveAndNotify();
        });
      },
      (previousValue) {
        setState(() {
          waypoints[index] = previousValue.clone();
          _saveAndNotify();
        });
      },
    ));

    _draggedWaypoint = null;
    _dragOldValue = null;
  }

  void _finishRotationDrag() {
    final index = _draggedRotationWaypoint;
    final oldValue = _dragRotationOldValue;
    if (index == null || oldValue == null || index >= waypoints.length) {
      _draggedRotationWaypoint = null;
      _dragRotationOldValue = null;
      return;
    }

    final waypoint = waypoints[index];
    if (waypoint is! PoseWaypoint) {
      _draggedRotationWaypoint = null;
      _dragRotationOldValue = null;
      return;
    }
    final endValue = waypoint.rotation;

    widget.undoStack.add(Change<Rotation2d>(
      oldValue,
      () {
        setState(() {
          final current = waypoints[index];
          if (current is PoseWaypoint) {
            current.rotation = endValue;
          }
          _saveAndNotify();
        });
      },
      (previousValue) {
        setState(() {
          final current = waypoints[index];
          if (current is PoseWaypoint) {
            current.rotation = previousValue;
          }
          _saveAndNotify();
        });
      },
    ));

    _draggedRotationWaypoint = null;
    _dragRotationOldValue = null;
  }

  int? _rotationHandleHitTest(num x, num y) {
    final hitRadius = _pixelsToMeters(
      PathPainterUtil.uiPointSizeToPixels(
        15,
        Path2Painter.scale,
        widget.fieldImage,
      ),
    );
    final pointer = Translation2d(x, y);

    for (var index = waypoints.length - 1; index >= 0; index--) {
      final waypoint = waypoints[index];
      if (waypoint is PoseWaypoint &&
          _rotationHandlePosition(waypoint).getDistance(pointer) < hitRadius) {
        return index;
      }
    }
    return null;
  }

  Translation2d _rotationHandlePosition(PoseWaypoint waypoint) {
    final handleOffset = Translation2d(
      (_robotSize.height / 2) + _bumperOffset.x,
      _bumperOffset.y,
    ).rotateBy(waypoint.rotation);
    return waypoint.position + handleOffset;
  }

  int? _pointZoneTargetHitTest(num x, num y) {
    final index = _selectedPointZone;
    if (index == null ||
        index < 0 ||
        index >= widget.path.pointTowardsZones.length) {
      return null;
    }
    final hitRadius = _pixelsToMeters(
      PathPainterUtil.uiPointSizeToPixels(
        40,
        Path2Painter.scale,
        widget.fieldImage,
      ),
    );
    final target = widget.path.pointTowardsZones[index].fieldPosition;
    return target.getDistance(Translation2d(x, y)) <= hitRadius ? index : null;
  }

  Translation2d _clampedFieldPosition(Offset localPosition) {
    final x = _xPixelsToMeters(
      min(
        88 + widget.fieldImage.defaultSize.width * Path2Painter.scale,
        max(8, localPosition.dx),
      ),
    );
    final y = _yPixelsToMeters(
      min(
        88 + widget.fieldImage.defaultSize.height * Path2Painter.scale,
        max(8, localPosition.dy),
      ),
    );
    return Translation2d(x, y);
  }

  void _deleteWaypoint(int index) {
    if (waypoints.length <= 1 || index < 0 || index >= waypoints.length) {
      return;
    }

    final oldValue = _Path2WaypointEditSnapshot(
      _cloneWaypoints(waypoints),
      widget.path.snapshotAnnotations(),
    );
    widget.undoStack.add(Change<_Path2WaypointEditSnapshot>(
      oldValue,
      () {
        setState(() {
          widget.path.removeWaypointAt(index);
          _clearWaypointSelection();
          _saveAndNotify();
        });
      },
      (oldValue) {
        setState(() {
          widget.path.waypoints = _cloneWaypoints(oldValue.waypoints);
          widget.path.restoreAnnotations(oldValue.annotations);
          _clearWaypointSelection();
          _saveAndNotify();
        });
      },
    ));
  }

  void _clearWaypointSelection() {
    _selectedWaypoint = null;
    _hoveredWaypoint = null;
    _waypointsTreeController.setSelectedWaypoint(null);
  }

  void _setSelectedWaypoint(int? index) {
    setState(() => _selectedWaypoint = index);
    _waypointsTreeController.setSelectedWaypoint(index);
  }

  void _swapTreeSide() {
    setState(() {
      _treeOnRight = !_treeOnRight;
      widget.prefs.setBool(PrefsKeys.treeOnRight, _treeOnRight);
      _splitController.areas = _splitController.areas.reversed.toList();
    });
  }

  void _saveTreeWeight() {
    final newWeight = _treeOnRight
        ? _splitController.areas[1].weight
        : _splitController.areas[0].weight;
    widget.prefs.setDouble(PrefsKeys.editorTreeWeight, newWeight ?? 0.5);
  }

  void _saveAndNotify() {
    widget.path.saveFile();
    if (widget.hotReload) {
      widget.telemetry?.hotReloadPath(widget.path);
    }
    widget.onPathChanged?.call();
    _simulatePath();
  }

  void _saveAndNotifyNoSim() {
    widget.path.saveFile();
    if (widget.hotReload) {
      widget.telemetry?.hotReloadPath(widget.path);
    }
    widget.onPathChanged?.call();
  }

  Future<void> _simulatePath() async {
    final generation = ++_simulationGeneration;
    final previousSimulation = _simulation;
    final previousTime = previousSimulation == null
        ? 0.0
        : _previewController.value * previousSimulation.totalTimeSeconds;
    late final Path2SimulationOutcome outcome;
    try {
      outcome = await Path2Simulator.simulatePathInBackground(
        widget.path,
        RobotConfig.fromPrefs(widget.prefs),
      );
    } catch (error) {
      outcome = Path2SimulationOutcome.failed(
        Path2SimulationFailure(
          Path2SimulationFailureKind.invalidConfiguration,
          error.toString(),
        ),
      );
    }
    if (!mounted || generation != _simulationGeneration) {
      return;
    }

    final result = outcome.result;
    if (result == null) {
      _previewController
        ..stop()
        ..reset();
      setState(() {
        _simulation = null;
        _runtimeDisplay = null;
      });
      _showSimulationFailure(outcome.failure!);
      return;
    }

    final previousRuntime = _runtimeDisplay?.currentRuntime;
    setState(() {
      _simulation = result;
      _runtimeDisplay = RuntimeDisplay(
        currentRuntime: result.totalTimeSeconds,
        previousRuntime: previousRuntime,
      );
    });

    _previewController
      ..stop()
      ..duration = Duration(
        milliseconds: max(1, (result.totalTimeSeconds * 1000).round()),
      );
    if (_paused) {
      _previewController.value = result.totalTimeSeconds <= 0
          ? 0
          : (previousTime / result.totalTimeSeconds).clamp(0.0, 1.0).toDouble();
    } else {
      _previewController
        ..value = 0
        ..repeat();
    }
  }

  void _showSimulationFailure(Path2SimulationFailure failure) {
    Log.warning('Failed to simulate Path2 path ${widget.path.name}: $failure');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Unable to simulate ${widget.path.name}: '
              '${failure.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  double _xPixelsToMeters(double pixels) {
    return (((pixels - 48) / Path2Painter.scale) /
            widget.fieldImage.pixelsPerMeter) -
        widget.fieldImage.marginMeters;
  }

  double _yPixelsToMeters(double pixels) {
    return ((widget.fieldImage.defaultSize.height -
                (pixels - 48) / Path2Painter.scale) /
            widget.fieldImage.pixelsPerMeter) -
        widget.fieldImage.marginMeters;
  }

  double _pixelsToMeters(double pixels) =>
      (pixels / Path2Painter.scale) / widget.fieldImage.pixelsPerMeter;

  static List<Waypoint> _cloneWaypoints(List<Waypoint> waypoints) =>
      waypoints.map((waypoint) => waypoint.clone()).toList();
}

class _Path2WaypointEditSnapshot {
  final List<Waypoint> waypoints;
  final path2.PathAnnotationSnapshot annotations;

  const _Path2WaypointEditSnapshot(this.waypoints, this.annotations);
}
