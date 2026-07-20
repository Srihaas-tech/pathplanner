import 'package:pathplanner/util/wpimath/geometry.dart';

/// A waypoint-relative section that points the robot at a field position.
class PointTowardsZone {
  Translation2d fieldPosition;
  Rotation2d rotationOffset;
  num minWaypointRelativePos;
  num maxWaypointRelativePos;
  String name;
  bool unprofiled;

  PointTowardsZone({
    this.fieldPosition = const Translation2d(0.4, 5.5),
    this.rotationOffset = const Rotation2d(),
    this.minWaypointRelativePos = 0.25,
    this.maxWaypointRelativePos = 0.75,
    this.name = 'Point Towards Zone',
    this.unprofiled = false,
  });

  PointTowardsZone.fromJson(Map<String, dynamic> json)
      : fieldPosition = _translationFromJson(json['fieldPosition']),
        rotationOffset = Rotation2d.fromDegrees(
            _finiteNum(json, 'rotationOffset').toDouble()),
        minWaypointRelativePos = _finiteNum(json, 'minWaypointRelativePos'),
        maxWaypointRelativePos = _finiteNum(json, 'maxWaypointRelativePos'),
        name = _string(json, 'name'),
        unprofiled = _optionalBool(json, 'unprofiled', false);

  Map<String, dynamic> toJson() {
    return {
      'fieldPosition': fieldPosition.toJson(),
      'rotationOffset': rotationOffset.degrees,
      'minWaypointRelativePos': minWaypointRelativePos,
      'maxWaypointRelativePos': maxWaypointRelativePos,
      'name': name,
      'unprofiled': unprofiled,
    };
  }

  PointTowardsZone clone() {
    return PointTowardsZone(
      fieldPosition: fieldPosition,
      rotationOffset: rotationOffset,
      minWaypointRelativePos: minWaypointRelativePos,
      maxWaypointRelativePos: maxWaypointRelativePos,
      name: name,
      unprofiled: unprofiled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PointTowardsZone &&
      other.fieldPosition == fieldPosition &&
      other.rotationOffset == rotationOffset &&
      other.minWaypointRelativePos == minWaypointRelativePos &&
      other.maxWaypointRelativePos == maxWaypointRelativePos &&
      other.name == name &&
      other.unprofiled == unprofiled;

  @override
  int get hashCode => Object.hash(fieldPosition, rotationOffset,
      minWaypointRelativePos, maxWaypointRelativePos, name, unprofiled);
}

Translation2d _translationFromJson(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('fieldPosition must be an object');
  }
  final x = value['x'];
  final y = value['y'];
  if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
    throw const FormatException(
        'fieldPosition must contain finite x and y values');
  }
  return Translation2d(x, y);
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
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

bool _optionalBool(
  Map<String, dynamic> json,
  String key,
  bool defaultValue,
) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is! bool) {
    throw FormatException('$key must be a boolean');
  }
  return value;
}
