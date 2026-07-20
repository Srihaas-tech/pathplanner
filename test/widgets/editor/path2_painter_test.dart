import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/path2/constraints_zone.dart';
import 'package:pathplanner/path2/event_marker.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/point_towards_zone.dart';
import 'package:pathplanner/path2/simulation/simulation_state.dart';
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/util/path_painter_util.dart';
import 'package:pathplanner/util/prefs.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/widgets/editor/path2_painter.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FieldImage fieldImage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.showGrid: false,
      PrefsKeys.robotWidth: 0.9,
      PrefsKeys.robotLength: 0.9,
    });
    prefs = await SharedPreferences.getInstance();
    fieldImage = FieldImage.official(OfficialField.chargedUp);
  });

  path2.Path path({
    String name = 'render',
    List<Waypoint>? waypoints,
    List<EventMarker>? markers,
    List<ConstraintsZone>? constraintZones,
    List<PointTowardsZone>? pointZones,
  }) {
    return path2.Path(
      name: name,
      waypoints: waypoints ??
          [
            TranslationWaypoint(position: const Translation2d(1, 4)),
            TranslationWaypoint(position: const Translation2d(4, 4)),
          ],
      eventMarkers: markers,
      constraintZones: constraintZones,
      pointTowardsZones: pointZones,
      fs: MemoryFileSystem(),
      pathDir: '/paths',
    );
  }

  Path2SimulationSample sample(double time, double x) {
    return Path2SimulationSample(
      timeSeconds: time,
      state: Path2SimulationState.atRest(
        Pose2d(Translation2d(x, 4), const Rotation2d()),
      ),
    );
  }

  Path2Painter painter(
    path2.Path renderedPath, {
    List<path2.Path>? renderedPaths,
    Path2SimulationResult? simulation,
    bool simple = true,
    int? selectedMarker,
    int? hoveredMarker,
  }) {
    return Path2Painter(
      colorScheme: const ColorScheme.light(),
      paths: renderedPaths ?? [renderedPath],
      fieldImage: fieldImage,
      prefs: prefs,
      simple: simple,
      selectedMarker: selectedMarker,
      hoveredMarker: hoveredMarker,
      simulation: simulation,
      showWaypointRobotPreviews: false,
    );
  }

  test('renders static marker at its sampled position but not unselected zones',
      () async {
    final baseline = await _render(painter(path()));
    final zonesOnly = await _render(
      painter(
        path(
          constraintZones: [
            ConstraintsZone(
              minWaypointRelativePos: 0.2,
              maxWaypointRelativePos: 0.8,
            ),
          ],
          pointZones: [PointTowardsZone()],
        ),
      ),
    );
    expect(const ListEquality<int>().equals(baseline.bytes, zonesOnly.bytes),
        isTrue);

    final markerPath = path(
      markers: [EventMarker(waypointRelativePos: 0.5)],
    );
    final withMarker = await _render(painter(markerPath));
    final expectedPosition = PathPainterUtil.pointToPixelOffset(
      markerPath.samplePath(0.5),
      Path2Painter.scale,
      fieldImage,
    );

    expect(
      _hasDifferenceNear(baseline, withMarker, expectedPosition, radius: 24),
      isTrue,
    );
  });

  test('renders exact trigger dots and zoned trace endpoints', () async {
    final samples = [
      sample(0, 1),
      sample(0.02, 2),
      sample(0.04, 3),
      sample(0.06, 4),
    ];
    final baselineResult = Path2SimulationResult(samples);
    final pointResult = Path2SimulationResult(
      samples,
      markerActivations: const [
        Path2SimulationMarkerActivation(
          pathIndex: 0,
          markerIndex: 0,
          startTimeSeconds: 0.02,
        ),
      ],
    );
    final zonedResult = Path2SimulationResult(
      samples,
      markerActivations: const [
        Path2SimulationMarkerActivation(
          pathIndex: 0,
          markerIndex: 0,
          startTimeSeconds: 0.02,
          endTimeSeconds: 0.04,
        ),
      ],
    );

    final renderedPath = path(
      markers: [
        EventMarker(),
      ],
    );
    final baseline = await _render(
      painter(renderedPath, simulation: baselineResult),
    );
    final point = await _render(
      painter(renderedPath, simulation: pointResult),
    );
    final zoned = await _render(
      painter(renderedPath, simulation: zonedResult),
    );
    final start = PathPainterUtil.pointToPixelOffset(
      const Translation2d(2, 4),
      Path2Painter.scale,
      fieldImage,
    );
    final end = PathPainterUtil.pointToPixelOffset(
      const Translation2d(3, 4),
      Path2Painter.scale,
      fieldImage,
    );
    final midpoint = Offset.lerp(start, end, 0.5)!;

    expect(_hasDifferenceNear(baseline, point, start, radius: 5), isTrue);
    expect(_hasDifferenceNear(baseline, point, end, radius: 5), isFalse);
    expect(_hasDifferenceNear(baseline, zoned, start, radius: 5), isTrue);
    expect(_hasDifferenceNear(baseline, zoned, midpoint, radius: 4), isTrue);
    expect(_hasDifferenceNear(baseline, zoned, end, radius: 5), isTrue);
  });

  test('uses runtime marker colors with selection and hover overrides',
      () async {
    final renderedPath = path(
      markers: [
        EventMarker(waypointRelativePos: 0.5),
      ],
    );
    final result = Path2SimulationResult(
      [sample(0, 1), sample(0.02, 2), sample(0.04, 4)],
      markerActivations: const [
        Path2SimulationMarkerActivation(
          pathIndex: 0,
          markerIndex: 0,
          startTimeSeconds: 0.02,
        ),
      ],
    );
    final triggerPosition = PathPainterUtil.pointToPixelOffset(
      const Translation2d(2, 4),
      Path2Painter.scale,
      fieldImage,
    );
    final markerPosition = PathPainterUtil.pointToPixelOffset(
      renderedPath.samplePath(0.5),
      Path2Painter.scale,
      fieldImage,
    );

    final normal = await _render(
      painter(renderedPath, simulation: result),
    );
    expect(_pixel(normal, triggerPosition), [0x87, 0x42, 0x42, 0xFF]);
    expect(
      _containsPixelNear(normal, markerPosition, [0x87, 0x42, 0x42, 0xFF]),
      isTrue,
    );

    final selected = await _render(
      painter(
        renderedPath,
        simulation: result,
        simple: false,
        selectedMarker: 0,
      ),
    );
    expect(_pixel(selected, triggerPosition), [0xFF, 0x98, 0x00, 0xFF]);
    expect(
      _containsPixelNear(
        selected,
        markerPosition,
        [0xFF, 0x98, 0x00, 0xFF],
      ),
      isTrue,
    );

    final hovered = await _render(
      painter(
        renderedPath,
        simulation: result,
        simple: false,
        hoveredMarker: 0,
      ),
    );
    expect(_pixel(hovered, triggerPosition), [0x7C, 0x4D, 0xFF, 0xFF]);
    expect(
      _containsPixelNear(
        hovered,
        markerPosition,
        [0x7C, 0x4D, 0xFF, 0xFF],
      ),
      isTrue,
    );
  });

  test('markers paint above paths and the simulated trace', () async {
    final markerPath = path(
      name: 'marker',
      markers: [EventMarker(waypointRelativePos: 0.5)],
    );
    final crossingPath = path(
      name: 'crossing',
      waypoints: [
        TranslationWaypoint(position: const Translation2d(2.5, 3)),
        TranslationWaypoint(position: const Translation2d(2.5, 5)),
      ],
    );
    final noMarker = await _render(painter(path()));
    final markerOnly = await _render(painter(markerPath));
    final markerAbovePath = await _render(
      painter(markerPath, renderedPaths: [markerPath, crossingPath]),
    );
    final markerPosition = PathPainterUtil.pointToPixelOffset(
      markerPath.samplePath(0.5),
      Path2Painter.scale,
      fieldImage,
    );

    final opaqueMarkerPosition = _findOpaqueDifferenceOnVerticalLine(
      noMarker,
      markerOnly,
      markerPosition,
      above: 27,
    );
    expect(_pixel(markerAbovePath, opaqueMarkerPosition),
        _pixel(markerOnly, opaqueMarkerPosition));

    final simulation = Path2SimulationResult([
      sample(0, 1),
      sample(0.02, 4),
    ]);
    final simulationOnly = await _render(
      painter(path(), simulation: simulation),
    );
    final markerAboveSimulation = await _render(
      painter(markerPath, simulation: simulation),
    );
    final markerTraceOverlap = _findDifferenceNearHorizontalLine(
      noMarker,
      markerOnly,
      markerPosition,
      horizontalRadius: 17,
      verticalRadius: 2,
    );
    expect(
      _pixel(markerAboveSimulation, markerTraceOverlap),
      isNot(_pixel(simulationOnly, markerTraceOverlap)),
    );
  });
}

class _RenderedImage {
  final Uint8List bytes;
  final int width;
  final int height;

  const _RenderedImage(this.bytes, this.width, this.height);
}

List<int> _pixel(_RenderedImage image, Offset position) {
  final x = position.dx.round().clamp(0, image.width - 1);
  final y = position.dy.round().clamp(0, image.height - 1);
  final offset = (y * image.width + x) * 4;
  return image.bytes.sublist(offset, offset + 4);
}

bool _containsPixelNear(
  _RenderedImage image,
  Offset position,
  List<int> color,
) {
  for (var yOffset = -27; yOffset <= 4; yOffset++) {
    for (var xOffset = -18; xOffset <= 18; xOffset++) {
      if (const ListEquality<int>().equals(
        _pixel(
          image,
          position + Offset(xOffset.toDouble(), yOffset.toDouble()),
        ),
        color,
      )) {
        return true;
      }
    }
  }
  return false;
}

Offset _findOpaqueDifferenceOnVerticalLine(
  _RenderedImage baseline,
  _RenderedImage rendered,
  Offset position, {
  required int above,
}) {
  for (var yOffset = above; yOffset >= 0; yOffset--) {
    final candidate = Offset(position.dx, position.dy - yOffset);
    final baselinePixel = _pixel(baseline, candidate);
    final renderedPixel = _pixel(rendered, candidate);
    if (renderedPixel[3] == 255 &&
        !const ListEquality<int>().equals(baselinePixel, renderedPixel)) {
      return candidate;
    }
  }
  fail('No opaque marker pixel found on the overlapping path');
}

Offset _findDifferenceNearHorizontalLine(
  _RenderedImage baseline,
  _RenderedImage rendered,
  Offset position, {
  required int horizontalRadius,
  required int verticalRadius,
}) {
  Offset? best;
  var bestAlpha = -1;
  for (var yOffset = -verticalRadius; yOffset <= verticalRadius; yOffset++) {
    for (var xOffset = -horizontalRadius;
        xOffset <= horizontalRadius;
        xOffset++) {
      final candidate =
          position + Offset(xOffset.toDouble(), yOffset.toDouble());
      final baselinePixel = _pixel(baseline, candidate);
      final renderedPixel = _pixel(rendered, candidate);
      if (!const ListEquality<int>().equals(baselinePixel, renderedPixel) &&
          renderedPixel[3] > bestAlpha) {
        best = candidate;
        bestAlpha = renderedPixel[3];
      }
    }
  }
  return best ??
      fail(
          'No marker pixel found where the marker crosses the simulated trace');
}

Future<_RenderedImage> _render(Path2Painter painter) async {
  const width = 600;
  final height = (painter.fieldImage.defaultSize.height /
          painter.fieldImage.defaultSize.width *
          width)
      .round();
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return _RenderedImage(data!.buffer.asUint8List(), width, height);
}

bool _hasDifferenceNear(
  _RenderedImage before,
  _RenderedImage after,
  Offset center, {
  required int radius,
}) {
  expect(after.width, before.width);
  expect(after.height, before.height);
  final minX = (center.dx.floor() - radius).clamp(0, before.width - 1);
  final maxX = (center.dx.ceil() + radius).clamp(0, before.width - 1);
  final minY = (center.dy.floor() - radius).clamp(0, before.height - 1);
  final maxY = (center.dy.ceil() + radius).clamp(0, before.height - 1);

  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final offset = (y * before.width + x) * 4;
      for (var channel = 0; channel < 4; channel++) {
        if (before.bytes[offset + channel] != after.bytes[offset + channel]) {
          return true;
        }
      }
    }
  }
  return false;
}
