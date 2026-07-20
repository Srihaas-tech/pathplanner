import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pathplanner/commands/command_groups.dart';
import 'package:pathplanner/commands/named_command.dart';
import 'package:pathplanner/path2/constraints_zone.dart';
import 'package:pathplanner/path2/event_marker.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/point_towards_zone.dart';
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/services/hot_reloadable_path.dart';
import 'package:pathplanner/services/project_event_registry.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';

void main() {
  late MemoryFileSystem fs;
  const pathsDir = '/paths';

  setUp(() {
    ProjectEventRegistry.clear();
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

    test('JSON round trip preserves markers and ordered zones', () {
      final original = path2.Path(
        name: 'annotations',
        waypoints: [
          TranslationWaypoint(position: const Translation2d(0, 0)),
          TranslationWaypoint(position: const Translation2d(4, 0)),
        ],
        eventMarkers: [
          EventMarker(
            name: 'late',
            waypointRelativePos: 0.8,
          ),
          EventMarker(
            name: 'early',
            waypointRelativePos: 0.2,
            endWaypointRelativePos: 0.6,
            command: SequentialCommandGroup(
              commands: [NamedCommand(name: 'nested')],
            ),
          ),
        ],
        constraintZones: [
          ConstraintsZone(
            name: 'slow',
            minWaypointRelativePos: 0.1,
            maxWaypointRelativePos: 0.4,
            constraints: WaypointConstraints(
              maxVelocity: 1.5,
              maxAngularVelocity: 120,
              maxAngularAcceleration: 240,
            ),
          ),
          ConstraintsZone(name: 'second'),
        ],
        pointTowardsZones: [
          PointTowardsZone(
            name: 'speaker',
            fieldPosition: const Translation2d(1, 2),
            rotationOffset: Rotation2d.fromDegrees(180),
            minWaypointRelativePos: 0.3,
            maxWaypointRelativePos: 0.7,
            unprofiled: true,
          ),
        ],
        fs: fs,
        pathDir: pathsDir,
      );

      final json = original.toJson();
      final restored = path2.Path.fromJson(
        jsonDecode(jsonEncode(json)),
        original.name,
        pathsDir,
        fs,
      );
      final sortedExpected = original.duplicate(original.name)
        ..eventMarkers.sort(
            (a, b) => a.waypointRelativePos.compareTo(b.waypointRelativePos));

      expect(restored, sortedExpected);
      expect(restored.hashCode, sortedExpected.hashCode);
      expect(
        (json['eventMarkers'] as List).map((marker) => marker['name']),
        ['early', 'late'],
      );
      expect(
        (json['eventMarkers'] as List)
            .every((marker) => !marker.containsKey('color')),
        isTrue,
      );
      expect(
        (json['constraintZones'] as List).map((zone) => zone['name']),
        ['slow', 'second'],
      );
      expect(
        (json['pointTowardsZones'] as List).single['unprofiled'],
        isTrue,
      );
      final constraints =
          (json['constraintZones'] as List).first['constraints'] as Map;
      expect(
        constraints.keys,
        unorderedEquals([
          'maxVelocity',
          'maxAngularVelocity',
          'maxAngularAcceleration',
        ]),
      );
      expect(ProjectEventRegistry.events,
          containsAll(['early', 'late', 'nested']));
    });

    test('annotation positions and zone ordering are validated', () {
      expect(
        () => path2.Path(
          name: 'out of range',
          waypoints: [
            TranslationWaypoint(position: const Translation2d(0, 0)),
          ],
          eventMarkers: [EventMarker(waypointRelativePos: 0.1)],
          fs: fs,
          pathDir: pathsDir,
        ),
        throwsArgumentError,
      );

      expect(
        () => path2.Path.fromJson(
          {
            'version': path2.fileVersion,
            'waypoints': [
              {
                'type': 'translation',
                'position': {'x': 0, 'y': 0},
              },
              {
                'type': 'translation',
                'position': {'x': 1, 'y': 0},
              },
            ],
            'constraintZones': [
              {
                'name': 'backwards',
                'minWaypointRelativePos': 0.8,
                'maxWaypointRelativePos': 0.2,
                'constraints': {},
              },
            ],
          },
          'invalid',
          pathsDir,
          fs,
        ),
        throwsFormatException,
      );
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
        'pointTowardsZones': [
          {
            'name': 'legacy point zone',
            'fieldPosition': {'x': 2, 'y': 3},
            'rotationOffset': 0,
            'minWaypointRelativePos': 0,
            'maxWaypointRelativePos': 0,
          },
        ],
        'eventMarkers': [
          {
            'name': 'legacy marker',
            'waypointRelativePos': 0,
          },
        ],
      }, 'defaults', pathsDir, fs);

      expect(path.endToleranceMeters, 0.1);
      expect(path.endAngleToleranceDegrees, 2.0);
      expect(path.folder, isNull);
      expect(path.pointTowardsZones.single.unprofiled, isFalse);
      expect(
        (path.toJson()['eventMarkers'] as List).single.containsKey('color'),
        isFalse,
      );
    });

    test('runtime event marker palette has eight evenly spaced tinted hues',
        () {
      expect(eventMarkerColorPalette, hasLength(8));
      for (var i = 0; i < eventMarkerColorPalette.length; i++) {
        expect(eventMarkerColorForIndex(i), eventMarkerColorPalette[i]);
        expect(
          eventMarkerColorForIndex(i + eventMarkerColorPalette.length),
          eventMarkerColorPalette[i],
        );
      }

      for (var i = 0; i < eventMarkerColorPalette.length; i++) {
        final color = eventMarkerColorPalette[i];
        final red = (color >> 16) & 0xFF;
        final green = (color >> 8) & 0xFF;
        final blue = color & 0xFF;
        final maximum = [red, green, blue].reduce((a, b) => a > b ? a : b);
        final minimum = [red, green, blue].reduce((a, b) => a < b ? a : b);
        final delta = maximum - minimum;
        late double hue;
        if (maximum == red) {
          hue = 60 * ((green - blue) / delta % 6);
        } else if (maximum == green) {
          hue = 60 * ((blue - red) / delta + 2);
        } else {
          hue = 60 * ((red - green) / delta + 4);
        }
        if (hue < 0) {
          hue += 360;
        }

        expect(maximum, 135);
        expect(minimum, 66);
        expect(hue, closeTo(i * 45.0, 1.0));
      }
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

    test('straight-line sampling clamps and interpolates', () {
      final onePoint = path2.Path(
        name: 'one',
        waypoints: [
          TranslationWaypoint(position: const Translation2d(2, 3)),
        ],
        fs: fs,
        pathDir: pathsDir,
      );
      expect(onePoint.samplePath(-10), const Translation2d(2, 3));
      expect(onePoint.samplePath(10), const Translation2d(2, 3));

      final line = path2.Path(
        name: 'line',
        waypoints: [
          TranslationWaypoint(position: const Translation2d(0, 0)),
          TranslationWaypoint(position: const Translation2d(4, 2)),
          TranslationWaypoint(position: const Translation2d(8, 2)),
        ],
        fs: fs,
        pathDir: pathsDir,
      );
      expect(line.samplePath(-1), const Translation2d(0, 0));
      expect(line.samplePath(0.25), const Translation2d(1, 0.5));
      expect(line.samplePath(1.5), const Translation2d(6, 2));
      expect(line.samplePath(20), const Translation2d(8, 2));
    });

    test('waypoint insertion and deletion remap every annotation endpoint', () {
      final path = path2.Path(
        name: 'remap',
        waypoints: [
          TranslationWaypoint(position: const Translation2d(0, 0)),
          TranslationWaypoint(position: const Translation2d(2, 0)),
          TranslationWaypoint(position: const Translation2d(4, 0)),
        ],
        eventMarkers: [
          EventMarker(
            waypointRelativePos: 0.25,
            endWaypointRelativePos: 1.75,
          ),
        ],
        constraintZones: [
          ConstraintsZone(
            minWaypointRelativePos: 0.5,
            maxWaypointRelativePos: 1.5,
          ),
        ],
        pointTowardsZones: [
          PointTowardsZone(
            minWaypointRelativePos: 0.75,
            maxWaypointRelativePos: 2,
          ),
        ],
        fs: fs,
        pathDir: pathsDir,
      );

      path.insertWaypointAfter(0);
      expect(path.eventMarkers.single.waypointRelativePos, 0.5);
      expect(path.eventMarkers.single.endWaypointRelativePos, 2.75);
      expect(path.constraintZones.single.minWaypointRelativePos, 1);
      expect(path.constraintZones.single.maxWaypointRelativePos, 2.5);
      expect(path.pointTowardsZones.single.minWaypointRelativePos, 1.5);
      expect(path.pointTowardsZones.single.maxWaypointRelativePos, 3);

      path.removeWaypointAt(1);
      expect(path.eventMarkers.single.waypointRelativePos, 0.25);
      expect(path.eventMarkers.single.endWaypointRelativePos, 1.75);
      expect(path.constraintZones.single.minWaypointRelativePos, 0.5);
      expect(path.constraintZones.single.maxWaypointRelativePos, 1.5);
      expect(path.pointTowardsZones.single.minWaypointRelativePos, 0.75);
      expect(path.pointTowardsZones.single.maxWaypointRelativePos, 2);
    });

    test('append preserves annotations and endpoint deletion clamps ranges',
        () {
      path2.Path annotatedPath() => path2.Path(
            name: 'endpoints',
            waypoints: [
              TranslationWaypoint(position: const Translation2d(0, 0)),
              TranslationWaypoint(position: const Translation2d(2, 0)),
              TranslationWaypoint(position: const Translation2d(4, 0)),
            ],
            eventMarkers: [
              EventMarker(
                waypointRelativePos: 0.25,
                endWaypointRelativePos: 1.75,
              ),
            ],
            constraintZones: [
              ConstraintsZone(
                minWaypointRelativePos: 0.5,
                maxWaypointRelativePos: 2,
              ),
            ],
            pointTowardsZones: [
              PointTowardsZone(
                minWaypointRelativePos: 0.75,
                maxWaypointRelativePos: 1.25,
              ),
            ],
            fs: fs,
            pathDir: pathsDir,
          );

      final appended = annotatedPath();
      final beforeAppend = appended.snapshotAnnotations();
      appended.addWaypoint(const Translation2d(6, 0));
      expect(appended.eventMarkers, beforeAppend.eventMarkers);
      expect(appended.constraintZones, beforeAppend.constraintZones);
      expect(appended.pointTowardsZones, beforeAppend.pointTowardsZones);

      final firstDeleted = annotatedPath()..removeWaypointAt(0);
      expect(firstDeleted.eventMarkers.single.waypointRelativePos, 0);
      expect(firstDeleted.eventMarkers.single.endWaypointRelativePos, 0.75);
      expect(firstDeleted.constraintZones.single.minWaypointRelativePos, 0);
      expect(firstDeleted.constraintZones.single.maxWaypointRelativePos, 1);
      expect(firstDeleted.pointTowardsZones.single.minWaypointRelativePos, 0);
      expect(
          firstDeleted.pointTowardsZones.single.maxWaypointRelativePos, 0.25);

      final lastDeleted = annotatedPath()..removeWaypointAt(2);
      expect(lastDeleted.eventMarkers.single.waypointRelativePos, 0.25);
      expect(lastDeleted.eventMarkers.single.endWaypointRelativePos, 1);
      expect(lastDeleted.constraintZones.single.minWaypointRelativePos, 0.5);
      expect(lastDeleted.constraintZones.single.maxWaypointRelativePos, 1);
      expect(lastDeleted.pointTowardsZones.single.minWaypointRelativePos, 0.75);
      expect(lastDeleted.pointTowardsZones.single.maxWaypointRelativePos, 1);
    });

    test('deleting down to one waypoint collapses all annotation positions',
        () {
      final path = path2.Path(
        name: 'collapse',
        waypoints: [
          TranslationWaypoint(position: const Translation2d(0, 0)),
          TranslationWaypoint(position: const Translation2d(2, 0)),
        ],
        eventMarkers: [
          EventMarker(
            waypointRelativePos: 0.25,
            endWaypointRelativePos: 0.75,
          ),
        ],
        constraintZones: [
          ConstraintsZone(
            minWaypointRelativePos: 0.1,
            maxWaypointRelativePos: 0.9,
          ),
        ],
        pointTowardsZones: [
          PointTowardsZone(
            minWaypointRelativePos: 0.2,
            maxWaypointRelativePos: 0.8,
          ),
        ],
        fs: fs,
        pathDir: pathsDir,
      );

      path.removeWaypointAt(1);

      expect(path.waypoints, hasLength(1));
      expect(path.eventMarkers.single.waypointRelativePos, 0);
      expect(path.eventMarkers.single.endWaypointRelativePos, 0);
      expect(path.constraintZones.single.minWaypointRelativePos, 0);
      expect(path.constraintZones.single.maxWaypointRelativePos, 0);
      expect(path.pointTowardsZones.single.minWaypointRelativePos, 0);
      expect(path.pointTowardsZones.single.maxWaypointRelativePos, 0);
      expect(
        () => path2.Path.fromJson(
          jsonDecode(jsonEncode(path.toJson())),
          path.name,
          pathsDir,
          fs,
        ),
        returnsNormally,
      );
    });

    test('annotation snapshots restore deep clones and empty commands warn',
        () {
      final path = path2.Path(
        name: 'snapshot',
        waypoints: [
          TranslationWaypoint(position: const Translation2d(0, 0)),
        ],
        eventMarkers: [
          EventMarker(
            name: 'event',
            command: SequentialCommandGroup(
              commands: [NamedCommand()],
            ),
          ),
        ],
        constraintZones: [ConstraintsZone()],
        pointTowardsZones: [
          PointTowardsZone(
            minWaypointRelativePos: 0,
            maxWaypointRelativePos: 0,
          ),
        ],
        fs: fs,
        pathDir: pathsDir,
      );
      final snapshot = path.snapshotAnnotations();

      expect(path.hasEmptyNamedCommand(), isTrue);
      path.eventMarkers.single.name = 'changed';
      path.constraintZones.single.constraints.maxVelocity = 99;
      path.pointTowardsZones.clear();
      path.restoreAnnotations(snapshot);

      expect(path.eventMarkers.single.name, 'event');
      expect(path.constraintZones.single.constraints.maxVelocity,
          Waypoint.defaultMaxVelocity);
      expect(path.pointTowardsZones, hasLength(1));
      expect(identical(path.eventMarkers, snapshot.eventMarkers), isFalse);
      path.eventMarkers.single.name = 'changed again';
      expect(snapshot.eventMarkers.single.name, 'event');
    });

    test('duplicate deeply clones waypoints, annotations and path settings',
        () {
      final original = path2.Path(
        name: 'original',
        waypoints: [
          PoseWaypoint(
              position: const Translation2d(1, 2),
              rotation: Rotation2d.fromDegrees(45)),
        ],
        eventMarkers: [EventMarker(name: 'event')],
        constraintZones: [ConstraintsZone()],
        pointTowardsZones: [
          PointTowardsZone(
            minWaypointRelativePos: 0,
            maxWaypointRelativePos: 0,
          ),
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
      duplicate.eventMarkers.first.name = 'changed';
      duplicate.constraintZones.first.constraints.maxVelocity = 99;
      duplicate.pointTowardsZones.first.fieldPosition =
          const Translation2d(8, 9);

      expect(duplicate.name, 'copy');
      expect(duplicate.waypoints.first, isA<PoseWaypoint>());
      expect(identical(duplicate.waypoints.first, original.waypoints.first),
          false);
      expect(original.waypoints.first.position, const Translation2d(1, 2));
      expect(original.eventMarkers.first.name, 'event');
      expect(original.constraintZones.first.constraints.maxVelocity,
          Waypoint.defaultMaxVelocity);
      expect(original.pointTowardsZones.first.fieldPosition,
          const Translation2d(0.4, 5.5));
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

    test('old stored marker colors are ignored and removed when saved',
        () async {
      final file = fs.file(p.join(pathsDir, 'marker.path'));
      file.writeAsStringSync(jsonEncode({
        'version': path2.fileVersion,
        'waypoints': [
          {
            'type': 'translation',
            'position': {'x': 1, 'y': 2},
          }
        ],
        'eventMarkers': [
          {
            'name': 'legacy marker',
            'waypointRelativePos': 0,
          },
          {
            'name': 'old generated marker',
            'waypointRelativePos': 0,
            'color': 0xFF123456,
          },
        ],
      }));

      final loaded = await path2.Path.loadAllPathsInDir(pathsDir, fs);
      loaded.single.saveFile();
      final persisted = jsonDecode(file.readAsStringSync()) as Map;

      expect(
        (persisted['eventMarkers'] as List)
            .every((marker) => !marker.containsKey('color')),
        isTrue,
      );
    });

    test('missing directory loads as an empty list', () async {
      expect(
          await path2.Path.loadAllPathsInDir('/does-not-exist', fs), isEmpty);
    });
  });
}
