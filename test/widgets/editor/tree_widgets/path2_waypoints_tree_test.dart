import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_waypoints_tree.dart';
import 'package:pathplanner/widgets/number_text_field.dart';
import 'package:undo/undo.dart';

void main() {
  late path2.Path path;
  late ChangeStack undoStack;
  late bool pathChanged;

  setUp(() {
    path = path2.Path.defaultPath(
      name: 'Path2',
      pathDir: '/paths',
      fs: MemoryFileSystem(),
    )..waypointsExpanded = true;
    undoStack = ChangeStack();
    pathChanged = false;
  });

  Future<void> pumpTree(
    WidgetTester tester, {
    int? selectedWaypoint = 0,
    ValueChanged<int>? onWaypointDeleted,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Path2WaypointsTree(
                path: path,
                undoStack: undoStack,
                initialSelectedWaypoint: selectedWaypoint,
                onPathChanged: () => pathChanged = true,
                onWaypointDeleted: onWaypointDeleted,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('edits position, heading, and all Path2 limits', (tester) async {
    await pumpTree(tester);

    Future<void> submit(String label, String value) async {
      final field = find.widgetWithText(NumberTextField, label);
      expect(field, findsOneWidget);
      await tester.enterText(field, value);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    await submit('X Position (M)', '1.25');
    await submit('Y Position (M)', '2.50');
    await submit('Heading (Deg)', '45');
    await submit('Max Velocity (M/S)', '3.2');
    await submit('Handoff Distance (M)', '0.4');
    await submit('Max Angular Velocity (Deg/S)', '240');
    await submit('Max Angular Acceleration (Deg/S²)', '480');

    final waypoint = path.waypoints.first as PoseWaypoint;
    expect(waypoint.position.x, closeTo(1.25, 0.001));
    expect(waypoint.position.y, closeTo(2.5, 0.001));
    expect(waypoint.rotation.degrees, closeTo(45, 0.001));
    expect(waypoint.maxVelocity, closeTo(3.2, 0.001));
    expect(waypoint.handoffDistance, closeTo(0.4, 0.001));
    expect(waypoint.maxAngularVelocity, closeTo(240, 0.001));
    expect(waypoint.maxAngularAcceleration, closeTo(480, 0.001));
    expect(pathChanged, isTrue);
  });

  testWidgets('pose toggle preserves limits and is undoable', (tester) async {
    final original = path.waypoints.first;
    original.maxVelocity = 2.2;
    original.handoffDistance = 0.6;
    original.maxAngularVelocity = 180;
    original.maxAngularAcceleration = 360;
    await pumpTree(tester);

    await tester.tap(find.text('Pose waypoint'));
    await tester.pumpAndSettle();

    final translation = path.waypoints.first;
    expect(translation, isA<TranslationWaypoint>());
    expect(translation.maxVelocity, 2.2);
    expect(translation.handoffDistance, 0.6);
    expect(translation.maxAngularVelocity, 180);
    expect(translation.maxAngularAcceleration, 360);
    expect(find.text('Heading (Deg)'), findsNothing);

    undoStack.undo();
    await tester.pumpAndSettle();
    expect(path.waypoints.first, isA<PoseWaypoint>());
    expect(path.waypoints.first.maxVelocity, 2.2);
  });

  testWidgets('limit fields clamp negative values to zero', (tester) async {
    await pumpTree(tester);

    final field = find.widgetWithText(NumberTextField, 'Handoff Distance (M)');
    await tester.enterText(field, '-1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(path.waypoints.first.handoffDistance, 0);
  });

  testWidgets('inserts a translation waypoint at the segment midpoint',
      (tester) async {
    final before = path.waypoints.first.position;
    final after = path.waypoints.last.position;
    await pumpTree(tester);

    await tester.tap(find.byTooltip('Create New Waypoint After'));
    await tester.pumpAndSettle();

    expect(path.waypoints, hasLength(3));
    expect(path.waypoints[1], isA<TranslationWaypoint>());
    expect(
        path.waypoints[1].position.x, closeTo((before.x + after.x) / 2, 0.001));
    expect(
        path.waypoints[1].position.y, closeTo((before.y + after.y) / 2, 0.001));

    undoStack.undo();
    await tester.pumpAndSettle();
    expect(path.waypoints, hasLength(2));
  });

  testWidgets('does not offer deletion for the only waypoint', (tester) async {
    path.waypoints = [path.waypoints.first];
    await pumpTree(tester);

    expect(find.byTooltip('Delete Waypoint'), findsNothing);
  });
}
