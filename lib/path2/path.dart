import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart';
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/services/hot_reloadable_path.dart';
import 'package:pathplanner/services/log.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:version/version.dart';

const String fileVersion = '2027.0';

class Path implements HotReloadablePath {
  static final Version _minimumFileVersion = Version.parse(fileVersion);

  @override
  String name;
  List<Waypoint> waypoints;
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
    this.endToleranceMeters = 0.1,
    this.endAngleToleranceDegrees = 2.0,
    required this.fs,
    required this.pathDir,
    this.folder,
    this.sourceVersion = fileVersion,
  }) {
    if (waypoints.isEmpty) {
      throw ArgumentError.value(
          waypoints, 'waypoints', 'A path must have at least one waypoint');
    }
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
        endToleranceMeters = 0.1,
        endAngleToleranceDegrees = 2.0,
        sourceVersion = fileVersion;

  Path.fromJson(
      Map<String, dynamic> json, String name, String pathsDir, FileSystem fs)
      : this(
          pathDir: pathsDir,
          fs: fs,
          name: name,
          waypoints: _waypointsFromJson(json),
          endToleranceMeters: _optionalNum(json, 'endToleranceMeters', 0.1),
          endAngleToleranceDegrees:
              _optionalNum(json, 'endAngleToleranceDegrees', 2.0),
          folder: _optionalFolder(json),
          sourceVersion: _validatedSourceVersion(json['version']),
        );

  String get version => sourceVersion;

  @override
  Map<String, dynamic> toJson() {
    return {
      'version': sourceVersion,
      'waypoints': [
        for (final waypoint in waypoints) waypoint.toJson(),
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
    waypoints.insert(
        waypointIdx + 1,
        TranslationWaypoint(
          position: before.interpolate(after, 0.5),
        ));
  }

  List<Translation2d> get pathPositions => [
        for (final waypoint in waypoints) waypoint.position,
      ];

  static List<Waypoint> cloneWaypoints(List<Waypoint> waypoints) {
    return [
      for (final waypoint in waypoints) waypoint.clone(),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is Path &&
      other.name == name &&
      other.endToleranceMeters == endToleranceMeters &&
      other.endAngleToleranceDegrees == endAngleToleranceDegrees &&
      other.folder == folder &&
      other.sourceVersion == sourceVersion &&
      const ListEquality<Waypoint>().equals(other.waypoints, waypoints);

  @override
  int get hashCode => Object.hash(
      name,
      const ListEquality<Waypoint>().hash(waypoints),
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
