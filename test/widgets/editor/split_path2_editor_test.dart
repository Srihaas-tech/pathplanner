import 'package:file/memory.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/path2/constraints_zone.dart';
import 'package:pathplanner/path2/event_marker.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/point_towards_zone.dart';
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/util/path_painter_util.dart';
import 'package:pathplanner/util/prefs.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/widgets/editor/path2_painter.dart';
import 'package:pathplanner/widgets/editor/preview_seekbar.dart';
import 'package:pathplanner/widgets/editor/split_path2_editor.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_tree.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undo/undo.dart';

void main() {
  late path2.Path path;
  late SharedPreferences prefs;
  late ChangeStack undoStack;
  late FieldImage fieldImage;

  setUp(() async {
    final fs = MemoryFileSystem();
    fs.directory('/paths').createSync(recursive: true);
    path = path2.Path.defaultPath(
      name: 'Path2',
      pathDir: '/paths',
      fs: fs,
    );
    undoStack = ChangeStack();
    fieldImage = FieldImage.official(OfficialField.chargedUp);
    SharedPreferences.setMockInitialValues({
      PrefsKeys.treeOnRight: true,
      PrefsKeys.robotWidth: 1.0,
      PrefsKeys.robotLength: 0.8,
      PrefsKeys.showRobotDetails: true,
      PrefsKeys.showGrid: true,
      PrefsKeys.snapToGuidelines: true,
    });
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitPath2Editor(
            prefs: prefs,
            path: path,
            fieldImage: fieldImage,
            undoStack: undoStack,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Path2 painter, runtime, and active preview',
      (tester) async {
    path.addWaypoint(const Translation2d(6, 5));
    await pumpEditor(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    final pathPaint = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((paint) => paint.painter is Path2Painter);
    expect(pathPaint, hasLength(1));
    expect(find.byType(Path2Tree), findsOneWidget);

    final seekbar = tester.widget<PreviewSeekbar>(find.byType(PreviewSeekbar));
    expect(seekbar.enabled, isTrue);
    expect(seekbar.totalPathTime, greaterThan(0));
    expect(seekbar.previewController.isAnimating, isTrue);
    expect(pathPaint.single.painter, isA<Path2Painter>());
    expect(
      (pathPaint.single.painter as Path2Painter).simulation,
      isNotNull,
    );

    expect(find.text('Rotation Targets'), findsNothing);
    expect(find.text('Constraint Zones'), findsOneWidget);
    expect(find.text('Event Markers'), findsOneWidget);
    expect(find.text('Point Towards Zones'), findsOneWidget);
  });

  testWidgets('swaps the waypoint tree side', (tester) async {
    await pumpEditor(tester);

    final swapButton = find.byTooltip('Move to Other Side');
    await tester.tap(swapButton);
    await tester.pump();
    expect(prefs.getBool(PrefsKeys.treeOnRight), isFalse);

    await tester.tap(swapButton);
    await tester.pump();
    expect(prefs.getBool(PrefsKeys.treeOnRight), isTrue);
  });

  testWidgets('double click appends a translation waypoint and supports undo',
      (tester) async {
    await pumpEditor(tester);
    final location = PathPainterUtil.pointToPixelOffset(
          const Translation2d(1, 1),
          Path2Painter.scale,
          fieldImage,
        ) +
        const Offset(48, 48) +
        const Offset(0, 23);

    await tester.tapAt(location);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(location);
    await tester.pumpAndSettle();

    expect(path.waypoints, hasLength(3));
    expect(path.waypoints.last, isA<TranslationWaypoint>());
    expect(path.waypoints.last.position.x, closeTo(1, 0.05));
    expect(path.waypoints.last.position.y, closeTo(1, 0.05));

    undoStack.undo();
    await tester.pumpAndSettle();
    expect(path.waypoints, hasLength(2));
  });

  testWidgets('sidebar midpoint insertion remains undoable after tree rebuild',
      (tester) async {
    path
      ..waypointsExpanded = true
      ..eventMarkers = [
        EventMarker(
          waypointRelativePos: 0.25,
          endWaypointRelativePos: 0.75,
        ),
      ]
      ..constraintZones = [
        ConstraintsZone(
          minWaypointRelativePos: 0.1,
          maxWaypointRelativePos: 0.9,
        ),
      ]
      ..pointTowardsZones = [
        PointTowardsZone(
          minWaypointRelativePos: 0.2,
          maxWaypointRelativePos: 0.8,
        ),
      ];
    await pumpEditor(tester);

    await tester.tap(find.text('Start Point'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create New Waypoint After'));
    await tester.pumpAndSettle();

    expect(path.waypoints, hasLength(3));
    expect(path.waypoints[1], isA<TranslationWaypoint>());
    expect(path.eventMarkers.single.waypointRelativePos, 0.5);
    expect(path.eventMarkers.single.endWaypointRelativePos, 1.5);
    expect(path.constraintZones.single.minWaypointRelativePos, 0.2);
    expect(path.constraintZones.single.maxWaypointRelativePos, 1.8);
    expect(path.pointTowardsZones.single.minWaypointRelativePos, 0.4);
    expect(path.pointTowardsZones.single.maxWaypointRelativePos, 1.6);

    undoStack.undo();
    await tester.pumpAndSettle();
    expect(path.waypoints, hasLength(2));
    expect(path.eventMarkers.single.waypointRelativePos, 0.25);
    expect(path.eventMarkers.single.endWaypointRelativePos, 0.75);
    expect(path.constraintZones.single.minWaypointRelativePos, 0.1);
    expect(path.constraintZones.single.maxWaypointRelativePos, 0.9);
    expect(path.pointTowardsZones.single.minWaypointRelativePos, 0.2);
    expect(path.pointTowardsZones.single.maxWaypointRelativePos, 0.8);

    undoStack.redo();
    await tester.pumpAndSettle();
    expect(path.waypoints, hasLength(3));
    expect(path.eventMarkers.single.endWaypointRelativePos, 1.5);
    expect(path.constraintZones.single.maxWaypointRelativePos, 1.8);
    expect(path.pointTowardsZones.single.maxWaypointRelativePos, 1.6);
  });

  testWidgets('drags an anchor and records one undo change', (tester) async {
    await pumpEditor(tester);
    final start = path.waypoints.last.position;
    final location = PathPainterUtil.pointToPixelOffset(
          start,
          Path2Painter.scale,
          fieldImage,
        ) +
        const Offset(48, 48) +
        const Offset(0, 23);
    final meterPixels = PathPainterUtil.metersToPixels(
      1,
      Path2Painter.scale,
      fieldImage,
    );

    final gesture = await tester.startGesture(
      location,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 0; i < meterPixels.ceil(); i++) {
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(path.waypoints.last.position.x, closeTo(start.x + 1, 0.05));
    expect(path.waypoints.last.position.y, closeTo(start.y, 0.05));
    expect(undoStack.canUndo, isTrue);

    undoStack.undo();
    await tester.pumpAndSettle();
    expect(path.waypoints.last.position.x, closeTo(start.x, 0.05));
    expect(path.waypoints.last.position.y, closeTo(start.y, 0.05));
  });

  testWidgets('drags a pose heading handle and supports undo', (tester) async {
    await pumpEditor(tester);
    final waypoint = path.waypoints.first as PoseWaypoint;
    final originalRotation = waypoint.rotation;
    final handlePosition = waypoint.position + const Translation2d(0.4, 0);
    final targetPosition = waypoint.position + const Translation2d(0, 1);
    final painterFinder = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is Path2Painter,
    );
    final editorOffset = tester.getTopLeft(painterFinder);
    final handlePixels = PathPainterUtil.pointToPixelOffset(
          handlePosition,
          Path2Painter.scale,
          fieldImage,
        ) +
        editorOffset;
    final targetPixels = PathPainterUtil.pointToPixelOffset(
          targetPosition,
          Path2Painter.scale,
          fieldImage,
        ) +
        editorOffset;

    final gesture = await tester.startGesture(
      handlePixels,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var step = 1; step <= 10; step++) {
      await gesture.moveTo(
        Offset.lerp(handlePixels, targetPixels, step / 10)!,
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(waypoint.rotation.degrees, closeTo(90, 1));
    expect(undoStack.canUndo, isTrue);

    undoStack.undo();
    await tester.pumpAndSettle();
    expect(waypoint.rotation.degrees, closeTo(originalRotation.degrees, 0.01));
  });

  testWidgets('drags a selected point-towards target and supports undo',
      (tester) async {
    const originalTarget = Translation2d(3, 4);
    path
      ..pointTowardsZonesExpanded = true
      ..pointTowardsZones = [
        PointTowardsZone(
          name: 'Aim Target',
          fieldPosition: originalTarget,
        ),
      ];
    await pumpEditor(tester);

    tester
        .widget<Path2Tree>(find.byType(Path2Tree))
        .onPointZoneSelected
        ?.call(0);
    await tester.pump();

    final painterFinder = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is Path2Painter,
    );
    final editorOffset = tester.getTopLeft(painterFinder);
    final targetPixels = PathPainterUtil.pointToPixelOffset(
          originalTarget,
          Path2Painter.scale,
          fieldImage,
        ) +
        editorOffset;
    expect(
      (tester.widget<CustomPaint>(painterFinder).painter as Path2Painter)
          .selectedPointZone,
      0,
    );
    final meterPixels = PathPainterUtil.metersToPixels(
      1,
      Path2Painter.scale,
      fieldImage,
    );

    final gesture = await tester.startGesture(
      targetPixels,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var step = 1; step <= 10; step++) {
      await gesture.moveTo(
        targetPixels + Offset(meterPixels * step / 10, 0),
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(path.pointTowardsZones.single.fieldPosition.x,
        closeTo(originalTarget.x + 1, 0.05));
    expect(path.pointTowardsZones.single.fieldPosition.y,
        closeTo(originalTarget.y, 0.05));
    expect(undoStack.canUndo, isTrue);

    undoStack.undo();
    await tester.pumpAndSettle();
    expect(path.pointTowardsZones.single.fieldPosition, originalTarget);
  });

  testWidgets('deletes down to one waypoint but never zero', (tester) async {
    path
      ..waypointsExpanded = true
      ..eventMarkers = [
        EventMarker(
          waypointRelativePos: 0.25,
          endWaypointRelativePos: 0.75,
        ),
      ]
      ..constraintZones = [
        ConstraintsZone(
          minWaypointRelativePos: 0.1,
          maxWaypointRelativePos: 0.9,
        ),
      ]
      ..pointTowardsZones = [
        PointTowardsZone(
          minWaypointRelativePos: 0.2,
          maxWaypointRelativePos: 0.8,
        ),
      ];
    await pumpEditor(tester);

    await tester.tap(find.byTooltip('Delete Waypoint').first);
    await tester.pumpAndSettle();

    expect(path.waypoints, hasLength(1));
    expect(find.byTooltip('Delete Waypoint'), findsNothing);
    expect(path.eventMarkers.single.waypointRelativePos, 0);
    expect(path.eventMarkers.single.endWaypointRelativePos, 0);
    expect(path.constraintZones.single.minWaypointRelativePos, 0);
    expect(path.constraintZones.single.maxWaypointRelativePos, 0);
    expect(path.pointTowardsZones.single.minWaypointRelativePos, 0);
    expect(path.pointTowardsZones.single.maxWaypointRelativePos, 0);

    undoStack.undo();
    await tester.pumpAndSettle();
    expect(path.waypoints, hasLength(2));
    expect(path.eventMarkers.single.waypointRelativePos, 0.25);
    expect(path.eventMarkers.single.endWaypointRelativePos, 0.75);
    expect(path.constraintZones.single.minWaypointRelativePos, 0.1);
    expect(path.constraintZones.single.maxWaypointRelativePos, 0.9);
    expect(path.pointTowardsZones.single.minWaypointRelativePos, 0.2);
    expect(path.pointTowardsZones.single.maxWaypointRelativePos, 0.8);

    undoStack.redo();
    await tester.pumpAndSettle();
    expect(path.waypoints, hasLength(1));
    expect(path.eventMarkers.single.endWaypointRelativePos, 0);
    expect(path.constraintZones.single.maxWaypointRelativePos, 0);
    expect(path.pointTowardsZones.single.maxWaypointRelativePos, 0);
  });
}
