import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pathplanner/path2/event_marker.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/simulation/simulation_state.dart';
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/robot_features/feature.dart';
import 'package:pathplanner/util/path_painter_util.dart';
import 'package:pathplanner/util/prefs.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paints the static geometry used by the Path2 path and auto editors.
///
/// Path2 intentionally has no trajectory representation yet, so paths are
/// rendered as straight segments between their waypoints.
class Path2Painter extends CustomPainter {
  final ColorScheme colorScheme;
  final List<path2.Path> paths;
  final FieldImage fieldImage;
  final SharedPreferences prefs;
  final bool simple;
  final bool hideOtherPathsOnHover;
  final String? hoveredPath;
  final int? hoveredWaypoint;
  final int? selectedWaypoint;
  final int? hoveredMarker;
  final int? selectedMarker;
  final int? hoveredConstraintZone;
  final int? selectedConstraintZone;
  final int? hoveredPointZone;
  final int? selectedPointZone;
  final Path2SimulationResult? simulation;
  final Animation<double>? animation;
  final Pose2d? autoStartingPose;
  final bool showStartingPoseHandles;
  final bool showWaypointRobotPreviews;

  late final Size robotSize;
  late final Translation2d bumperOffset;
  late final double robotRadius;
  final List<Feature> robotFeatures = [];

  static double scale = 1;

  Path2Painter({
    required this.colorScheme,
    required this.paths,
    required this.fieldImage,
    required this.prefs,
    this.simple = false,
    this.hideOtherPathsOnHover = false,
    this.hoveredPath,
    this.hoveredWaypoint,
    this.selectedWaypoint,
    this.hoveredMarker,
    this.selectedMarker,
    this.hoveredConstraintZone,
    this.selectedConstraintZone,
    this.hoveredPointZone,
    this.selectedPointZone,
    this.simulation,
    this.animation,
    this.autoStartingPose,
    this.showStartingPoseHandles = false,
    this.showWaypointRobotPreviews = true,
  }) : super(repaint: animation) {
    robotSize = Size(
      prefs.getDouble(PrefsKeys.robotWidth) ?? Defaults.robotWidth,
      prefs.getDouble(PrefsKeys.robotLength) ?? Defaults.robotLength,
    );
    bumperOffset = Translation2d(
      prefs.getDouble(PrefsKeys.bumperOffsetX) ?? Defaults.bumperOffsetX,
      prefs.getDouble(PrefsKeys.bumperOffsetY) ?? Defaults.bumperOffsetY,
    );
    robotRadius = sqrt(
          robotSize.width * robotSize.width +
              robotSize.height * robotSize.height,
        ) /
        2.0;

    for (final featureJson in prefs.getStringList(PrefsKeys.robotFeatures) ??
        Defaults.robotFeatures) {
      try {
        final feature = Feature.fromJson(jsonDecode(featureJson));
        if (feature != null) {
          robotFeatures.add(feature);
        }
      } catch (_) {
        // A malformed optional robot feature should not prevent path editing.
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    scale = size.width / fieldImage.defaultSize.width;
    _paintGrid(canvas, size);

    for (final path in paths) {
      if (hideOtherPathsOnHover &&
          hoveredPath != null &&
          hoveredPath != path.name) {
        continue;
      }

      _paintSegments(path, canvas);
      _paintSelectedZones(path, canvas);
      for (var index = 0; index < path.waypoints.length; index++) {
        _paintWaypoint(path, index, canvas);
      }
      _paintPointZoneTargets(path, canvas);
    }

    if (autoStartingPose != null) {
      _paintAutoStartingPose(canvas, autoStartingPose!);
    }

    // Keep the simulated trace visible without allowing it to cover marker
    // pins at intersections.
    _paintSimulationTrace(canvas);

    // Marker pins must remain visible when paths overlap, so paint them only
    // after every configured path and the simulated trace have been drawn.
    for (final path in paths) {
      if (hideOtherPathsOnHover &&
          hoveredPath != null &&
          hoveredPath != path.name) {
        continue;
      }
      _paintEventMarkers(path, canvas);
    }

    // Simulated marker activations and the live robot remain topmost.
    _paintSimulationPreview(canvas);
  }

  void _paintSimulationTrace(Canvas canvas) {
    final result = simulation;
    if (result == null || result.samples.isEmpty) {
      return;
    }

    final trace = Path();
    for (var index = 0; index < result.samples.length; index++) {
      final point = PathPainterUtil.pointToPixelOffset(
        result.samples[index].pose.translation,
        scale,
        fieldImage,
      );
      if (index == 0) {
        trace.moveTo(point.dx, point.dy);
      } else {
        trace.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      trace,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  void _paintSimulationPreview(Canvas canvas) {
    final result = simulation;
    if (result == null || result.samples.isEmpty) {
      return;
    }

    _paintSimulatedMarkers(canvas, result);

    final animationTime = (animation?.value ?? 0.0) * result.totalTimeSeconds;
    final sample = result.sampleAt(animationTime);
    _paintRobotModules(canvas, sample);
    PathPainterUtil.paintRobotOutline(
      sample.pose,
      fieldImage,
      robotSize,
      bumperOffset,
      scale,
      canvas,
      colorScheme.primary,
      colorScheme.surfaceContainer.withAlpha(210),
      robotFeatures,
      showDetails: prefs.getBool(PrefsKeys.showRobotDetails) ??
          Defaults.showRobotDetails,
    );
  }

  void _paintSimulatedMarkers(
    Canvas canvas,
    Path2SimulationResult result,
  ) {
    for (final activation in result.markerActivations) {
      final color = _eventMarkerColor(
        activation.pathIndex,
        activation.markerIndex,
      );
      final markerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;
      final startTime = activation.startTimeSeconds
          .clamp(0.0, result.totalTimeSeconds)
          .toDouble();
      final start = PathPainterUtil.pointToPixelOffset(
        result.sampleAt(startTime).pose.translation,
        scale,
        fieldImage,
      );
      final endTime = activation.endTimeSeconds;
      if (endTime == null) {
        _paintSimulationMarkerDot(canvas, start, color);
        continue;
      }

      final clampedEnd =
          endTime.clamp(startTime, result.totalTimeSeconds).toDouble();
      final highlightedTrace = Path()..moveTo(start.dx, start.dy);
      for (final sample in result.samples) {
        if (sample.timeSeconds <= startTime ||
            sample.timeSeconds >= clampedEnd) {
          continue;
        }
        final point = PathPainterUtil.pointToPixelOffset(
          sample.pose.translation,
          scale,
          fieldImage,
        );
        highlightedTrace.lineTo(point.dx, point.dy);
      }
      final end = PathPainterUtil.pointToPixelOffset(
        result.sampleAt(clampedEnd).pose.translation,
        scale,
        fieldImage,
      );
      highlightedTrace.lineTo(end.dx, end.dy);
      canvas.drawPath(highlightedTrace, markerPaint);
      _paintSimulationMarkerDot(canvas, start, color);
      _paintSimulationMarkerDot(canvas, end, color);
    }
  }

  void _paintSimulationMarkerDot(
    Canvas canvas,
    Offset position,
    Color color,
  ) {
    canvas.drawCircle(position, 4, Paint()..color = color);
    canvas.drawCircle(
      position,
      4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colorScheme.surfaceContainer,
    );
  }

  void _paintRobotModules(
    Canvas canvas,
    Path2SimulationSample sample,
  ) {
    final locations = <Translation2d>[
      Translation2d(
        prefs.getDouble(PrefsKeys.flModuleX) ?? Defaults.flModuleX,
        prefs.getDouble(PrefsKeys.flModuleY) ?? Defaults.flModuleY,
      ),
      Translation2d(
        prefs.getDouble(PrefsKeys.frModuleX) ?? Defaults.frModuleX,
        prefs.getDouble(PrefsKeys.frModuleY) ?? Defaults.frModuleY,
      ),
      Translation2d(
        prefs.getDouble(PrefsKeys.blModuleX) ?? Defaults.blModuleX,
        prefs.getDouble(PrefsKeys.blModuleY) ?? Defaults.blModuleY,
      ),
      Translation2d(
        prefs.getDouble(PrefsKeys.brModuleX) ?? Defaults.brModuleX,
        prefs.getDouble(PrefsKeys.brModuleY) ?? Defaults.brModuleY,
      ),
    ];
    final moduleCount = min(locations.length, sample.moduleStates.length);
    final modulePoses = <Pose2d>[
      for (var index = 0; index < moduleCount; index++)
        Pose2d(
          sample.pose.translation +
              locations[index].rotateBy(sample.pose.rotation),
          sample.pose.rotation + sample.moduleStates[index].angle,
        ),
    ];

    PathPainterUtil.paintRobotModules(
      modulePoses,
      fieldImage,
      scale,
      canvas,
      colorScheme.primary,
    );
  }

  void _paintAutoStartingPose(Canvas canvas, Pose2d pose) {
    const color = Colors.green;
    PathPainterUtil.paintRobotOutline(
      pose,
      fieldImage,
      robotSize,
      bumperOffset,
      scale,
      canvas,
      color.withAlpha(190),
      colorScheme.surfaceContainer.withAlpha(120),
      robotFeatures,
      showDetails: false,
    );
    if (!showStartingPoseHandles) {
      return;
    }

    final center = PathPainterUtil.pointToPixelOffset(
      pose.translation,
      scale,
      fieldImage,
    );
    final handlePosition = pose.translation +
        Translation2d(
          robotSize.height / 2 + bumperOffset.x,
          bumperOffset.y,
        ).rotateBy(pose.rotation);
    final handle = PathPainterUtil.pointToPixelOffset(
      handlePosition,
      scale,
      fieldImage,
    );
    final anchorRadius =
        PathPainterUtil.uiPointSizeToPixels(20, scale, fieldImage);
    final rotationRadius =
        PathPainterUtil.uiPointSizeToPixels(14, scale, fieldImage);
    canvas.drawCircle(center, anchorRadius, Paint()..color = color);
    canvas.drawCircle(handle, rotationRadius, Paint()..color = color);
    canvas.drawCircle(
      center,
      anchorRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colorScheme.surfaceContainer,
    );
    canvas.drawCircle(
      handle,
      rotationRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colorScheme.surfaceContainer,
    );
  }

  void _paintSegments(path2.Path path, Canvas canvas) {
    if (path.waypoints.length < 2) {
      return;
    }

    final line = Path()
      ..moveTo(
        PathPainterUtil.pointToPixelOffset(
          path.waypoints.first.position,
          scale,
          fieldImage,
        ).dx,
        PathPainterUtil.pointToPixelOffset(
          path.waypoints.first.position,
          scale,
          fieldImage,
        ).dy,
      );

    for (final waypoint in path.waypoints.skip(1)) {
      final position = PathPainterUtil.pointToPixelOffset(
        waypoint.position,
        scale,
        fieldImage,
      );
      line.lineTo(position.dx, position.dy);
    }

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.grey.shade600,
    );
  }

  void _paintSelectedZones(path2.Path path, Canvas canvas) {
    if (_isValidIndex(selectedConstraintZone, path.constraintZones.length)) {
      final zone = path.constraintZones[selectedConstraintZone!];
      _paintPathRange(
        canvas,
        path,
        zone.minWaypointRelativePos,
        zone.maxWaypointRelativePos,
        Colors.orange,
      );
    }
    if (_isValidIndex(
          hoveredConstraintZone,
          path.constraintZones.length,
        ) &&
        hoveredConstraintZone != selectedConstraintZone &&
        hoveredConstraintZone != null) {
      final zone = path.constraintZones[hoveredConstraintZone!];
      _paintPathRange(
        canvas,
        path,
        zone.minWaypointRelativePos,
        zone.maxWaypointRelativePos,
        Colors.deepPurpleAccent,
      );
    }
    if (_isValidIndex(selectedPointZone, path.pointTowardsZones.length)) {
      final zone = path.pointTowardsZones[selectedPointZone!];
      _paintPathRange(
        canvas,
        path,
        zone.minWaypointRelativePos,
        zone.maxWaypointRelativePos,
        Colors.orange,
      );
    }
    if (_isValidIndex(hoveredPointZone, path.pointTowardsZones.length) &&
        hoveredPointZone != selectedPointZone &&
        hoveredPointZone != null) {
      final zone = path.pointTowardsZones[hoveredPointZone!];
      _paintPathRange(
        canvas,
        path,
        zone.minWaypointRelativePos,
        zone.maxWaypointRelativePos,
        Colors.deepPurpleAccent,
      );
    }
    if (_isValidIndex(selectedMarker, path.eventMarkers.length) &&
        path.eventMarkers[selectedMarker!].isZoned) {
      final marker = path.eventMarkers[selectedMarker!];
      _paintPathRange(
        canvas,
        path,
        marker.waypointRelativePos,
        marker.endWaypointRelativePos!,
        Colors.orange,
      );
    }
    if (_isValidIndex(hoveredMarker, path.eventMarkers.length) &&
        hoveredMarker != selectedMarker &&
        hoveredMarker != null &&
        path.eventMarkers[hoveredMarker!].isZoned) {
      final marker = path.eventMarkers[hoveredMarker!];
      _paintPathRange(
        canvas,
        path,
        marker.waypointRelativePos,
        marker.endWaypointRelativePos!,
        Colors.deepPurpleAccent,
      );
    }
  }

  void _paintPathRange(
    Canvas canvas,
    path2.Path path,
    num startPosition,
    num endPosition,
    Color color,
  ) {
    final start = startPosition.clamp(0, path.waypoints.length - 1).toDouble();
    final end = endPosition.clamp(start, path.waypoints.length - 1).toDouble();
    final range = Path();
    final startOffset = PathPainterUtil.pointToPixelOffset(
      path.samplePath(start),
      scale,
      fieldImage,
    );
    range.moveTo(startOffset.dx, startOffset.dy);

    for (var waypointIndex = start.floor() + 1;
        waypointIndex <= end.floor() && waypointIndex < path.waypoints.length;
        waypointIndex++) {
      final waypointOffset = PathPainterUtil.pointToPixelOffset(
        path.waypoints[waypointIndex].position,
        scale,
        fieldImage,
      );
      range.lineTo(waypointOffset.dx, waypointOffset.dy);
    }

    final endOffset = PathPainterUtil.pointToPixelOffset(
      path.samplePath(end),
      scale,
      fieldImage,
    );
    range.lineTo(endOffset.dx, endOffset.dy);
    canvas.drawPath(
      range,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  void _paintEventMarkers(path2.Path path, Canvas canvas) {
    for (var index = 0; index < path.eventMarkers.length; index++) {
      var color = Color(eventMarkerColorForIndex(index));
      if (!simple && selectedMarker == index) {
        color = Colors.orange;
      } else if (!simple && hoveredMarker == index) {
        color = Colors.deepPurpleAccent;
      }
      PathPainterUtil.paintMarker(
        canvas,
        PathPainterUtil.pointToPixelOffset(
          path.samplePath(path.eventMarkers[index].waypointRelativePos),
          scale,
          fieldImage,
        ),
        color,
        colorScheme.surfaceContainer,
      );
    }
  }

  Color _eventMarkerColor(int pathIndex, int markerIndex) {
    if (pathIndex < 0 || pathIndex >= paths.length) {
      return Colors.blue.shade800;
    }
    final markers = paths[pathIndex].eventMarkers;
    if (markerIndex < 0 || markerIndex >= markers.length) {
      return Colors.blue.shade800;
    }
    if (!simple && selectedMarker == markerIndex) {
      return Colors.orange;
    }
    if (!simple && hoveredMarker == markerIndex) {
      return Colors.deepPurpleAccent;
    }
    return Color(eventMarkerColorForIndex(markerIndex));
  }

  void _paintPointZoneTargets(path2.Path path, Canvas canvas) {
    if (_isValidIndex(selectedPointZone, path.pointTowardsZones.length)) {
      _paintPointZoneTarget(
        canvas,
        path.pointTowardsZones[selectedPointZone!].fieldPosition,
        Colors.orange,
      );
    }
    if (_isValidIndex(hoveredPointZone, path.pointTowardsZones.length) &&
        hoveredPointZone != selectedPointZone &&
        hoveredPointZone != null) {
      _paintPointZoneTarget(
        canvas,
        path.pointTowardsZones[hoveredPointZone!].fieldPosition,
        Colors.deepPurpleAccent,
      );
    }
  }

  void _paintPointZoneTarget(
    Canvas canvas,
    Translation2d position,
    Color color,
  ) {
    final center =
        PathPainterUtil.pointToPixelOffset(position, scale, fieldImage);
    canvas.drawCircle(
      center,
      PathPainterUtil.uiPointSizeToPixels(25, scale, fieldImage),
      Paint()..color = color,
    );
    canvas.drawCircle(
      center,
      PathPainterUtil.uiPointSizeToPixels(40, scale, fieldImage),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );
  }

  void _paintWaypoint(path2.Path path, int index, Canvas canvas) {
    final waypoint = path.waypoints[index];
    final center = PathPainterUtil.pointToPixelOffset(
      waypoint.position,
      scale,
      fieldImage,
    );
    final waypointColor = _waypointColor(path, index);

    if (waypoint is PoseWaypoint && showWaypointRobotPreviews) {
      PathPainterUtil.paintRobotOutline(
        Pose2d(waypoint.position, waypoint.rotation),
        fieldImage,
        robotSize,
        bumperOffset,
        scale,
        canvas,
        waypointColor.withAlpha(160),
        colorScheme.surfaceContainer,
        robotFeatures,
        showDetails: prefs.getBool(PrefsKeys.showRobotDetails) ??
            Defaults.showRobotDetails,
      );
    } else if (waypoint is! PoseWaypoint) {
      canvas.drawCircle(
        center,
        PathPainterUtil.metersToPixels(robotRadius, scale, fieldImage),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = waypointColor.withAlpha(160),
      );
    }

    final anchorRadius =
        PathPainterUtil.uiPointSizeToPixels(25, scale, fieldImage);
    canvas.drawCircle(
      center,
      anchorRadius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = waypointColor,
    );
    canvas.drawCircle(
      center,
      anchorRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colorScheme.surfaceContainer,
    );
  }

  Color _waypointColor(path2.Path path, int index) {
    if (!simple && index == selectedWaypoint) {
      return Colors.orange;
    }
    if (!simple && index == hoveredWaypoint) {
      return Colors.deepPurpleAccent;
    }
    if (simple && hoveredPath == path.name) {
      return Colors.orange;
    }
    if (index == 0) {
      return Colors.green;
    }
    if (index == path.waypoints.length - 1) {
      return Colors.red;
    }
    return colorScheme.secondary;
  }

  static bool _isValidIndex(int? index, int length) =>
      index != null && index >= 0 && index < length;

  void _paintGrid(Canvas canvas, Size size) {
    if (!(prefs.getBool(PrefsKeys.showGrid) ?? Defaults.showGrid)) {
      return;
    }

    final paint = Paint()
      ..color = colorScheme.secondary.withAlpha(50)
      ..strokeWidth = 1;
    final spacing = PathPainterUtil.metersToPixels(0.5, scale, fieldImage);

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant Path2Painter oldDelegate) => true;
}
