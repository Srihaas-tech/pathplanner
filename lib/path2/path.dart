import 'package:file/file.dart';
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';

const String fileVersion = '2027.0';

class Path {
  String name;
  List<Waypoint> waypoints;
  num endToleranceMeters;
  num endAngleToleranceDegrees;
  String? folder;

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
  DateTime lastModified = DateTime.now().toUtc();

  Path({
    required this.name,
    required this.waypoints,
    this.endToleranceMeters = 0.1,
    this.endAngleToleranceDegrees = 2.0,
    required this.fs,
    required this.pathDir,
    this.folder,
  });

  Path.defaultPath({
    required this.pathDir,
    required this.fs,
    this.name = 'New Path',
    this.folder,
  })  : waypoints = [],
        endToleranceMeters = 0.1,
        endAngleToleranceDegrees = 2.0 {
    waypoints.addAll([
      PoseWaypoint(
          position: const Translation2d(2.0, 7.0),
          rotation: const Rotation2d()),
      PoseWaypoint(
          position: const Translation2d(4.0, 6.0), rotation: const Rotation2d())
    ]);
  }

  Path.fromJson(
      Map<String, dynamic> json, String name, String pathsDir, FileSystem fs)
      : this(
          pathDir: pathsDir,
          fs: fs,
          name: name,
          waypoints: [
            for (final waypointJson in json['waypoints'])
              Waypoint.fromJson(waypointJson),
          ],
          endToleranceMeters: json['endToleranceMeters'],
          endAngleToleranceDegrees: json['endAngleToleranceDegrees'],
        );
}
