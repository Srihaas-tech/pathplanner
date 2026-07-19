import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pathplanner/commands/command_groups.dart';
import 'package:pathplanner/commands/named_command.dart';
import 'package:pathplanner/commands/path_command.dart';
import 'package:pathplanner/commands/wait_command.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/pathplanner_auto.dart' as path2_auto;
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/services/project_event_registry.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';

void main() {
  late MemoryFileSystem fs;
  const autosDir = '/autos';
  const pathsDir = '/paths';

  setUp(() {
    fs = MemoryFileSystem();
    fs.directory(autosDir).createSync(recursive: true);
    fs.directory(pathsDir).createSync(recursive: true);
    ProjectEventRegistry.clear();
  });

  path2.Path posePath(
    String name, {
    Translation2d position = const Translation2d(1, 2),
    Rotation2d rotation = const Rotation2d(0.5),
  }) {
    return path2.Path(
      name: name,
      waypoints: [PoseWaypoint(position: position, rotation: rotation)],
      fs: fs,
      pathDir: pathsDir,
    );
  }

  Map<String, dynamic> legacyAutoJson(List<String> pathNames) {
    return {
      'version': '2025.0',
      'command': SequentialCommandGroup(
        commands: [for (final name in pathNames) PathCommand(pathName: name)],
      ).toJson(),
      'resetOdom': true,
      'folder': 'Legacy',
      'choreoAuto': false,
    };
  }

  group('Path2 auto schema', () {
    test('new autos persist an uninitialized zero pose in the 2027 schema', () {
      final auto = path2_auto.Path2Auto.defaultAuto(
        name: 'New Auto',
        autoDir: autosDir,
        fs: fs,
        folder: 'Folder',
      );

      final json = auto.toJson();

      expect(json['version'], path2_auto.fileVersion);
      expect(json['command']['type'], 'sequential');
      expect(json['startingPose'], {
        'position': {'x': 0.0, 'y': 0.0},
        'rotation': 0,
      });
      expect(json['startingPoseInitialized'], false);
      expect(json['folder'], 'Folder');
      expect(json, isNot(contains('resetOdom')));
      expect(json, isNot(contains('choreoAuto')));
    });

    test('round trip preserves command tree, folder, pose radians, and flag',
        () {
      final original = path2_auto.Path2Auto(
        name: 'Round Trip',
        sequence: SequentialCommandGroup(
          commands: [
            WaitCommand(waitTime: 1.25),
            SequentialCommandGroup(
              commands: [
                PathCommand(pathName: 'A'),
                NamedCommand(name: 'score'),
              ],
            ),
          ],
        ),
        startingPose: const Pose2d(
          Translation2d(3.2, 4.5),
          Rotation2d(1.75),
        ),
        startingPoseInitialized: true,
        folder: 'Folder',
        sourceVersion: '2028.1.0-beta.1',
        autoDir: autosDir,
        fs: fs,
      );

      final json =
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      final restored = path2_auto.Path2Auto.fromJson(
        json,
        original.name,
        autosDir,
        fs,
      );

      expect(restored, original);
      expect(restored.version, '2028.1.0-beta.1');
      expect(restored.startingPose.rotation.radians, 1.75);
      expect(json['startingPose']['rotation'], 1.75);
      expect(ProjectEventRegistry.events, contains('score'));
    });

    test('current and future schemas require finite complete starting state',
        () {
      final valid = {
        'version': path2_auto.fileVersion,
        'command': SequentialCommandGroup(commands: []).toJson(),
        'startingPose': {
          'position': {'x': 0, 'y': 0},
          'rotation': 0,
        },
        'startingPoseInitialized': false,
        'folder': null,
      };

      expect(
        () => path2_auto.Path2Auto.fromJson(
          {...valid}..remove('startingPoseInitialized'),
          'bad',
          autosDir,
          fs,
        ),
        throwsFormatException,
      );
      expect(
        () => path2_auto.Path2Auto.fromJson(
          {
            ...valid,
            'startingPose': {
              'position': {'x': double.infinity, 'y': 0},
              'rotation': 0,
            },
          },
          'bad',
          autosDir,
          fs,
        ),
        throwsFormatException,
      );
      expect(
        () => path2_auto.Path2Auto.fromJson(
          {...valid, 'version': 'not-a-version'},
          'bad',
          autosDir,
          fs,
        ),
        throwsFormatException,
      );
    });
  });

  group('starting pose initialization', () {
    test('new auto seeds from the first resolvable path exactly once', () {
      final firstResolved = posePath(
        'resolved',
        position: const Translation2d(4, 6),
        rotation: const Rotation2d(0.8),
      );
      final later = posePath(
        'later',
        position: const Translation2d(8, 9),
        rotation: const Rotation2d(1.2),
      );
      final auto = path2_auto.Path2Auto(
        name: 'Seed',
        sequence: SequentialCommandGroup(
          commands: [
            PathCommand(pathName: 'missing'),
            PathCommand(pathName: firstResolved.name),
            PathCommand(pathName: later.name),
          ],
        ),
        autoDir: autosDir,
        fs: fs,
      );

      expect(auto.initializeStartingPoseFromPaths([]), false);
      expect(auto.startingPoseInitialized, false);
      expect(
          auto.initializeStartingPoseFromPaths([firstResolved, later]), true);
      expect(auto.startingPose.translation, const Translation2d(4, 6));
      expect(auto.startingPose.rotation.radians, 0.8);

      auto.sequence.commands
        ..clear()
        ..add(PathCommand(pathName: later.name));
      auto.handleMissingPaths([later.name]);
      expect(auto.initializeStartingPoseFromPaths([later]), false);
      expect(auto.startingPose.translation, const Translation2d(4, 6));
      expect(auto.startingPose.rotation.radians, 0.8);
    });

    test('translation-only start uses zero heading and manual edit initializes',
        () {
      final translationPath = path2.Path(
        name: 'translation',
        waypoints: [
          TranslationWaypoint(position: const Translation2d(2, 3)),
        ],
        fs: fs,
        pathDir: pathsDir,
      );
      final auto = path2_auto.Path2Auto(
        name: 'Translation',
        sequence: SequentialCommandGroup(
          commands: [PathCommand(pathName: translationPath.name)],
        ),
        autoDir: autosDir,
        fs: fs,
      );

      expect(auto.initializeStartingPoseFromPaths([translationPath]), true);
      expect(auto.startingPose.translation, const Translation2d(2, 3));
      expect(auto.startingPose.rotation.radians, 0);

      auto.setStartingPose(
        const Pose2d(Translation2d(7, 8), Rotation2d(2.4)),
      );
      expect(auto.startingPoseInitialized, true);
      expect(auto.startingPose.translation, const Translation2d(7, 8));
      expect(auto.startingPose.rotation.radians, 2.4);
    });

    test('duplicate keeps initialization state and deeply clones commands', () {
      final auto = path2_auto.Path2Auto(
        name: 'Original',
        sequence: SequentialCommandGroup(
          commands: [PathCommand(pathName: 'A')],
        ),
        startingPose: const Pose2d(Translation2d(1, 2), Rotation2d(0.25)),
        startingPoseInitialized: true,
        folder: 'Folder',
        autoDir: autosDir,
        fs: fs,
      );

      final copy = auto.duplicate('Copy');
      auto.sequence.commands.clear();

      expect(copy.name, 'Copy');
      expect(copy.sequence.commands, hasLength(1));
      expect(copy.startingPose.translation, const Translation2d(1, 2));
      expect(copy.startingPoseInitialized, true);
      expect(copy.folder, 'Folder');
    });
  });

  group('legacy migration and file management', () {
    test(
        'legacy fromJson seeds first resolvable path and is always initialized',
        () {
      final resolved = posePath(
        'resolved',
        position: const Translation2d(5, 6),
        rotation: const Rotation2d(1.1),
      );

      final seeded = path2_auto.Path2Auto.fromJson(
        legacyAutoJson(['missing', resolved.name]),
        'seeded',
        autosDir,
        fs,
        paths: [resolved],
      );
      final fallback = path2_auto.Path2Auto.fromJson(
        legacyAutoJson(['missing']),
        'fallback',
        autosDir,
        fs,
        paths: [resolved],
      );

      expect(seeded.version, path2_auto.fileVersion);
      expect(seeded.startingPose.translation, const Translation2d(5, 6));
      expect(seeded.startingPose.rotation.radians, 1.1);
      expect(seeded.startingPoseInitialized, true);
      expect(fallback.startingPose.translation, const Translation2d());
      expect(fallback.startingPose.rotation.radians, 0);
      expect(fallback.startingPoseInitialized, true);
    });

    test('loader defers migration write until the next normal save', () async {
      final resolved = posePath(
        'resolved',
        position: const Translation2d(5, 6),
        rotation: const Rotation2d(1.1),
      );
      final seededFile = fs.file(p.join(autosDir, 'seeded.auto'));
      final fallbackFile = fs.file(p.join(autosDir, 'fallback.auto'));
      final seededSource =
          jsonEncode(legacyAutoJson(['missing', resolved.name]));
      final fallbackSource = jsonEncode(legacyAutoJson(['missing']));
      seededFile.writeAsStringSync(seededSource);
      fallbackFile.writeAsStringSync(fallbackSource);

      final loaded = await path2_auto.Path2Auto.loadAllAutosInDir(
        autosDir,
        fs,
        paths: [resolved],
      );
      loaded.sort((a, b) => a.name.compareTo(b.name));

      expect(loaded.map((auto) => auto.name), ['fallback', 'seeded']);
      expect(seededFile.readAsStringSync(), seededSource);
      expect(fallbackFile.readAsStringSync(), fallbackSource);
      expect(loaded.last.startingPose.translation, const Translation2d(5, 6));
      expect(loaded.last.startingPoseInitialized, true);
      expect(loaded.first.startingPose.translation, const Translation2d());
      expect(loaded.first.startingPoseInitialized, true);

      loaded.last.saveFile();
      loaded.first.saveFile();
      final seededJson =
          jsonDecode(seededFile.readAsStringSync()) as Map<String, dynamic>;
      final fallbackJson =
          jsonDecode(fallbackFile.readAsStringSync()) as Map<String, dynamic>;
      expect(seededJson['version'], path2_auto.fileVersion);
      expect(seededJson['startingPose'], {
        'position': {'x': 5, 'y': 6},
        'rotation': 1.1,
      });
      expect(seededJson['startingPoseInitialized'], true);
      expect(fallbackJson['startingPoseInitialized'], true);
      expect(fallbackJson['startingPose'], {
        'position': {'x': 0.0, 'y': 0.0},
        'rotation': 0,
      });
      expect(seededJson, isNot(contains('resetOdom')));
      expect(seededJson, isNot(contains('choreoAuto')));

      final persistedSource = seededFile.readAsStringSync();
      await path2_auto.Path2Auto.loadAllAutosInDir(
        autosDir,
        fs,
        paths: [resolved],
      );
      expect(seededFile.readAsStringSync(), persistedSource);
    });

    test('loader skips Choreo, isolates invalid files, and preserves future',
        () async {
      final current = path2_auto.Path2Auto.defaultAuto(
        name: 'current',
        autoDir: autosDir,
        fs: fs,
      );
      final currentFile = fs.file(p.join(autosDir, 'current.auto'));
      currentFile.writeAsStringSync(jsonEncode(current.toJson()));

      final futureJson = {
        ...current.toJson(),
        'version': '2029.2.0',
        'startingPoseInitialized': true,
      };
      final futureFile = fs.file(p.join(autosDir, 'future.auto'));
      futureFile.writeAsStringSync(jsonEncode(futureJson));

      const choreoSource =
          '{"version":"2025.0","choreoAuto":true,"command":{}}';
      final choreoFile = fs.file(p.join(autosDir, 'choreo.auto'));
      choreoFile.writeAsStringSync(choreoSource);
      const invalidSource = '{"version":"2027.0","command":{}}';
      final invalidFile = fs.file(p.join(autosDir, 'invalid.auto'));
      invalidFile.writeAsStringSync(invalidSource);

      final loaded = await path2_auto.Path2Auto.loadAllAutosInDir(autosDir, fs);
      loaded.sort((a, b) => a.name.compareTo(b.name));

      expect(loaded.map((auto) => auto.name), ['current', 'future']);
      expect(loaded.last.version, '2029.2.0');
      expect(choreoFile.readAsStringSync(), choreoSource);
      expect(invalidFile.readAsStringSync(), invalidSource);
      expect(jsonDecode(futureFile.readAsStringSync()), futureJson);
    });

    test('save, rename, delete, path rename, and missing directory work',
        () async {
      final auto = path2_auto.Path2Auto(
        name: 'file',
        sequence: SequentialCommandGroup(
          commands: [
            SequentialCommandGroup(
              commands: [PathCommand(pathName: 'old')],
            ),
          ],
        ),
        autoDir: autosDir,
        fs: fs,
      );

      auto.saveFile();
      expect(fs.file(p.join(autosDir, 'file.auto')).existsSync(), true);
      auto.updatePathName('old', 'new');
      expect(auto.getAllPathNames(), ['new']);

      auto.rename('renamed');
      expect(auto.name, 'renamed');
      expect(fs.file(p.join(autosDir, 'file.auto')).existsSync(), false);
      expect(fs.file(p.join(autosDir, 'renamed.auto')).existsSync(), true);

      auto.delete();
      expect(fs.file(p.join(autosDir, 'renamed.auto')).existsSync(), false);
      expect(
        await path2_auto.Path2Auto.loadAllAutosInDir('/missing', fs),
        isEmpty,
      );
    });
  });
}
