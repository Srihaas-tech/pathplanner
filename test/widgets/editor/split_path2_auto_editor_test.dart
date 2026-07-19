import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/auto/pathplanner_auto.dart';
import 'package:pathplanner/commands/command_groups.dart';
import 'package:pathplanner/commands/path_command.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/util/prefs.dart';
import 'package:pathplanner/widgets/editor/path2_painter.dart';
import 'package:pathplanner/widgets/editor/preview_seekbar.dart';
import 'package:pathplanner/widgets/editor/split_path2_auto_editor.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_auto_tree.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undo/undo.dart';

void main() {
  testWidgets('uses the Path2 painter/tree and a disabled idle seekbar',
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
    final auto = PathPlannerAuto(
      name: 'testAuto',
      sequence: SequentialCommandGroup(
        commands: [PathCommand(pathName: path.name)],
      ),
      resetOdom: true,
      autoDir: '/autos',
      fs: fs,
      folder: null,
      choreoAuto: false,
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

    expect(find.byType(Path2AutoTree), findsOneWidget);
    expect(find.text('Reset Odometry'), findsNothing);
    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(paints.any((paint) => paint.painter is Path2Painter), isTrue);
    final seekbar = tester.widget<PreviewSeekbar>(find.byType(PreviewSeekbar));
    expect(seekbar.enabled, isFalse);
    expect(find.text('0.00'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });
}
