import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/services/hot_reloadable_path.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';

void main() {
  late MemoryFileSystem fs;
  const pathsDir = '/paths';

  setUp(() {
    fs = MemoryFileSystem();
    fs.directory(pathsDir).createSync(recursive: true);
  });

  group('Path2 model', () {
    test('requires at least one waypoint', () {
      expect(
          () => path2.Path(
                name: 'empty',
                waypoints: [],
                fs: fs,
                pathDir: pathsDir,
              ),
          throwsArgumentError);

      expect(
          () => path2.Path.fromJson({
                'version': path2.fileVersion,
                'waypoints': [],
              }, 'empty', pathsDir, fs),
          throwsFormatException);
    });

    test('JSON round trip preserves version, folder, tolerances and waypoints',
        () {
      final original = path2.Path(
        name: 'roundtrip',
        waypoints: [
          TranslationWaypoint(
            position: const Translation2d(1, 2),
            maxVelocity: 3,
            handoffDistance: 0.4,
            maxAngularVelocity: 100,
            maxAngularAcceleration: 200,
          ),
          PoseWaypoint(
            position: const Translation2d(4, 5),
            rotation: Rotation2d.fromDegrees(60),
            maxVelocity: 6,
            handoffDistance: 0.7,
            maxAngularVelocity: 300,
            maxAngularAcceleration: 400,
          ),
        ],
        endToleranceMeters: 0.25,
        endAngleToleranceDegrees: 3.5,
        folder: 'Folder',
        sourceVersion: '2028.1.0-beta.1',
        fs: fs,
        pathDir: pathsDir,
      );

      final restored = path2.Path.fromJson(
          jsonDecode(jsonEncode(original.toJson())),
          original.name,
          pathsDir,
          fs);

      expect(restored, original);
      expect(restored, isA<HotReloadablePath>());
      expect(restored.sourceVersion, '2028.1.0-beta.1');
      expect(restored.folder, 'Folder');
      expect(restored.waypoints.first.handoffDistance, 0.4);
    });

    test('omitted optional path values use defaults', () {
      final path = path2.Path.fromJson({
        'version': path2.fileVersion,
        'waypoints': [
          {
            'type': 'translation',
            'position': {'x': 1, 'y': 2},
          }
        ],
      }, 'defaults', pathsDir, fs);

      expect(path.endToleranceMeters, 0.1);
      expect(path.endAngleToleranceDegrees, 2.0);
      expect(path.folder, isNull);
    });

    test('append, midpoint insertion and preview positions use translations',
        () {
      final path = path2.Path(
        name: 'editing',
        waypoints: [
          TranslationWaypoint(position: const Translation2d(0, 0)),
          PoseWaypoint(
              position: const Translation2d(4, 2),
              rotation: const Rotation2d()),
        ],
        fs: fs,
        pathDir: pathsDir,
      );

      path.insertWaypointAfter(-1);
      path.insertWaypointAfter(1);
      expect(path.waypoints, hasLength(2));

      path.insertWaypointAfter(0);
      expect(path.waypoints, hasLength(3));
      expect(path.waypoints[1], isA<TranslationWaypoint>());
      expect(path.waypoints[1].position, const Translation2d(2, 1));

      path.addWaypoint(const Translation2d(8, 3));
      expect(path.waypoints.last, isA<TranslationWaypoint>());
      expect(path.pathPositions, const [
        Translation2d(0, 0),
        Translation2d(2, 1),
        Translation2d(4, 2),
        Translation2d(8, 3),
      ]);
    });

    test('duplicate deeply clones waypoints and preserves path settings', () {
      final original = path2.Path(
        name: 'original',
        waypoints: [
          PoseWaypoint(
              position: const Translation2d(1, 2),
              rotation: Rotation2d.fromDegrees(45)),
        ],
        endToleranceMeters: 0.3,
        endAngleToleranceDegrees: 4,
        folder: 'Folder',
        sourceVersion: '2028.0',
        fs: fs,
        pathDir: pathsDir,
      );

      final duplicate = original.duplicate('copy');
      duplicate.waypoints.first.move(9, 10);

      expect(duplicate.name, 'copy');
      expect(duplicate.waypoints.first, isA<PoseWaypoint>());
      expect(identical(duplicate.waypoints.first, original.waypoints.first),
          false);
      expect(original.waypoints.first.position, const Translation2d(1, 2));
      expect(duplicate.endToleranceMeters, original.endToleranceMeters);
      expect(duplicate.endAngleToleranceDegrees,
          original.endAngleToleranceDegrees);
      expect(duplicate.folder, original.folder);
      expect(duplicate.sourceVersion, original.sourceVersion);
    });
  });

  group('Path2 file management', () {
    test('save, rename and delete are synchronous', () {
      final path = path2.Path.defaultPath(
          name: 'test', pathDir: pathsDir, fs: fs, folder: 'Folder');
      path.lastModified = DateTime.utc(2000);

      path.saveFile();

      final originalFile = fs.file(p.join(pathsDir, 'test.path'));
      expect(originalFile.existsSync(), true);
      expect(path.lastModified.isAfter(DateTime.utc(2000)), true);
      expect(
          const DeepCollectionEquality().equals(
              jsonDecode(originalFile.readAsStringSync()), path.toJson()),
          true);

      path.renamePath('renamed');
      expect(path.name, 'renamed');
      expect(originalFile.existsSync(), false);
      expect(fs.file(p.join(pathsDir, 'renamed.path')).existsSync(), true);

      path.deletePath();
      expect(fs.file(p.join(pathsDir, 'renamed.path')).existsSync(), false);
    });

    test('loader gates versions, isolates failures, and rewrites no files',
        () async {
      String validFile(String version) => jsonEncode({
            'version': version,
            'waypoints': [
              {
                'type': 'translation',
                'position': {'x': 1, 'y': 2},
              }
            ],
            'folder': 'Loaded',
          });

      final contents = <String, String>{
        'current.path': validFile('2027.0'),
        'future.path': validFile('2028.1.0-beta.1'),
        'old.path': validFile('2026.9.9'),
        'prerelease.path': validFile('2027.0-alpha.1'),
        'missing.path': jsonEncode({
          'waypoints': [
            {
              'type': 'translation',
              'position': {'x': 1, 'y': 2},
            }
          ]
        }),
        'malformed.path': validFile('not-a-version'),
        'corrupt.path': '{bad json',
        'empty.path': jsonEncode({
          'version': '2027.0',
          'waypoints': [],
        }),
      };

      for (final entry in contents.entries) {
        fs.file(p.join(pathsDir, entry.key)).writeAsStringSync(entry.value);
      }

      final loaded = await path2.Path.loadAllPathsInDir(pathsDir, fs);

      loaded.sort((a, b) => a.name.compareTo(b.name));
      expect(loaded.map((path) => path.name), ['current', 'future']);
      expect(loaded.first.sourceVersion, '2027.0');
      expect(loaded.last.sourceVersion, '2028.1.0-beta.1');
      expect(loaded.first.folder, 'Loaded');

      for (final entry in contents.entries) {
        expect(fs.file(p.join(pathsDir, entry.key)).readAsStringSync(),
            entry.value,
            reason: '${entry.key} was unexpectedly rewritten');
      }
    });

    test('saving a loaded future path preserves its source version', () async {
      final file = fs.file(p.join(pathsDir, 'future.path'));
      file.writeAsStringSync(jsonEncode({
        'version': '2030.2.0',
        'waypoints': [
          {
            'type': 'pose',
            'position': {'x': 1, 'y': 2},
            'rotation': {'value': 0.5},
          }
        ],
      }));

      final loaded = await path2.Path.loadAllPathsInDir(pathsDir, fs);
      loaded.single.saveFile();

      expect(jsonDecode(file.readAsStringSync())['version'], '2030.2.0');
    });

    test('missing directory loads as an empty list', () async {
      expect(
          await path2.Path.loadAllPathsInDir('/does-not-exist', fs), isEmpty);
    });
  });
}
