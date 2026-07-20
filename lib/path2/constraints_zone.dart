import 'package:pathplanner/path2/waypoint.dart';

/// The waypoint constraints that can be overridden by a constraints zone.
///
/// Handoff distance belongs to waypoint targeting rather than motion limits,
/// so it is intentionally not part of a zone. Path 2 also has no independent
/// linear-acceleration constraint.
class WaypointConstraints {
  num maxVelocity;
  num maxAngularVelocity;
  num maxAngularAcceleration;

  WaypointConstraints({
    this.maxVelocity = Waypoint.defaultMaxVelocity,
    this.maxAngularVelocity = Waypoint.defaultMaxAngularVelocity,
    this.maxAngularAcceleration = Waypoint.defaultMaxAngularAcceleration,
  });

  WaypointConstraints.fromWaypoint(Waypoint waypoint)
      : this(
          maxVelocity: waypoint.maxVelocity,
          maxAngularVelocity: waypoint.maxAngularVelocity,
          maxAngularAcceleration: waypoint.maxAngularAcceleration,
        );

  WaypointConstraints.fromJson(Map<String, dynamic> json)
      : this(
          maxVelocity: _optionalFiniteNum(
              json, 'maxVelocity', Waypoint.defaultMaxVelocity),
          maxAngularVelocity: _optionalFiniteNum(
              json, 'maxAngularVelocity', Waypoint.defaultMaxAngularVelocity),
          maxAngularAcceleration: _optionalFiniteNum(json,
              'maxAngularAcceleration', Waypoint.defaultMaxAngularAcceleration),
        );

  Map<String, dynamic> toJson() {
    return {
      'maxVelocity': maxVelocity,
      'maxAngularVelocity': maxAngularVelocity,
      'maxAngularAcceleration': maxAngularAcceleration,
    };
  }

  WaypointConstraints clone() {
    return WaypointConstraints(
      maxVelocity: maxVelocity,
      maxAngularVelocity: maxAngularVelocity,
      maxAngularAcceleration: maxAngularAcceleration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WaypointConstraints &&
      other.maxVelocity == maxVelocity &&
      other.maxAngularVelocity == maxAngularVelocity &&
      other.maxAngularAcceleration == maxAngularAcceleration;

  @override
  int get hashCode =>
      Object.hash(maxVelocity, maxAngularVelocity, maxAngularAcceleration);
}

/// A waypoint-relative section of a path with alternate constraints.
class ConstraintsZone {
  num minWaypointRelativePos;
  num maxWaypointRelativePos;
  WaypointConstraints constraints;
  String name;

  ConstraintsZone({
    this.minWaypointRelativePos = 0,
    this.maxWaypointRelativePos = 0,
    WaypointConstraints? constraints,
    this.name = 'Constraints Zone',
  }) : constraints = constraints ?? WaypointConstraints();

  ConstraintsZone.fromJson(Map<String, dynamic> json)
      : name = _optionalString(json, 'name', 'Constraints Zone'),
        minWaypointRelativePos = _finiteNum(json, 'minWaypointRelativePos'),
        maxWaypointRelativePos = _finiteNum(json, 'maxWaypointRelativePos'),
        constraints = _constraintsFromJson(json['constraints']);

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'minWaypointRelativePos': minWaypointRelativePos,
      'maxWaypointRelativePos': maxWaypointRelativePos,
      'constraints': constraints.toJson(),
    };
  }

  ConstraintsZone clone() {
    return ConstraintsZone(
      name: name,
      minWaypointRelativePos: minWaypointRelativePos,
      maxWaypointRelativePos: maxWaypointRelativePos,
      constraints: constraints.clone(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ConstraintsZone &&
      other.name == name &&
      other.minWaypointRelativePos == minWaypointRelativePos &&
      other.maxWaypointRelativePos == maxWaypointRelativePos &&
      other.constraints == constraints;

  @override
  int get hashCode => Object.hash(
      name, minWaypointRelativePos, maxWaypointRelativePos, constraints);
}

WaypointConstraints _constraintsFromJson(Object? value) {
  if (value == null) {
    return WaypointConstraints();
  }
  if (value is! Map<String, dynamic>) {
    throw const FormatException('constraints must be an object');
  }
  return WaypointConstraints.fromJson(value);
}

String _optionalString(
    Map<String, dynamic> json, String key, String defaultValue) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is! String) {
    throw FormatException('$key must be a string');
  }
  return value;
}

num _finiteNum(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('$key must be a finite number');
  }
  return value;
}

num _optionalFiniteNum(
    Map<String, dynamic> json, String key, num defaultValue) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is! num || !value.isFinite) {
    throw FormatException('$key must be a finite number');
  }
  return value;
}
