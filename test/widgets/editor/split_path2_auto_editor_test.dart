import 'package:file/memory.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/commands/command_groups.dart';
import 'package:pathplanner/commands/path_command.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/pathplanner_auto.dart';
import 'package:pathplanner/util/prefs.dart';
import 'package:pathplanner/util/path_painter_util.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/widgets/editor/path2_painter.dart';
import 'package:pathplanner/widgets/editor/preview_seekbar.dart';
import 'package:pathplanner/widgets/editor/split_path2_auto_editor.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_auto_tree.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undo/undo.dart';

void main() {
  testWidgets('simulates with the Path2 painter, tree, and active seekbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      PrefsKeys.treeOnRight: true,
      PrefsKeys.pathsCompactView: true,
    });
    final prefs = await SharedPreferences.getInstance();
    final fs = MemoryFileSystem();
    final path = path2.Path.defaultPath(
      name: 'testPath',
      pathDir: '/paths',
      fs: fs,
    );
    final auto = Path2Auto(
      name: 'testAuto',
      sequence: SequentialCommandGroup(
        commands: [PathCommand(pathName: path.name)],
      ),
      startingPose: Pose2d(
        path.waypoints.first.position,
        const Rotation2d(),
      ),
      startingPoseInitialized: true,
      autoDir: '/autos',
      fs: fs,
      folder: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitPath2AutoEditor(
            prefs: prefs,
            auto: auto,
            autoPaths: [path],
            allPathNames: [path.name],
            fieldImage: FieldImage.defaultField,
            undoStack: ChangeStack(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.byType(Path2AutoTree), findsOneWidget);
    expect(find.text('Reset Odometry'), findsNothing);
    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(paints.any((paint) => paint.painter is Path2Painter), isTrue);
    final painter =
        paints.map((paint) => paint.painter).whereType<Path2Painter>().single;
    expect(painter.simulation, isNotNull);
    expect(painter.autoStartingPose, auto.startingPose);
    expect(painter.showWaypointRobotPreviews, isFalse);
    final seekbar = tester.widget<PreviewSeekbar>(find.byType(PreviewSeekbar));
    expect(seekbar.enabled, isTrue);
    expect(seekbar.totalPathTime, greaterThan(0));
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    expect(find.textContaining('Simulated Driving Time:'), findsOneWidget);
  });

  testWidgets('drags the auto starting position as one undoable change',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      PrefsKeys.treeOnRight: true,
      PrefsKeys.robotWidth: 0.9,
      PrefsKeys.robotLength: 0.9,
      PrefsKeys.snapToGuidelines: false,
    });
    final prefs = await SharedPreferences.getInstance();
    final fs = MemoryFileSystem();
    final path = path2.Path.defaultPath(
      name: 'testPath',
      pathDir: '/paths',
      fs: fs,
    );
    final originalPose = Pose2d(
      path.waypoints.first.position,
      const Rotation2d(),
    );
    final auto = Path2Auto(
      name: 'testAuto',
      sequence: SequentialCommandGroup(
        commands: [PathCommand(pathName: path.name)],
      ),
      startingPose: originalPose,
      startingPoseInitialized: true,
      autoDir: '/autos',
      fs: fs,
    );
    final undoStack = ChangeStack();
    final fieldImage = FieldImage.official(OfficialField.chargedUp);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitPath2AutoEditor(
            prefs: prefs,
            auto: auto,
            autoPaths: [path],
            allPathNames: [path.name],
            fieldImage: fieldImage,
            undoStack: undoStack,
          ),
        ),
      ),
    );
    await tester.pump();

    final start = PathPainterUtil.pointToPixelOffset(
          originalPose.translation,
          Path2Painter.scale,
          fieldImage,
        ) +
        tester.getTopLeft(find.byKey(const ValueKey('path2AutoFieldGesture'))) +
        const Offset(48, 48);
    final meterPixels = PathPainterUtil.metersToPixels(
      1,
      Path2Painter.scale,
      fieldImage,
    );
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var step = 0; step < 10; step++) {
      await gesture.moveBy(Offset(meterPixels / 10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(auto.startingPose.x, closeTo(originalPose.x + 1, 0.05));
    expect(auto.startingPose.y, closeTo(originalPose.y, 0.05));
    expect(undoStack.canUndo, isTrue);

    undoStack.undo();
    await tester.pump();
    expect(auto.startingPose.translation, originalPose.translation);
    expect(auto.startingPoseInitialized, true);
  });
}
