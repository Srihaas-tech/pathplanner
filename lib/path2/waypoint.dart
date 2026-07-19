import 'dart:math';

import 'package:pathplanner/util/wpimath/geometry.dart';

abstract class Waypoint {
  static const num defaultMaxVelocity = 4.0;
  static const num defaultHandoffDistance = 0.25;
  static const num defaultMaxAngularVelocity = 360.0;
  static const num defaultMaxAngularAcceleration = 720.0;

  Translation2d position;
  num maxVelocity;
  num handoffDistance;
  num maxAngularVelocity;
  num maxAngularAcceleration;

  bool _isDragging = false;

  Waypoint({
    required this.position,
    this.maxVelocity = defaultMaxVelocity,
    this.handoffDistance = defaultHandoffDistance,
    this.maxAngularVelocity = defaultMaxAngularVelocity,
    this.maxAngularAcceleration = defaultMaxAngularAcceleration,
  });

  bool get isDragging => _isDragging;

  bool get isAnchorDragging => _isDragging;

  bool shouldHandoff(Translation2d currentPos) {
    return position.getDistance(currentPos) <= handoffDistance;
  }

  void move(num x, num y) {
    position = Translation2d(x, y);
  }

  bool isPointInAnchor(num xPos, num yPos, num radius) {
    return pow(xPos - position.x, 2) + pow(yPos - position.y, 2) <
        pow(radius, 2);
  }

  bool startDragging(num xPos, num yPos, num radius) {
    if (isPointInAnchor(xPos, yPos, radius)) {
      _isDragging = true;
    }
    return _isDragging;
  }

  void dragUpdate(num x, num y) {
    if (_isDragging) {
      move(x, y);
    }
  }

  void stopDragging() {
    _isDragging = false;
  }

  Waypoint clone();

  Waypoint withRotation(Rotation2d? rotation) {
    if (rotation == null) {
      return TranslationWaypoint(
        position: position,
        maxVelocity: maxVelocity,
        handoffDistance: handoffDistance,
        maxAngularVelocity: maxAngularVelocity,
        maxAngularAcceleration: maxAngularAcceleration,
      );
    }

    return PoseWaypoint(
      position: position,
      rotation: rotation,
      maxVelocity: maxVelocity,
      handoffDistance: handoffDistance,
      maxAngularVelocity: maxAngularVelocity,
      maxAngularAcceleration: maxAngularAcceleration,
    );
  }

  Map<String, dynamic> toJson();

  static Waypoint fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) {
      throw const FormatException('Waypoint type must be a string');
    }

    return switch (type) {
      'pose' => PoseWaypoint.fromJson(json),
      'translation' => TranslationWaypoint.fromJson(json),
      _ => throw FormatException('Unknown waypoint type: $type'),
    };
  }

  Map<String, dynamic> commonJson(String type) {
    return {
      'type': type,
      'position': position.toJson(),
      'maxVelocity': maxVelocity,
      'handoffDistance': handoffDistance,
      'maxAngularVelocity': maxAngularVelocity,
      'maxAngularAcceleration': maxAngularAcceleration,
    };
  }

  bool commonEquals(Waypoint other) {
    return other.position == position &&
        other.maxVelocity == maxVelocity &&
        other.handoffDistance == handoffDistance &&
        other.maxAngularVelocity == maxAngularVelocity &&
        other.maxAngularAcceleration == maxAngularAcceleration;
  }

  int get commonHashCode => Object.hash(position, maxVelocity, handoffDistance,
      maxAngularVelocity, maxAngularAcceleration);
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
      : this(
          position: _positionFromJson(json),
          maxVelocity:
              _optionalNum(json, 'maxVelocity', Waypoint.defaultMaxVelocity),
          handoffDistance: _optionalNum(
              json, 'handoffDistance', Waypoint.defaultHandoffDistance),
          maxAngularVelocity: _optionalNum(
              json, 'maxAngularVelocity', Waypoint.defaultMaxAngularVelocity),
          maxAngularAcceleration: _optionalNum(json, 'maxAngularAcceleration',
              Waypoint.defaultMaxAngularAcceleration),
        );

  @override
  TranslationWaypoint clone() {
    return TranslationWaypoint(
      position: position,
      maxVelocity: maxVelocity,
      handoffDistance: handoffDistance,
      maxAngularVelocity: maxAngularVelocity,
      maxAngularAcceleration: maxAngularAcceleration,
    );
  }

  @override
  Map<String, dynamic> toJson() => commonJson('translation');

  @override
  bool operator ==(Object other) =>
      other is TranslationWaypoint && commonEquals(other);

  @override
  int get hashCode => commonHashCode;
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
          position: _positionFromJson(json),
          rotation: _rotationFromJson(json),
          maxVelocity:
              _optionalNum(json, 'maxVelocity', Waypoint.defaultMaxVelocity),
          handoffDistance: _optionalNum(
              json, 'handoffDistance', Waypoint.defaultHandoffDistance),
          maxAngularVelocity: _optionalNum(
              json, 'maxAngularVelocity', Waypoint.defaultMaxAngularVelocity),
          maxAngularAcceleration: _optionalNum(json, 'maxAngularAcceleration',
              Waypoint.defaultMaxAngularAcceleration),
        );

  @override
  PoseWaypoint clone() {
    return PoseWaypoint(
      position: position,
      rotation: rotation,
      maxVelocity: maxVelocity,
      handoffDistance: handoffDistance,
      maxAngularVelocity: maxAngularVelocity,
      maxAngularAcceleration: maxAngularAcceleration,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...commonJson('pose'),
      'rotation': rotation.toJson(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is PoseWaypoint &&
      commonEquals(other) &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(commonHashCode, rotation);
}

Translation2d _positionFromJson(Map<String, dynamic> json) {
  final position = json['position'];
  if (position is! Map<String, dynamic>) {
    throw const FormatException('Waypoint position must be an object');
  }

  final x = position['x'];
  final y = position['y'];
  if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
    throw const FormatException(
        'Waypoint position must contain finite x and y values');
  }

  return Translation2d(x, y);
}

Rotation2d _rotationFromJson(Map<String, dynamic> json) {
  final rotation = json['rotation'];
  if (rotation is! Map<String, dynamic>) {
    throw const FormatException('Pose waypoint rotation must be an object');
  }

  final value = rotation['value'];
  if (value is! num || !value.isFinite) {
    throw const FormatException(
        'Pose waypoint rotation must contain a finite value');
  }

  return Rotation2d(value);
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
