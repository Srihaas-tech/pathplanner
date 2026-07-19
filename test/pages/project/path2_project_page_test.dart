import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:pathplanner/auto/pathplanner_auto.dart';
import 'package:pathplanner/commands/command_groups.dart';
import 'package:pathplanner/commands/named_command.dart';
import 'package:pathplanner/commands/path_command.dart';
import 'package:pathplanner/pages/project/path2_project_page.dart';
import 'package:pathplanner/pages/project/project_item_card.dart';
import 'package:pathplanner/services/project_event_registry.dart';
import 'package:pathplanner/util/prefs.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undo/undo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late MemoryFileSystem fs;
  final deployPath = Platform.isWindows ? r'C:\deploy' : '/deploy';

  setUp(() async {
    ProjectEventRegistry.clear();
    SharedPreferences.setMockInitialValues({
      PrefsKeys.projectLeftWeight: 0.5,
      PrefsKeys.pathsCompactView: true,
    });
    prefs = await SharedPreferences.getInstance();
    fs = MemoryFileSystem(
      style:
          Platform.isWindows ? FileSystemStyle.windows : FileSystemStyle.posix,
    );
  });

  Widget project() => MaterialApp(
        home: Scaffold(
          body: Path2ProjectPage(
            prefs: prefs,
            fieldImage: FieldImage.defaultField,
            pathplannerDirectory: fs.directory(deployPath),
            fs: fs,
            undoStack: ChangeStack(),
            shortcuts: false,
          ),
        ),
      );

  testWidgets('creates the Path2 example only for a physically empty directory',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(project());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(
        find.widgetWithText(ProjectItemCard, 'Example Path'), findsOneWidget);
    expect(
      fs.file(join(deployPath, 'paths', 'Example Path.path')).existsSync(),
      isTrue,
    );
  });

  testWidgets('rejected paths stay reserved and suppress the example fallback',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pathsDir = fs.directory(join(deployPath, 'paths'))
      ..createSync(recursive: true);
    // Case variants must collide too because the normal macOS deployment
    // filesystem is case-insensitive.
    final oldFile = fs.file(join(pathsDir.path, 'new path.path'));
    const oldSource = '{"version":"2026.0"}';
    oldFile.writeAsStringSync(oldSource);

    await tester.pumpWidget(project());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ProjectItemCard, 'Example Path'), findsNothing);
    expect(find.byType(ProjectItemCard), findsNothing);
    await tester.tap(find.byTooltip('Add new path'));
    await tester.pumpAndSettle();

    expect(
        find.widgetWithText(ProjectItemCard, 'New New Path'), findsOneWidget);
    expect(oldFile.readAsStringSync(), oldSource);
  });

  testWidgets('hidden Choreo autos remain untouched and reserve their names',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final autosDir = fs.directory(join(deployPath, 'autos'))
      ..createSync(recursive: true);
    final choreo = PathPlannerAuto.defaultAuto(
      name: 'New Auto',
      autoDir: autosDir.path,
      fs: fs,
      choreoAuto: true,
    );
    final choreoFile = fs.file(join(autosDir.path, 'new auto.auto'));
    final source = jsonEncode(choreo.toJson());
    choreoFile.writeAsStringSync(source);

    await tester.pumpWidget(project());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ProjectItemCard, 'New Auto'), findsNothing);
    await tester.tap(find.byTooltip('Add new auto'));
    await tester.pumpAndSettle();

    expect(
        find.widgetWithText(ProjectItemCard, 'New New Auto'), findsOneWidget);
    final newAutoJson = jsonDecode(
      fs.file(join(autosDir.path, 'New New Auto.auto')).readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(newAutoJson, isNot(contains('resetOdom')));
    expect(newAutoJson['startingPoseInitialized'], isFalse);
    expect(choreoFile.readAsStringSync(), source);
    expect(find.textContaining('Choreo'), findsNothing);
  });

  testWidgets('missing path references are not persisted during initial load',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pathsDir = fs.directory(join(deployPath, 'paths'))
      ..createSync(recursive: true);
    // A physical legacy path suppresses the fallback but is rejected by Path2.
    fs
        .file(join(pathsDir.path, 'missing.path'))
        .writeAsStringSync('{"version":"2026.0"}');
    final autosDir = fs.directory(join(deployPath, 'autos'))
      ..createSync(recursive: true);
    final auto = PathPlannerAuto(
      name: 'references missing',
      sequence: SequentialCommandGroup(
        commands: [PathCommand(pathName: 'missing')],
      ),
      resetOdom: true,
      autoDir: autosDir.path,
      fs: fs,
      folder: null,
      choreoAuto: false,
    );
    final autoFile = fs.file(join(autosDir.path, '${auto.name}.auto'));
    final source = jsonEncode(auto.toJson());
    autoFile.writeAsStringSync(source);

    await tester.pumpWidget(project());
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(ProjectItemCard, 'references missing'),
      findsOneWidget,
    );
    expect(autoFile.readAsStringSync(), source);
  });

  testWidgets('events-only management recursively renames and deletes events',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final autosDir = fs.directory(join(deployPath, 'autos'))
      ..createSync(recursive: true);
    final auto = PathPlannerAuto(
      name: 'events',
      sequence: SequentialCommandGroup(
        commands: [
          SequentialCommandGroup(
            commands: [NamedCommand(name: 'score')],
          ),
        ],
      ),
      resetOdom: true,
      autoDir: autosDir.path,
      fs: fs,
      folder: null,
      choreoAuto: false,
    );
    final autoFile = fs.file(join(autosDir.path, 'events.auto'));
    autoFile.writeAsStringSync(jsonEncode(auto.toJson()));

    await tester.pumpWidget(project());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage Events'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Linked Waypoint'), findsNothing);
    await tester.tap(find.byTooltip('Rename event'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'score renamed');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(ProjectEventRegistry.events, contains('score renamed'));
    expect(autoFile.readAsStringSync(), contains('score renamed'));

    await tester.tap(find.byTooltip('Remove event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(ProjectEventRegistry.events, isNot(contains('score renamed')));
    expect(autoFile.readAsStringSync(), contains('"name": null'));
  });
}
