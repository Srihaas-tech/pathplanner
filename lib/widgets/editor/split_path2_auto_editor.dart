import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/pathplanner_auto.dart';
import 'package:pathplanner/path2/simulation/path2_simulator.dart';
import 'package:pathplanner/path2/simulation/simulation_state.dart';
import 'package:pathplanner/services/log.dart';
import 'package:pathplanner/trajectory/config.dart';
import 'package:pathplanner/util/path_painter_util.dart';
import 'package:pathplanner/util/prefs.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/widgets/editor/path2_painter.dart';
import 'package:pathplanner/widgets/editor/preview_seekbar.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_auto_tree.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undo/undo.dart';

class SplitPath2AutoEditor extends StatefulWidget {
  final SharedPreferences prefs;
  final Path2Auto auto;
  final List<path2.Path> autoPaths;
  final List<String> allPathNames;
  final VoidCallback? onAutoChanged;
  final FieldImage fieldImage;
  final ChangeStack undoStack;
  final ValueChanged<String?>? onEditPathPressed;

  const SplitPath2AutoEditor({
    super.key,
    required this.prefs,
    required this.auto,
    required this.autoPaths,
    required this.allPathNames,
    required this.fieldImage,
    required this.undoStack,
    this.onAutoChanged,
    this.onEditPathPressed,
  });

  @override
  State<SplitPath2AutoEditor> createState() => _SplitPath2AutoEditorState();
}

class _SplitPath2AutoEditorState extends State<SplitPath2AutoEditor>
    with SingleTickerProviderStateMixin {
  final MultiSplitViewController _controller = MultiSplitViewController();
  late final AnimationController _previewController;
  late bool _treeOnRight;
  String? _hoveredPath;
  Path2SimulationResult? _simulation;
  bool _paused = false;
  int _simulationGeneration = 0;
  Offset? _panDownPosition;
  bool _draggingStartingPosition = false;
  bool _draggingStartingRotation = false;
  _StartingPoseSnapshot? _startingPoseBeforeDrag;
  late final Size _robotSize;
  late final Translation2d _bumperOffset;

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
    _controller.areas = [
      Area(
        weight: _treeOnRight ? 1 - treeWeight : treeWeight,
        minimalWeight: 0.4,
      ),
      Area(
        weight: _treeOnRight ? treeWeight : 1 - treeWeight,
        minimalWeight: 0.4,
      ),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _simulateAuto());
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final seekbar = PreviewSeekbar(
      previewController: _previewController,
      onPauseStateChanged: (paused) => _paused = paused,
      totalPathTime: _simulation?.totalTimeSeconds ?? 0,
      enabled: _simulation != null,
    );
    final tree = Card(
      margin: EdgeInsets.zero,
      elevation: 4,
      color: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: _treeOnRight ? const Radius.circular(12) : Radius.zero,
          topRight: _treeOnRight ? Radius.zero : const Radius.circular(12),
          bottomLeft: _treeOnRight ? const Radius.circular(12) : Radius.zero,
          bottomRight: _treeOnRight ? Radius.zero : const Radius.circular(12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Path2AutoTree(
          auto: widget.auto,
          allPathNames: widget.allPathNames,
          undoStack: widget.undoStack,
          autoRuntime: _simulation?.totalTimeSeconds,
          onPathHovered: (pathName) => setState(() => _hoveredPath = pathName),
          onAutoChanged: () {
            widget.onAutoChanged?.call();
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _simulateAuto());
          },
          onEditPathPressed: widget.onEditPathPressed,
          onSideSwapped: _swapTreeSide,
        ),
      ),
    );

    return Stack(
      children: [
        Center(
          child: InteractiveViewer(
            maxScale: 10,
            child: GestureDetector(
              key: const ValueKey('path2AutoFieldGesture'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              onPanDown: (details) => _panDownPosition = details.localPosition,
              onPanStart: _handlePanStart,
              onPanUpdate: _handlePanUpdate,
              onPanEnd: (_) => _finishStartingPoseDrag(),
              onPanCancel: _finishStartingPoseDrag,
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Stack(
                  children: [
                    widget.fieldImage.getWidget(),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: Path2Painter(
                          colorScheme: colorScheme,
                          paths: widget.autoPaths,
                          fieldImage: widget.fieldImage,
                          prefs: widget.prefs,
                          simple: true,
                          hideOtherPathsOnHover: widget.prefs
                                  .getBool(PrefsKeys.hidePathsOnHover) ??
                              Defaults.hidePathsOnHover,
                          hoveredPath: _hoveredPath,
                          simulation: _simulation,
                          animation: _previewController.view,
                          autoStartingPose: widget.auto.startingPose,
                          showStartingPoseHandles: true,
                          showWaypointRobotPreviews: false,
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
            controller: _controller,
            onWeightChange: () {
              final newWeight = _treeOnRight
                  ? _controller.areas[1].weight
                  : _controller.areas[0].weight;
              widget.prefs.setDouble(
                PrefsKeys.editorTreeWeight,
                newWeight ?? Defaults.editorTreeWeight,
              );
            },
            children: _treeOnRight ? [seekbar, tree] : [tree, seekbar],
          ),
        ),
      ],
    );
  }

  void _swapTreeSide() {
    setState(() {
      _treeOnRight = !_treeOnRight;
      widget.prefs.setBool(PrefsKeys.treeOnRight, _treeOnRight);
      _controller.areas = _controller.areas.reversed.toList();
    });
  }

  void _handlePanStart(DragStartDetails details) {
    final localPosition = _panDownPosition ?? details.localPosition;
    _panDownPosition = null;
    final pointer = Translation2d(
      _xPixelsToMeters(localPosition.dx),
      _yPixelsToMeters(localPosition.dy),
    );
    final pose = widget.auto.startingPose;
    final rotationHandle = _startingRotationHandlePosition(pose);
    final rotationRadius = _pixelsToMeters(
      PathPainterUtil.uiPointSizeToPixels(
        16,
        Path2Painter.scale,
        widget.fieldImage,
      ),
    );
    final positionRadius = _pixelsToMeters(
      PathPainterUtil.uiPointSizeToPixels(
        25,
        Path2Painter.scale,
        widget.fieldImage,
      ),
    );

    if (rotationHandle.getDistance(pointer) < rotationRadius) {
      _startingPoseBeforeDrag = _StartingPoseSnapshot(
        pose,
        widget.auto.startingPoseInitialized,
      );
      _draggingStartingRotation = true;
    } else if (pose.translation.getDistance(pointer) < positionRadius) {
      _startingPoseBeforeDrag = _StartingPoseSnapshot(
        pose,
        widget.auto.startingPoseInitialized,
      );
      _draggingStartingPosition = true;
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_draggingStartingRotation) {
      final x = _xPixelsToMeters(details.localPosition.dx);
      final y = _yPixelsToMeters(details.localPosition.dy);
      final pose = widget.auto.startingPose;
      setState(() {
        widget.auto.startingPose = Pose2d(
          pose.translation,
          Rotation2d.fromComponents(
            x - pose.x,
            y - pose.y,
          ),
        );
      });
      return;
    }
    if (!_draggingStartingPosition) {
      return;
    }

    var targetX = _xPixelsToMeters(
      min(
        88 + widget.fieldImage.defaultSize.width * Path2Painter.scale,
        max(8, details.localPosition.dx),
      ),
    );
    var targetY = _yPixelsToMeters(
      min(
        88 + widget.fieldImage.defaultSize.height * Path2Painter.scale,
        max(8, details.localPosition.dy),
      ),
    );
    final snapSetting = widget.prefs.getBool(PrefsKeys.snapToGuidelines) ??
        Defaults.snapToGuidelines;
    final ctrlHeld = HardwareKeyboard.instance.logicalKeysPressed
            .contains(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed
            .contains(LogicalKeyboardKey.controlRight);
    if (snapSetting ^ ctrlHeld) {
      final waypointPositions = widget.autoPaths
          .expand((path) => path.waypoints)
          .map((waypoint) => waypoint.position);
      num? closestX;
      num? closestY;
      for (final position in waypointPositions) {
        if (closestX == null ||
            (targetX - position.x).abs() < (targetX - closestX).abs()) {
          closestX = position.x;
        }
        if (closestY == null ||
            (targetY - position.y).abs() < (targetY - closestY).abs()) {
          closestY = position.y;
        }
      }
      if (closestX != null && (targetX - closestX).abs() < 0.1) {
        targetX = closestX.toDouble();
      }
      if (closestY != null && (targetY - closestY).abs() < 0.1) {
        targetY = closestY.toDouble();
      }
    }

    final pose = widget.auto.startingPose;
    setState(() {
      widget.auto.startingPose = Pose2d(
        Translation2d(targetX, targetY),
        pose.rotation,
      );
    });
  }

  void _finishStartingPoseDrag() {
    _panDownPosition = null;
    final before = _startingPoseBeforeDrag;
    if (before == null ||
        (!_draggingStartingPosition && !_draggingStartingRotation)) {
      _clearStartingPoseDrag();
      return;
    }
    final after = widget.auto.startingPose;
    _clearStartingPoseDrag();
    if (_samePose(before.pose, after)) {
      return;
    }

    widget.undoStack.add(
      Change<_StartingPoseSnapshot>(
        before,
        () {
          setState(() => widget.auto.setStartingPose(after));
          widget.onAutoChanged?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) => _simulateAuto());
        },
        (oldValue) {
          setState(() {
            widget.auto.startingPose = oldValue.pose;
            widget.auto.startingPoseInitialized = oldValue.initialized;
          });
          widget.onAutoChanged?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) => _simulateAuto());
        },
      ),
    );
  }

  void _clearStartingPoseDrag() {
    _draggingStartingPosition = false;
    _draggingStartingRotation = false;
    _startingPoseBeforeDrag = null;
  }

  Future<void> _simulateAuto() async {
    final generation = ++_simulationGeneration;
    final referencedPathCount = widget.auto.getAllPathNames().length;
    if (widget.auto.hasEmptyPathCommands()) {
      _applySimulationFailure(
        generation,
        const Path2SimulationFailure(
          Path2SimulationFailureKind.missingPath,
          'A path command does not reference a loaded path.',
        ),
      );
      return;
    }
    if (referencedPathCount == 0) {
      _previewController
        ..stop()
        ..reset();
      if (mounted && generation == _simulationGeneration) {
        setState(() => _simulation = null);
      }
      return;
    }
    if (referencedPathCount != widget.autoPaths.length) {
      _applySimulationFailure(
        generation,
        const Path2SimulationFailure(
          Path2SimulationFailureKind.missingPath,
          'One or more referenced paths could not be loaded.',
        ),
      );
      return;
    }

    final previousSimulation = _simulation;
    final previousTime = previousSimulation == null
        ? 0.0
        : _previewController.value * previousSimulation.totalTimeSeconds;
    late final Path2SimulationOutcome outcome;
    try {
      outcome = await Path2Simulator.simulateAutoInBackground(
        widget.autoPaths,
        widget.auto.startingPose,
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
      _applySimulationFailure(generation, outcome.failure!);
      return;
    }

    setState(() => _simulation = result);
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

  void _applySimulationFailure(
    int generation,
    Path2SimulationFailure failure,
  ) {
    if (!mounted || generation != _simulationGeneration) {
      return;
    }
    _previewController
      ..stop()
      ..reset();
    setState(() => _simulation = null);
    Log.warning('Failed to simulate Path2 auto ${widget.auto.name}: $failure');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Unable to simulate ${widget.auto.name}: '
              '${failure.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Translation2d _startingRotationHandlePosition(Pose2d pose) {
    return pose.translation +
        Translation2d(
          _robotSize.height / 2 + _bumperOffset.x,
          _bumperOffset.y,
        ).rotateBy(pose.rotation);
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

  static bool _samePose(Pose2d first, Pose2d second) {
    return first.translation == second.translation &&
        first.rotation == second.rotation;
  }
}

class _StartingPoseSnapshot {
  final Pose2d pose;
  final bool initialized;

  const _StartingPoseSnapshot(this.pose, this.initialized);
}
