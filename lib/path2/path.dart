import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart';
import 'package:pathplanner/commands/command.dart';
import 'package:pathplanner/commands/command_groups.dart';
import 'package:pathplanner/commands/named_command.dart';
import 'package:pathplanner/path2/constraints_zone.dart';
import 'package:pathplanner/path2/event_marker.dart';
import 'package:pathplanner/path2/point_towards_zone.dart';
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/services/hot_reloadable_path.dart';
import 'package:pathplanner/services/log.dart';
import 'package:pathplanner/services/project_event_registry.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:version/version.dart';

const String fileVersion = '2027.0';

/// A deep-copyable snapshot of all waypoint-relative path annotations.
class PathAnnotationSnapshot {
  final List<EventMarker> eventMarkers;
  final List<ConstraintsZone> constraintZones;
  final List<PointTowardsZone> pointTowardsZones;

  const PathAnnotationSnapshot({
    required this.eventMarkers,
    required this.constraintZones,
    required this.pointTowardsZones,
  });
}

class Path implements HotReloadablePath {
  static final Version _minimumFileVersion = Version.parse(fileVersion);

  @override
  String name;
  List<Waypoint> waypoints;
  List<EventMarker> eventMarkers;
  List<ConstraintsZone> constraintZones;
  List<PointTowardsZone> pointTowardsZones;
  num endToleranceMeters;
  num endAngleToleranceDegrees;
  String? folder;

  /// The accepted version string read from disk.
  ///
  /// Keeping this verbatim prevents saving a path created by a newer release
  /// from silently replacing its version with this release's version.
  String sourceVersion;

  FileSystem fs;
  String pathDir;

  // Stuff used for UI
  bool waypointsExpanded = false;
  bool globalConstraintsExpanded = false;
  bool goalEndStateExpanded = false;
  bool rotationTargetsExpanded = false;
  bool eventMarkersExpanded = false;
  bool constraintZonesExpanded = false;
  bool pointTowardsZonesExpanded = false;
  bool previewStartingStateExpanded = false;
  bool pathOptimizationExpanded = false;
  bool pathConfigurationExpanded = false;
  DateTime lastModified = DateTime.now().toUtc();

  Path({
    required this.name,
    required this.waypoints,
    List<EventMarker>? eventMarkers,
    List<ConstraintsZone>? constraintZones,
    List<PointTowardsZone>? pointTowardsZones,
    this.endToleranceMeters = 0.1,
    this.endAngleToleranceDegrees = 2.0,
    required this.fs,
    required this.pathDir,
    this.folder,
    this.sourceVersion = fileVersion,
  })  : eventMarkers = eventMarkers ?? [],
        constraintZones = constraintZones ?? [],
        pointTowardsZones = pointTowardsZones ?? [] {
    if (waypoints.isEmpty) {
      throw ArgumentError.value(
          waypoints, 'waypoints', 'A path must have at least one waypoint');
    }
    _validateAnnotations();
    _collectEventNames();
  }

  Path.defaultPath({
    required this.pathDir,
    required this.fs,
    this.name = 'New Path',
    this.folder,
  })  : waypoints = [
          PoseWaypoint(
              position: const Translation2d(2.0, 7.0),
              rotation: const Rotation2d()),
          PoseWaypoint(
              position: const Translation2d(4.0, 6.0),
              rotation: const Rotation2d()),
        ],
        eventMarkers = [],
        constraintZones = [],
        pointTowardsZones = [],
        endToleranceMeters = 0.1,
        endAngleToleranceDegrees = 2.0,
        sourceVersion = fileVersion;

  factory Path.fromJson(
      Map<String, dynamic> json, String name, String pathsDir, FileSystem fs) {
    try {
      return Path(
        pathDir: pathsDir,
        fs: fs,
        name: name,
        waypoints: _waypointsFromJson(json),
        eventMarkers:
            _objectListFromJson(json, 'eventMarkers', EventMarker.fromJson),
        constraintZones: _objectListFromJson(
            json, 'constraintZones', ConstraintsZone.fromJson),
        pointTowardsZones: _objectListFromJson(
            json, 'pointTowardsZones', PointTowardsZone.fromJson),
        endToleranceMeters: _optionalNum(json, 'endToleranceMeters', 0.1),
        endAngleToleranceDegrees:
            _optionalNum(json, 'endAngleToleranceDegrees', 2.0),
        folder: _optionalFolder(json),
        sourceVersion: _validatedSourceVersion(json['version']),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid path annotations: ${error.message}');
    }
  }

  String get version => sourceVersion;

  @override
  Map<String, dynamic> toJson() {
    final sortedMarkers = List<EventMarker>.of(eventMarkers)
      ..sort((a, b) => a.waypointRelativePos.compareTo(b.waypointRelativePos));

    return {
      'version': sourceVersion,
      'waypoints': [
        for (final waypoint in waypoints) waypoint.toJson(),
      ],
      'eventMarkers': [
        for (final marker in sortedMarkers) marker.toJson(),
      ],
      'constraintZones': [
        for (final zone in constraintZones) zone.toJson(),
      ],
      'pointTowardsZones': [
        for (final zone in pointTowardsZones) zone.toJson(),
      ],
      'endToleranceMeters': endToleranceMeters,
      'endAngleToleranceDegrees': endAngleToleranceDegrees,
      'folder': folder,
    };
  }

  void saveFile() {
    try {
      final pathFile = fs.file(join(pathDir, '$name.path'));
      pathFile.parent.createSync(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      pathFile.writeAsStringSync(encoder.convert(toJson()));
      lastModified = DateTime.now().toUtc();
    } catch (ex, stack) {
      Log.error('Failed to save path: $name', ex, stack);
    }
  }

  static Future<List<Path>> loadAllPathsInDir(
      String pathsDir, FileSystem fs) async {
    final paths = <Path>[];
    final directory = fs.directory(pathsDir);

    if (!directory.existsSync()) {
      return paths;
    }

    List<FileSystemEntity> entities;
    try {
      entities = directory.listSync();
    } catch (ex, stack) {
      Log.error('Failed to list paths directory: $pathsDir', ex, stack);
      return paths;
    }

    for (final entity in entities) {
      if (!entity.path.endsWith('.path')) {
        continue;
      }

      try {
        final pathFile = fs.file(entity.path);
        final decoded = jsonDecode(pathFile.readAsStringSync());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Path file must contain a JSON object');
        }

        // Validate before constructing the path. In particular, rejected
        // legacy files must not be migrated or rewritten as a side effect.
        _validatedSourceVersion(decoded['version']);

        final path = Path.fromJson(
            decoded, basenameWithoutExtension(entity.path), pathsDir, fs);
        path.lastModified = pathFile.lastModifiedSync().toUtc();
        paths.add(path);
      } catch (ex, stack) {
        Log.error('Failed to load path: ${entity.path}', ex, stack);
      }
    }

    return paths;
  }

  void deletePath() {
    final pathFile = fs.file(join(pathDir, '$name.path'));
    if (pathFile.existsSync()) {
      pathFile.deleteSync();
    }
  }

  void renamePath(String newName) {
    final pathFile = fs.file(join(pathDir, '$name.path'));
    if (pathFile.existsSync()) {
      pathFile.renameSync(join(pathDir, '$newName.path'));
    }
    name = newName;
    lastModified = DateTime.now().toUtc();
  }

  Path duplicate(String newName) {
    return Path(
      name: newName,
      waypoints: cloneWaypoints(waypoints),
      eventMarkers: cloneEventMarkers(eventMarkers),
      constraintZones: cloneConstraintZones(constraintZones),
      pointTowardsZones: clonePointTowardsZones(pointTowardsZones),
      endToleranceMeters: endToleranceMeters,
      endAngleToleranceDegrees: endAngleToleranceDegrees,
      fs: fs,
      pathDir: pathDir,
      folder: folder,
      sourceVersion: sourceVersion,
    );
  }

  void addWaypoint(Translation2d position) {
    waypoints.add(TranslationWaypoint(position: position));
  }

  void insertWaypointAfter(int waypointIdx) {
    if (waypointIdx < 0 || waypointIdx >= waypoints.length - 1) {
      return;
    }

    final before = waypoints[waypointIdx].position;
    final after = waypoints[waypointIdx + 1].position;
    final insertedWaypointIdx = waypointIdx + 1;
    waypoints.insert(
        insertedWaypointIdx,
        TranslationWaypoint(
          position: before.interpolate(after, 0.5),
        ));
    _remapAnnotations(
        (position) => _positionAfterInsertion(position, insertedWaypointIdx));
  }

  /// Remove a waypoint and remap every waypoint-relative annotation.
  ///
  /// Removing the only waypoint, or passing an invalid index, is a no-op.
  void removeWaypointAt(int waypointIdx) {
    if (waypoints.length <= 1 ||
        waypointIdx < 0 ||
        waypointIdx >= waypoints.length) {
      return;
    }

    waypoints.removeAt(waypointIdx);
    _remapAnnotations(
        (position) => _positionAfterDeletion(position, waypointIdx));
  }

  /// Linearly sample the straight segment represented by a relative position.
  Translation2d samplePath(num waypointRelativePos) {
    if (waypoints.length == 1) {
      return waypoints.first.position;
    }

    final position =
        waypointRelativePos.clamp(0, waypoints.length - 1).toDouble();
    final segment = position.floor();
    if (segment >= waypoints.length - 1) {
      return waypoints.last.position;
    }

    return waypoints[segment]
        .position
        .interpolate(waypoints[segment + 1].position, position - segment);
  }

  List<Translation2d> get pathPositions => [
        for (final waypoint in waypoints) waypoint.position,
      ];

  static List<Waypoint> cloneWaypoints(List<Waypoint> waypoints) {
    return [
      for (final waypoint in waypoints) waypoint.clone(),
    ];
  }

  static List<EventMarker> cloneEventMarkers(List<EventMarker> markers) {
    return [for (final marker in markers) marker.clone()];
  }

  static List<ConstraintsZone> cloneConstraintZones(
      List<ConstraintsZone> zones) {
    return [for (final zone in zones) zone.clone()];
  }

  static List<PointTowardsZone> clonePointTowardsZones(
      List<PointTowardsZone> zones) {
    return [for (final zone in zones) zone.clone()];
  }

  PathAnnotationSnapshot snapshotAnnotations() {
    return PathAnnotationSnapshot(
      eventMarkers: cloneEventMarkers(eventMarkers),
      constraintZones: cloneConstraintZones(constraintZones),
      pointTowardsZones: clonePointTowardsZones(pointTowardsZones),
    );
  }

  void restoreAnnotations(PathAnnotationSnapshot snapshot) {
    eventMarkers = cloneEventMarkers(snapshot.eventMarkers);
    constraintZones = cloneConstraintZones(snapshot.constraintZones);
    pointTowardsZones = clonePointTowardsZones(snapshot.pointTowardsZones);
    _collectEventNames();
  }

  bool hasEmptyNamedCommand() {
    for (final marker in eventMarkers) {
      final command = marker.command;
      if (command != null && _hasEmptyNamedCommand(command)) {
        return true;
      }
    }
    return false;
  }

  void _validateAnnotations() {
    final maximum = waypoints.length - 1;

    void validatePosition(num position, String label) {
      if (!position.isFinite || position < 0 || position > maximum) {
        throw ArgumentError.value(position, label,
            'Must be between 0 and $maximum waypoint-relative units');
      }
    }

    for (final marker in eventMarkers) {
      validatePosition(marker.waypointRelativePos, 'event marker position');
      final endPosition = marker.endWaypointRelativePos;
      if (endPosition != null) {
        validatePosition(endPosition, 'event marker end position');
        if (endPosition < marker.waypointRelativePos) {
          throw ArgumentError.value(endPosition, 'event marker end position',
              'Must not be before the start position');
        }
      }
    }
    for (final zone in constraintZones) {
      validatePosition(
          zone.minWaypointRelativePos, 'constraints zone start position');
      validatePosition(
          zone.maxWaypointRelativePos, 'constraints zone end position');
      if (zone.maxWaypointRelativePos < zone.minWaypointRelativePos) {
        throw ArgumentError.value(
            zone.maxWaypointRelativePos,
            'constraints zone end position',
            'Must not be before the start position');
      }
    }
    for (final zone in pointTowardsZones) {
      validatePosition(
          zone.minWaypointRelativePos, 'point towards zone start position');
      validatePosition(
          zone.maxWaypointRelativePos, 'point towards zone end position');
      if (zone.maxWaypointRelativePos < zone.minWaypointRelativePos) {
        throw ArgumentError.value(
            zone.maxWaypointRelativePos,
            'point towards zone end position',
            'Must not be before the start position');
      }
    }
  }

  void _remapAnnotations(num Function(num position) remap) {
    for (final marker in eventMarkers) {
      marker.waypointRelativePos = remap(marker.waypointRelativePos);
      final endPosition = marker.endWaypointRelativePos;
      if (endPosition != null) {
        marker.endWaypointRelativePos = remap(endPosition);
      }
    }
    for (final zone in constraintZones) {
      zone.minWaypointRelativePos = remap(zone.minWaypointRelativePos);
      zone.maxWaypointRelativePos = remap(zone.maxWaypointRelativePos);
    }
    for (final zone in pointTowardsZones) {
      zone.minWaypointRelativePos = remap(zone.minWaypointRelativePos);
      zone.maxWaypointRelativePos = remap(zone.maxWaypointRelativePos);
    }
  }

  num _positionAfterInsertion(num position, int insertedWaypointIdx) {
    final remapped = position >= insertedWaypointIdx
        ? position + 1
        : position > insertedWaypointIdx - 1
            ? (insertedWaypointIdx - 1) +
                (2 * (position - (insertedWaypointIdx - 1)))
            : position;
    return remapped.clamp(0, waypoints.length - 1);
  }

  num _positionAfterDeletion(num position, int deletedWaypointIdx) {
    num remapped;
    if (position >= deletedWaypointIdx + 1) {
      remapped = position - 1;
    } else if (position >= deletedWaypointIdx) {
      remapped =
          (deletedWaypointIdx - 0.5) + ((position - position.floor()) * 0.5);
    } else if (position > deletedWaypointIdx - 1) {
      remapped = position.floor() + ((position - position.floor()) * 0.5);
    } else {
      remapped = position;
    }
    return remapped.clamp(0, waypoints.length - 1);
  }

  void _collectEventNames() {
    for (final marker in eventMarkers) {
      if (marker.name.isNotEmpty) {
        ProjectEventRegistry.events.add(marker.name);
      }
      final command = marker.command;
      if (command != null) {
        _collectNamedCommands(command);
      }
    }
  }

  static void _collectNamedCommands(Command command) {
    if (command is NamedCommand && command.name != null) {
      ProjectEventRegistry.events.add(command.name!);
    } else if (command is CommandGroup) {
      for (final child in command.commands) {
        _collectNamedCommands(child);
      }
    }
  }

  static bool _hasEmptyNamedCommand(Command command) {
    if (command is NamedCommand && command.name == null) {
      return true;
    }
    if (command is CommandGroup) {
      for (final child in command.commands) {
        if (_hasEmptyNamedCommand(child)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is Path &&
      other.name == name &&
      other.endToleranceMeters == endToleranceMeters &&
      other.endAngleToleranceDegrees == endAngleToleranceDegrees &&
      other.folder == folder &&
      other.sourceVersion == sourceVersion &&
      const ListEquality<Waypoint>().equals(other.waypoints, waypoints) &&
      const ListEquality<EventMarker>()
          .equals(other.eventMarkers, eventMarkers) &&
      const ListEquality<ConstraintsZone>()
          .equals(other.constraintZones, constraintZones) &&
      const ListEquality<PointTowardsZone>()
          .equals(other.pointTowardsZones, pointTowardsZones);

  @override
  int get hashCode => Object.hash(
      name,
      const ListEquality<Waypoint>().hash(waypoints),
      const ListEquality<EventMarker>().hash(eventMarkers),
      const ListEquality<ConstraintsZone>().hash(constraintZones),
      const ListEquality<PointTowardsZone>().hash(pointTowardsZones),
      endToleranceMeters,
      endAngleToleranceDegrees,
      folder,
      sourceVersion);

  static String _validatedSourceVersion(Object? value) {
    if (value is! String) {
      throw const FormatException('Path version must be a string');
    }

    final parsed = Version.parse(value);
    if (parsed < _minimumFileVersion) {
      throw FormatException(
          'Path version $value is older than the minimum $fileVersion');
    }
    return value;
  }
}

List<T> _objectListFromJson<T>(Map<String, dynamic> json, String key,
    T Function(Map<String, dynamic>) fromJson) {
  final value = json[key];
  if (value == null) {
    return [];
  }
  if (value is! List) {
    throw FormatException('$key must be a list');
  }

  return [
    for (final item in value)
      if (item is Map<String, dynamic>)
        fromJson(item)
      else
        throw FormatException('$key entries must be objects'),
  ];
}

List<Waypoint> _waypointsFromJson(Map<String, dynamic> json) {
  final waypointJson = json['waypoints'];
  if (waypointJson is! List || waypointJson.isEmpty) {
    throw const FormatException('A path must have at least one waypoint');
  }

  return [
    for (final waypoint in waypointJson)
      if (waypoint is Map<String, dynamic>)
        Waypoint.fromJson(waypoint)
      else
        throw const FormatException('Waypoint must be a JSON object'),
  ];
}

num _optionalNum(Map<String, dynamic> json, String key, num defaultValue) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is! num || !value.isFinite) {
    throw FormatException('$key must be a finite number');
  }
  return value;
}

String? _optionalFolder(Map<String, dynamic> json) {
  final folder = json['folder'];
  if (folder == null || folder is String) {
    return folder as String?;
  }
  throw const FormatException('Path folder must be a string or null');
}
