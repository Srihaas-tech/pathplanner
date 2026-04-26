import 'package:pathplanner/util/wpimath/geometry.dart';

class Waypoint {
  Translation2d position;
  num maxVelocity;
  num handoffDistance;
  num maxAngularVelocity;
  num maxAngularAcceleration;

  Waypoint({
    required this.position,
    this.maxVelocity = 4.0,
    this.handoffDistance = 0.25,
    this.maxAngularVelocity = 360.0,
    this.maxAngularAcceleration = 720.0,
  });

  bool shouldHandoff(Translation2d currentPos) {
    return position.getDistance(currentPos) <= handoffDistance;
  }
}

class PoseWaypoint extends Waypoint {
  Rotation2d rotation;

  PoseWaypoint({
    required super.position,
    required this.rotation,
    super.maxVelocity,
    super.handoffDistance,
    super.maxAngularVelocity,
    super.maxAngularAcceleration,
  });
}
