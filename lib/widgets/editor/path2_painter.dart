import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pathplanner/path2/path.dart' as path2;
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
  }) {
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
      for (var index = 0; index < path.waypoints.length; index++) {
        _paintWaypoint(path, index, canvas);
      }
    }
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

  void _paintWaypoint(path2.Path path, int index, Canvas canvas) {
    final waypoint = path.waypoints[index];
    final center = PathPainterUtil.pointToPixelOffset(
      waypoint.position,
      scale,
      fieldImage,
    );
    final waypointColor = _waypointColor(path, index);

    if (waypoint is PoseWaypoint) {
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
    } else {
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
