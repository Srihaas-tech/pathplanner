import 'package:pathplanner/path2/waypoint.dart';

class Path {
  List<Waypoint> waypoints;
  num endToleranceMeters;
  num endAngleToleranceDegrees;

  Path({
    required this.waypoints,
    this.endToleranceMeters = 0.1,
    this.endAngleToleranceDegrees = 2.0,
  });
}
