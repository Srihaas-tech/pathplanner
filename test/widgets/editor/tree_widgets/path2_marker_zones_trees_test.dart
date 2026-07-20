import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/path2/constraints_zone.dart';
import 'package:pathplanner/path2/event_marker.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/point_towards_zone.dart';
import 'package:pathplanner/services/project_event_registry.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_constraint_zones_tree.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_event_markers_tree.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_point_towards_zones_tree.dart';
import 'package:pathplanner/widgets/number_text_field.dart';
import 'package:undo/undo.dart';

void main() {
  late path2.Path path;
  late ChangeStack undoStack;
  late int simulatedChanges;
  late int nonSimulatedChanges;

  setUp(() {
    ProjectEventRegistry.clear();
    path = path2.Path.defaultPath(
      name: 'Path2',
      pathDir: '/paths',
      fs: MemoryFileSystem(),
    );
    undoStack = ChangeStack();
    simulatedChanges = 0;
    nonSimulatedChanges = 0;
  });

  tearDown(ProjectEventRegistry.clear);

  Future<void> pumpTree(WidgetTester tester, Widget tree) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 900, child: tree),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('event marker edits use the correct callback and are undoable',
      (tester) async {
    ProjectEventRegistry.events.addAll({'Collect', 'Shoot'});
    path
      ..eventMarkersExpanded = true
      ..eventMarkers = [
        EventMarker(name: 'Shoot', waypointRelativePos: 0.25),
      ];

    await pumpTree(
      tester,
      Path2EventMarkersTree(
        path: path,
        undoStack: undoStack,
        initiallySelectedMarker: 0,
        onPathChanged: () => simulatedChanges++,
        onPathChangedNoSim: () => nonSimulatedChanges++,
      ),
    );

    expect(find.text('Event Markers'), findsOneWidget);
    expect(find.widgetWithText(NumberTextField, 'Position'), findsOneWidget);

    final dropdown = tester.widget<DropdownButton2<String>>(
      find.byType(DropdownButton2<String>),
    );
    dropdown.onChanged?.call('Collect');
    await tester.pump();

    expect(path.eventMarkers.single.name, 'Collect');
    expect(nonSimulatedChanges, 1);
    expect(simulatedChanges, 0);

    undoStack.undo();
    await tester.pump();
    expect(path.eventMarkers.single.name, 'Shoot');
    expect(nonSimulatedChanges, 2);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(path.eventMarkers.single.endWaypointRelativePos, 0.25);
    expect(simulatedChanges, 1);

    undoStack.undo();
    await tester.pump();
    expect(path.eventMarkers.single.endWaypointRelativePos, isNull);
    expect(simulatedChanges, 2);
  });

  testWidgets('event marker add is undoable', (tester) async {
    await pumpTree(
      tester,
      Path2EventMarkersTree(
        path: path,
        undoStack: undoStack,
        onPathChanged: () => simulatedChanges++,
      ),
    );

    await tester.tap(find.byTooltip('Add New Event Marker'));
    await tester.pump();
    expect(path.eventMarkers, hasLength(1));
    expect(simulatedChanges, 1);

    undoStack.undo();
    await tester.pump();
    expect(path.eventMarkers, isEmpty);
    expect(simulatedChanges, 2);
  });

  testWidgets('marker slider previews without simulation and simulates on end',
      (tester) async {
    path
      ..eventMarkersExpanded = true
      ..eventMarkers = [
        EventMarker(waypointRelativePos: 0.25),
      ];

    await pumpTree(
      tester,
      Path2EventMarkersTree(
        path: path,
        undoStack: undoStack,
        initiallySelectedMarker: 0,
        onPathChanged: () => simulatedChanges++,
        onPathChangedNoSim: () => nonSimulatedChanges++,
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart?.call(0.25);
    slider.onChanged?.call(0.5);
    await tester.pump();

    expect(path.eventMarkers.single.waypointRelativePos, 0.5);
    expect(nonSimulatedChanges, 1);
    expect(simulatedChanges, 0);

    slider.onChangeEnd?.call(0.5);
    await tester.pump();
    expect(simulatedChanges, 1);
    expect(undoStack.canUndo, isTrue);

    undoStack.undo();
    await tester.pump();
    expect(path.eventMarkers.single.waypointRelativePos, 0.25);
    expect(simulatedChanges, 2);
  });

  testWidgets('zoned event sliders do not commit rejected crossing values',
      (tester) async {
    path
      ..eventMarkersExpanded = true
      ..eventMarkers = [
        EventMarker(
          waypointRelativePos: 0.25,
          endWaypointRelativePos: 0.75,
        ),
      ];

    await pumpTree(
      tester,
      Path2EventMarkersTree(
        path: path,
        undoStack: undoStack,
        initiallySelectedMarker: 0,
        onPathChanged: () => simulatedChanges++,
        onPathChangedNoSim: () => nonSimulatedChanges++,
      ),
    );

    final startSlider = tester.widget<Slider>(find.byType(Slider).first);
    startSlider.onChangeStart?.call(0.25);
    startSlider.onChanged?.call(0.9);
    startSlider.onChangeEnd?.call(0.9);
    await tester.pump();

    expect(path.eventMarkers.single.waypointRelativePos, 0.25);
    expect(path.eventMarkers.single.endWaypointRelativePos, 0.75);

    final endSlider = tester.widget<Slider>(find.byType(Slider).last);
    endSlider.onChangeStart?.call(0.75);
    endSlider.onChanged?.call(0.1);
    endSlider.onChangeEnd?.call(0.1);
    await tester.pump();

    expect(path.eventMarkers.single.waypointRelativePos, 0.25);
    expect(path.eventMarkers.single.endWaypointRelativePos, 0.75);
    expect(simulatedChanges, 0);
    expect(nonSimulatedChanges, 0);
    expect(undoStack.canUndo, isFalse);
  });

  testWidgets('new constraint zone inherits the second waypoint constraints',
      (tester) async {
    path.waypoints[1]
      ..maxVelocity = 2.25
      ..maxAngularVelocity = 135
      ..maxAngularAcceleration = 270;

    await pumpTree(
      tester,
      Path2ConstraintZonesTree(
        path: path,
        undoStack: undoStack,
        onPathChanged: () => simulatedChanges++,
      ),
    );

    await tester.tap(find.byTooltip('Add New Constraint Zone'));
    await tester.pump();

    final constraints = path.constraintZones.single.constraints;
    expect(constraints.maxVelocity, 2.25);
    expect(constraints.maxAngularVelocity, 135);
    expect(constraints.maxAngularAcceleration, 270);
    expect(simulatedChanges, 1);

    undoStack.undo();
    await tester.pump();
    expect(path.constraintZones, isEmpty);
    expect(simulatedChanges, 2);
  });

  testWidgets('constraint zone exposes Path 2 limits and supports undo',
      (tester) async {
    path
      ..constraintZonesExpanded = true
      ..constraintZones = [
        ConstraintsZone(
          constraints: WaypointConstraints(maxVelocity: 2),
        ),
      ];

    await pumpTree(
      tester,
      Path2ConstraintZonesTree(
        path: path,
        undoStack: undoStack,
        initiallySelectedZone: 0,
        onPathChanged: () => simulatedChanges++,
      ),
    );

    expect(find.widgetWithText(NumberTextField, 'Max Velocity (M/S)'),
        findsOneWidget);
    expect(find.widgetWithText(NumberTextField, 'Max Angular Velocity (Deg/S)'),
        findsOneWidget);
    expect(
        find.widgetWithText(
            NumberTextField, 'Max Angular Acceleration (Deg/S²)'),
        findsOneWidget);
    expect(find.textContaining('Linear Acceleration'), findsNothing);

    final maxVelocity = tester.widget<NumberTextField>(
      find.widgetWithText(NumberTextField, 'Max Velocity (M/S)'),
    );
    maxVelocity.onSubmitted?.call(1.5);
    await tester.pump();

    expect(path.constraintZones.single.constraints.maxVelocity, 1.5);
    expect(simulatedChanges, 1);

    undoStack.undo();
    await tester.pump();
    expect(path.constraintZones.single.constraints.maxVelocity, 2);
    expect(simulatedChanges, 2);
  });

  testWidgets('constraint zone priority reorder is undoable', (tester) async {
    path
      ..constraintZonesExpanded = true
      ..constraintZones = [
        ConstraintsZone(name: 'First'),
        ConstraintsZone(name: 'Second'),
      ];

    await pumpTree(
      tester,
      Path2ConstraintZonesTree(
        path: path,
        undoStack: undoStack,
        onPathChanged: () => simulatedChanges++,
      ),
    );

    await tester.tap(find.byTooltip('Move Zone Down').first);
    await tester.pump();
    expect(path.constraintZones.map((zone) => zone.name), ['Second', 'First']);

    undoStack.undo();
    await tester.pump();
    expect(path.constraintZones.map((zone) => zone.name), ['First', 'Second']);
  });

  testWidgets('point-towards add clamps its default range to a one-point path',
      (tester) async {
    path.waypoints.removeLast();

    await pumpTree(
      tester,
      Path2PointTowardsZonesTree(
        path: path,
        undoStack: undoStack,
        onPathChanged: () => simulatedChanges++,
      ),
    );

    await tester.tap(find.byTooltip('Add New Point Towards Zone'));
    await tester.pump();

    final zone = path.pointTowardsZones.single;
    expect(zone.minWaypointRelativePos, 0);
    expect(zone.maxWaypointRelativePos, 0);
    expect(simulatedChanges, 1);

    undoStack.undo();
    await tester.pump();
    expect(path.pointTowardsZones, isEmpty);
  });

  testWidgets('point-towards configuration fields update with undo',
      (tester) async {
    path
      ..pointTowardsZonesExpanded = true
      ..pointTowardsZones = [PointTowardsZone()];

    await pumpTree(
      tester,
      Path2PointTowardsZonesTree(
        path: path,
        undoStack: undoStack,
        initiallySelectedZone: 0,
        onPathChanged: () => simulatedChanges++,
      ),
    );

    expect(find.widgetWithText(NumberTextField, 'Field Position X (M)'),
        findsOneWidget);
    expect(find.widgetWithText(NumberTextField, 'Field Position Y (M)'),
        findsOneWidget);
    expect(find.widgetWithText(NumberTextField, 'Rotation Offset (Deg)'),
        findsOneWidget);
    expect(find.text('Unprofiled'), findsOneWidget);
    expect(
      find.byTooltip(
        'Use a normal PID controller for rotation while inside this zone '
        'instead of the profiled rotation controller.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(NumberTextField, 'Start Pos'), findsOneWidget);
    expect(find.widgetWithText(NumberTextField, 'End Pos'), findsOneWidget);
    final unprofiledLabel = tester.widget<Text>(find.text('Unprofiled'));
    expect(unprofiledLabel.style?.fontSize, 18);

    final endPositionTop =
        tester.getTopLeft(find.widgetWithText(NumberTextField, 'End Pos')).dy;
    final unprofiledTop = tester.getTopLeft(find.text('Unprofiled')).dy;
    expect(unprofiledTop, greaterThan(endPositionTop));

    final xPosition = tester.widget<NumberTextField>(
      find.widgetWithText(NumberTextField, 'Field Position X (M)'),
    );
    final oldX = path.pointTowardsZones.single.fieldPosition.x;
    xPosition.onSubmitted?.call(3.25);
    await tester.pump();

    expect(path.pointTowardsZones.single.fieldPosition.x, 3.25);
    expect(simulatedChanges, 1);

    undoStack.undo();
    await tester.pump();
    expect(path.pointTowardsZones.single.fieldPosition.x, oldX);
    expect(simulatedChanges, 2);

    final unprofiled = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Unprofiled'),
    );
    unprofiled.onChanged?.call(true);
    await tester.pump();
    expect(path.pointTowardsZones.single.unprofiled, isTrue);
    expect(simulatedChanges, 3);

    undoStack.undo();
    await tester.pump();
    expect(path.pointTowardsZones.single.unprofiled, isFalse);
    expect(simulatedChanges, 4);
  });
}
