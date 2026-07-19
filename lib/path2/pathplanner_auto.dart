import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart';
import 'package:pathplanner/commands/command.dart';
import 'package:pathplanner/commands/command_groups.dart';
import 'package:pathplanner/commands/named_command.dart';
import 'package:pathplanner/commands/path_command.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/services/log.dart';
import 'package:pathplanner/services/project_event_registry.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:version/version.dart';

const String fileVersion = '2027.0';

/// The auto model used by the Path2 application.
///
/// Path2 autos always own a starting pose. [startingPoseInitialized] records
/// whether that pose has been chosen yet so adding, removing, or reordering
/// commands cannot unexpectedly move an auto that has already been seeded.
class Path2Auto {
  static final Version _minimumFileVersion = Version.parse(fileVersion);
  static const Pose2d _zeroPose = Pose2d(Translation2d(), Rotation2d());

  String name;
  SequentialCommandGroup sequence;
  Pose2d startingPose;
  bool startingPoseInitialized;
  String? folder;

  /// The accepted version string read from disk.
  ///
  /// Future versions are kept verbatim so an explicit save does not silently
  /// downgrade a file created by a newer release.
  String sourceVersion;

  FileSystem fs;
  String autoDir;

  DateTime lastModified = DateTime.now().toUtc();

  Path2Auto({
    required this.name,
    required this.sequence,
    required this.autoDir,
    required this.fs,
    this.startingPose = _zeroPose,
    this.startingPoseInitialized = false,
    this.folder,
    this.sourceVersion = fileVersion,
  }) {
    _validatePose(startingPose);
    _addNamedCommandsToEvents(sequence.commands);
  }

  Path2Auto.defaultAuto({
    this.name = 'New Auto',
    required this.autoDir,
    required this.fs,
    this.folder,
  })  : sequence = SequentialCommandGroup(commands: []),
        startingPose = _zeroPose,
        startingPoseInitialized = false,
        sourceVersion = fileVersion;

  factory Path2Auto.fromJson(
    Map<String, dynamic> json,
    String name,
    String autosDir,
    FileSystem fs, {
    Iterable<path2.Path> paths = const [],
  }) {
    final parsedVersion = _parseVersion(json['version']);
    final isLegacy =
        parsedVersion == null || parsedVersion < _minimumFileVersion;

    final commandJson = json['command'];
    if (commandJson is! Map<String, dynamic>) {
      throw const FormatException('Auto command must be an object');
    }
    final command = Command.fromJson(commandJson);
    if (command is! SequentialCommandGroup) {
      throw const FormatException('Auto command must be sequential');
    }

    final folder = json['folder'];
    if (folder != null && folder is! String) {
      throw const FormatException('Auto folder must be a string or null');
    }

    late final Pose2d startingPose;
    late final bool startingPoseInitialized;
    if (isLegacy) {
      startingPose = json.containsKey('startingPose')
          ? _poseFromJson(json['startingPose'])
          : (_firstResolvableStartingPose(command, paths) ?? _zeroPose);
      // Every migrated auto is initialized, including one that had to fall
      // back to the origin because none of its path references resolved.
      startingPoseInitialized = true;
    } else {
      startingPose = _poseFromJson(json['startingPose']);
      final initialized = json['startingPoseInitialized'];
      if (initialized is! bool) {
        throw const FormatException(
            'startingPoseInitialized must be a boolean');
      }
      startingPoseInitialized = initialized;
    }

    return Path2Auto(
      name: name,
      sequence: command,
      startingPose: startingPose,
      startingPoseInitialized: startingPoseInitialized,
      folder: folder as String?,
      sourceVersion: isLegacy ? fileVersion : json['version'] as String,
      autoDir: autosDir,
      fs: fs,
    );
  }

  String get version => sourceVersion;

  Map<String, dynamic> toJson() {
    return {
      'version': sourceVersion,
      'command': sequence.toJson(),
      'startingPose': {
        'position': startingPose.translation.toJson(),
        'rotation': startingPose.rotation.radians,
      },
      'startingPoseInitialized': startingPoseInitialized,
      'folder': folder,
    };
  }

  static Future<List<Path2Auto>> loadAllAutosInDir(
    String autosDir,
    FileSystem fs, {
    Iterable<path2.Path> paths = const [],
  }) async {
    final autos = <Path2Auto>[];
    final directory = fs.directory(autosDir);
    if (!directory.existsSync()) {
      return autos;
    }

    List<FileSystemEntity> entities;
    try {
      entities = directory.listSync();
    } catch (ex, stack) {
      Log.error('Failed to list autos directory: $autosDir', ex, stack);
      return autos;
    }

    for (final entity in entities) {
      if (!entity.path.endsWith('.auto')) {
        continue;
      }

      try {
        final file = fs.file(entity.path);
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Auto file must contain a JSON object');
        }

        // Choreo remains a legacy-only format. Filter it before parsing or
        // migrating so the Path2 application never mutates a hidden file.
        if (decoded['choreoAuto'] == true) {
          continue;
        }

        final auto = Path2Auto.fromJson(
          decoded,
          basenameWithoutExtension(entity.path),
          autosDir,
          fs,
          paths: paths,
        );
        auto.lastModified = file.lastModifiedSync().toUtc();

        // Migration is intentionally in-memory only. The next ordinary user
        // save persists the 2027 schema; merely opening a project is read-only.
        autos.add(auto);
      } catch (ex, stack) {
        Log.error('Failed to load Path2 auto: ${entity.path}', ex, stack);
      }
    }
    return autos;
  }

  Path2Auto duplicate(String newName) {
    return Path2Auto(
      name: newName,
      sequence: sequence.clone() as SequentialCommandGroup,
      startingPose: startingPose,
      startingPoseInitialized: startingPoseInitialized,
      autoDir: autoDir,
      fs: fs,
      folder: folder,
      sourceVersion: sourceVersion,
    );
  }

  void rename(String newName) {
    final autoFile = fs.file(join(autoDir, '$name.auto'));
    if (autoFile.existsSync()) {
      autoFile.renameSync(join(autoDir, '$newName.auto'));
    }
    name = newName;
    lastModified = DateTime.now().toUtc();
  }

  void delete() {
    final autoFile = fs.file(join(autoDir, '$name.auto'));
    if (autoFile.existsSync()) {
      autoFile.deleteSync();
    }
  }

  void saveFile() {
    try {
      final autoFile = fs.file(join(autoDir, '$name.auto'));
      autoFile.parent.createSync(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      autoFile.writeAsStringSync(encoder.convert(toJson()));
      lastModified = DateTime.now().toUtc();
      Log.debug('Saved "$name.auto"');
    } catch (ex, stack) {
      Log.error('Failed to save Path2 auto: $name', ex, stack);
    }
  }

  /// Sets a user-selected pose and permanently marks this auto initialized.
  void setStartingPose(Pose2d pose) {
    _validatePose(pose);
    startingPose = pose;
    startingPoseInitialized = true;
  }

  /// Seeds a new auto from its first currently resolvable path exactly once.
  ///
  /// Returns whether a pose was initialized. If no path reference resolves,
  /// this leaves the auto uninitialized so a path added later can seed it.
  bool initializeStartingPoseFromPaths(Iterable<path2.Path> paths) {
    if (startingPoseInitialized) {
      return false;
    }

    final pose = _firstResolvableStartingPose(sequence, paths);
    if (pose == null) {
      return false;
    }

    setStartingPose(pose);
    return true;
  }

  void updatePathName(String oldPathName, String newPathName) {
    _updatePathNameInCommands(sequence.commands, oldPathName, newPathName);
    saveFile();
  }

  List<String> getAllPathNames() {
    return _getPathNamesInCommands(sequence.commands);
  }

  bool hasEmptyPathCommands() {
    return _hasEmptyPathCommands(sequence.commands);
  }

  bool hasEmptyNamedCommand() {
    return _hasEmptyNamedCommand(sequence.commands);
  }

  void handleMissingPaths(List<String> pathNames) {
    _handleMissingPaths(sequence.commands, pathNames);
  }

  static Version? _parseVersion(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw const FormatException('Auto version must be a string');
    }
    try {
      return Version.parse(value);
    } catch (_) {
      throw FormatException('Invalid auto version: $value');
    }
  }

  static Pose2d _poseFromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('startingPose must be an object');
    }
    final position = value['position'];
    if (position is! Map<String, dynamic>) {
      throw const FormatException('startingPose.position must be an object');
    }
    final x = position['x'];
    final y = position['y'];
    final rotation = value['rotation'];
    if (x is! num ||
        y is! num ||
        rotation is! num ||
        !x.isFinite ||
        !y.isFinite ||
        !rotation.isFinite) {
      throw const FormatException(
          'startingPose must contain finite x, y, and rotation values');
    }
    return Pose2d(
      Translation2d(x, y),
      Rotation2d.fromRadians(rotation),
    );
  }

  static void _validatePose(Pose2d pose) {
    if (!pose.x.isFinite ||
        !pose.y.isFinite ||
        !pose.rotation.radians.isFinite) {
      throw ArgumentError.value(pose, 'startingPose', 'Pose must be finite');
    }
  }

  static Pose2d? _firstResolvableStartingPose(
    SequentialCommandGroup sequence,
    Iterable<path2.Path> paths,
  ) {
    final pathNames = _getPathNamesInCommands(sequence.commands);
    for (final pathName in pathNames) {
      path2.Path? resolvedPath;
      for (final candidate in paths) {
        if (candidate.name == pathName) {
          resolvedPath = candidate;
          break;
        }
      }
      if (resolvedPath == null) {
        continue;
      }

      final firstWaypoint = resolvedPath.waypoints.first;
      return Pose2d(
        firstWaypoint.position,
        firstWaypoint is PoseWaypoint
            ? firstWaypoint.rotation
            : const Rotation2d(),
      );
    }
    return null;
  }

  static void _updatePathNameInCommands(
    List<Command> commands,
    String oldPathName,
    String newPathName,
  ) {
    for (final command in commands) {
      if (command is PathCommand && command.pathName == oldPathName) {
        command.pathName = newPathName;
      } else if (command is CommandGroup) {
        _updatePathNameInCommands(command.commands, oldPathName, newPathName);
      }
    }
  }

  static void _addNamedCommandsToEvents(List<Command> commands) {
    for (final command in commands) {
      if (command is NamedCommand && command.name != null) {
        ProjectEventRegistry.events.add(command.name!);
      } else if (command is CommandGroup) {
        _addNamedCommandsToEvents(command.commands);
      }
    }
  }

  static List<String> _getPathNamesInCommands(List<Command> commands) {
    final names = <String>[];
    for (final command in commands) {
      if (command is PathCommand && command.pathName != null) {
        names.add(command.pathName!);
      } else if (command is CommandGroup) {
        names.addAll(_getPathNamesInCommands(command.commands));
      }
    }
    return names;
  }

  static bool _hasEmptyPathCommands(List<Command> commands) {
    for (final command in commands) {
      if (command is PathCommand && command.pathName == null) {
        return true;
      }
      if (command is CommandGroup && _hasEmptyPathCommands(command.commands)) {
        return true;
      }
    }
    return false;
  }

  static bool _hasEmptyNamedCommand(List<Command> commands) {
    for (final command in commands) {
      if (command is NamedCommand && command.name == null) {
        return true;
      }
      if (command is CommandGroup && _hasEmptyNamedCommand(command.commands)) {
        return true;
      }
    }
    return false;
  }

  static void _handleMissingPaths(
      List<Command> commands, List<String> pathNames) {
    for (final command in commands) {
      if (command is PathCommand && !pathNames.contains(command.pathName)) {
        command.pathName = null;
      } else if (command is CommandGroup) {
        _handleMissingPaths(command.commands, pathNames);
      }
    }
  }

  @override
  bool operator ==(Object other) {
    return other is Path2Auto &&
        other.name == name &&
        other.sequence == sequence &&
        other.startingPose.x == startingPose.x &&
        other.startingPose.y == startingPose.y &&
        other.startingPose.rotation.radians == startingPose.rotation.radians &&
        other.startingPoseInitialized == startingPoseInitialized &&
        other.folder == folder &&
        other.sourceVersion == sourceVersion;
  }

  @override
  int get hashCode => Object.hash(
        name,
        sequence,
        startingPose.x,
        startingPose.y,
        startingPose.rotation.radians,
        startingPoseInitialized,
        folder,
        sourceVersion,
      );
}
