import 'package:pathplanner/util/wpimath/geometry.dart';

abstract class Waypoint {
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

  Map<String, dynamic> toJson();

  static Waypoint fromJson(Map<String, dynamic> json) {
    String type = json['type'];

    return switch (type) {
      'pose' => PoseWaypoint.fromJson(json),
      'translation' => TranslationWaypoint.fromJson(json),
      _ => throw ArgumentError('Unknon waypoint type'),
    };
  }
}

class TranslationWaypoint extends Waypoint {
  TranslationWaypoint({
    required super.position,
    super.maxVelocity,
    super.handoffDistance,
    super.maxAngularVelocity,
    super.maxAngularAcceleration,
  });

  TranslationWaypoint.fromJson(Map<String, dynamic> json)
      : super(
          position: Translation2d.fromJson(json['position']),
          maxVelocity: json['maxVelocity'],
          maxAngularVelocity: json['maxAngularVelocity'],
          maxAngularAcceleration: json['maxAngularAcceleration'],
        );

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'translation',
      'position': position.toJson(),
      'maxVelocity': maxVelocity,
      'maxAngularVelocity': maxAngularVelocity,
      'maxAngularAcceleration': maxAngularAcceleration,
    };
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

  PoseWaypoint.fromJson(Map<String, dynamic> json)
      : this(
          position: Translation2d.fromJson(json['position']),
          rotation: Rotation2d.fromJson(json['rotation']),
          maxVelocity: json['maxVelocity'],
          maxAngularVelocity: json['maxAngularVelocity'],
          maxAngularAcceleration: json['maxAngularAcceleration'],
        );

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'pose',
      'position': position.toJson(),
      'rotation': rotation.toJson(),
      'maxVelocity': maxVelocity,
      'maxAngularVelocity': maxAngularVelocity,
      'maxAngularAcceleration': maxAngularAcceleration,
    };
  }
}
