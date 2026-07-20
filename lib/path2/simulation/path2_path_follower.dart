import 'dart:math' as math;

import 'package:pathplanner/path2/constraints_zone.dart';
import 'package:pathplanner/path2/event_marker.dart';
import 'package:pathplanner/path2/point_towards_zone.dart';
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/util/wpimath/kinematics.dart';

/// Primitive-only constraints used by the Path2 simulation isolate.
class Path2SimulationConstraints {
  final double maxVelocity;
  final double maxAngularVelocityRadiansPerSecond;
  final double maxAngularAccelerationRadiansPerSecondSquared;

  const Path2SimulationConstraints({
    required this.maxVelocity,
    required this.maxAngularVelocityRadiansPerSecond,
    required this.maxAngularAccelerationRadiansPerSecondSquared,
  });

  factory Path2SimulationConstraints.fromWaypoint(Waypoint waypoint) {
    return Path2SimulationConstraints(
      maxVelocity: waypoint.maxVelocity.toDouble(),
      maxAngularVelocityRadiansPerSecond:
          _degreesToRadians(waypoint.maxAngularVelocity.toDouble()),
      maxAngularAccelerationRadiansPerSecondSquared:
          _degreesToRadians(waypoint.maxAngularAcceleration.toDouble()),
    );
  }

  factory Path2SimulationConstraints.fromModel(
    WaypointConstraints constraints,
  ) {
    return Path2SimulationConstraints(
      maxVelocity: constraints.maxVelocity.toDouble(),
      maxAngularVelocityRadiansPerSecond:
          _degreesToRadians(constraints.maxAngularVelocity.toDouble()),
      maxAngularAccelerationRadiansPerSecondSquared:
          _degreesToRadians(constraints.maxAngularAcceleration.toDouble()),
    );
  }

  factory Path2SimulationConstraints.fromMap(Map<String, dynamic> map) {
    return Path2SimulationConstraints(
      maxVelocity: (map['maxVelocity'] as num).toDouble(),
      maxAngularVelocityRadiansPerSecond:
          (map['maxAngularVelocityRadiansPerSecond'] as num).toDouble(),
      maxAngularAccelerationRadiansPerSecondSquared:
          (map['maxAngularAccelerationRadiansPerSecondSquared'] as num)
              .toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'maxVelocity': maxVelocity,
        'maxAngularVelocityRadiansPerSecond':
            maxAngularVelocityRadiansPerSecond,
        'maxAngularAccelerationRadiansPerSecondSquared':
            maxAngularAccelerationRadiansPerSecondSquared,
      };
}

/// Primitive-only event marker definition used by the simulation isolate.
class Path2SimulationEventMarker {
  final double waypointRelativePosition;
  final double? endWaypointRelativePosition;

  const Path2SimulationEventMarker({
    required this.waypointRelativePosition,
    this.endWaypointRelativePosition,
  });

  factory Path2SimulationEventMarker.fromMarker(EventMarker marker) {
    return Path2SimulationEventMarker(
      waypointRelativePosition: marker.waypointRelativePos.toDouble(),
      endWaypointRelativePosition: marker.endWaypointRelativePos?.toDouble(),
    );
  }

  factory Path2SimulationEventMarker.fromMap(Map<String, dynamic> map) {
    final endPosition = map['endWaypointRelativePosition'];
    return Path2SimulationEventMarker(
      waypointRelativePosition:
          (map['waypointRelativePosition'] as num).toDouble(),
      endWaypointRelativePosition:
          endPosition is num ? endPosition.toDouble() : null,
    );
  }

  bool get isZoned => endWaypointRelativePosition != null;

  Map<String, dynamic> toMap() => {
        'waypointRelativePosition': waypointRelativePosition,
        'endWaypointRelativePosition': endWaypointRelativePosition,
      };
}

/// Primitive-only constraints zone used by the simulation isolate.
class Path2SimulationConstraintsZone {
  final double minWaypointRelativePosition;
  final double maxWaypointRelativePosition;
  final Path2SimulationConstraints constraints;

  const Path2SimulationConstraintsZone({
    required this.minWaypointRelativePosition,
    required this.maxWaypointRelativePosition,
    required this.constraints,
  });

  factory Path2SimulationConstraintsZone.fromZone(ConstraintsZone zone) {
    return Path2SimulationConstraintsZone(
      minWaypointRelativePosition: zone.minWaypointRelativePos.toDouble(),
      maxWaypointRelativePosition: zone.maxWaypointRelativePos.toDouble(),
      constraints: Path2SimulationConstraints.fromModel(zone.constraints),
    );
  }

  factory Path2SimulationConstraintsZone.fromMap(Map<String, dynamic> map) {
    return Path2SimulationConstraintsZone(
      minWaypointRelativePosition:
          (map['minWaypointRelativePosition'] as num).toDouble(),
      maxWaypointRelativePosition:
          (map['maxWaypointRelativePosition'] as num).toDouble(),
      constraints: Path2SimulationConstraints.fromMap(
        Map<String, dynamic>.from(map['constraints'] as Map),
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'minWaypointRelativePosition': minWaypointRelativePosition,
        'maxWaypointRelativePosition': maxWaypointRelativePosition,
        'constraints': constraints.toMap(),
      };
}

/// Primitive-only point-towards zone used by the simulation isolate.
class Path2SimulationPointTowardsZone {
  final Translation2d fieldPosition;
  final Rotation2d rotationOffset;
  final double minWaypointRelativePosition;
  final double maxWaypointRelativePosition;
  final bool unprofiled;

  const Path2SimulationPointTowardsZone({
    required this.fieldPosition,
    required this.rotationOffset,
    required this.minWaypointRelativePosition,
    required this.maxWaypointRelativePosition,
    this.unprofiled = false,
  });

  factory Path2SimulationPointTowardsZone.fromZone(PointTowardsZone zone) {
    return Path2SimulationPointTowardsZone(
      fieldPosition: zone.fieldPosition,
      rotationOffset: zone.rotationOffset,
      minWaypointRelativePosition: zone.minWaypointRelativePos.toDouble(),
      maxWaypointRelativePosition: zone.maxWaypointRelativePos.toDouble(),
      unprofiled: zone.unprofiled,
    );
  }

  factory Path2SimulationPointTowardsZone.fromMap(Map<String, dynamic> map) {
    return Path2SimulationPointTowardsZone(
      fieldPosition: Translation2d(
        (map['fieldX'] as num).toDouble(),
        (map['fieldY'] as num).toDouble(),
      ),
      rotationOffset: Rotation2d.fromRadians(
        (map['rotationOffsetRadians'] as num).toDouble(),
      ),
      minWaypointRelativePosition:
          (map['minWaypointRelativePosition'] as num).toDouble(),
      maxWaypointRelativePosition:
          (map['maxWaypointRelativePosition'] as num).toDouble(),
      unprofiled: map['unprofiled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'fieldX': fieldPosition.x.toDouble(),
        'fieldY': fieldPosition.y.toDouble(),
        'rotationOffsetRadians': rotationOffset.radians.toDouble(),
        'minWaypointRelativePosition': minWaypointRelativePosition,
        'maxWaypointRelativePosition': maxWaypointRelativePosition,
        'unprofiled': unprofiled,
      };
}

/// A marker state change emitted by [Path2PathFollower].
class Path2SimulationMarkerTransition {
  final int markerIndex;
  final bool isZoned;
  final bool active;

  const Path2SimulationMarkerTransition({
    required this.markerIndex,
    required this.isZoned,
    required this.active,
  });
}

/// A file-system-free waypoint used by the deterministic Path2 simulator.
class Path2SimulationWaypoint {
  final Translation2d position;
  final Rotation2d? rotation;
  final double maxVelocity;
  final double handoffDistance;
  final double maxAngularVelocityRadiansPerSecond;
  final double maxAngularAccelerationRadiansPerSecondSquared;

  const Path2SimulationWaypoint({
    required this.position,
    required this.rotation,
    required this.maxVelocity,
    required this.handoffDistance,
    required this.maxAngularVelocityRadiansPerSecond,
    required this.maxAngularAccelerationRadiansPerSecondSquared,
  });

  Path2SimulationConstraints get constraints => Path2SimulationConstraints(
        maxVelocity: maxVelocity,
        maxAngularVelocityRadiansPerSecond: maxAngularVelocityRadiansPerSecond,
        maxAngularAccelerationRadiansPerSecondSquared:
            maxAngularAccelerationRadiansPerSecondSquared,
      );

  factory Path2SimulationWaypoint.fromWaypoint(Waypoint waypoint) {
    return Path2SimulationWaypoint(
      position: waypoint.position,
      rotation: waypoint is PoseWaypoint ? waypoint.rotation : null,
      maxVelocity: waypoint.maxVelocity.toDouble(),
      handoffDistance: waypoint.handoffDistance.toDouble(),
      maxAngularVelocityRadiansPerSecond:
          _degreesToRadians(waypoint.maxAngularVelocity.toDouble()),
      maxAngularAccelerationRadiansPerSecondSquared:
          _degreesToRadians(waypoint.maxAngularAcceleration.toDouble()),
    );
  }

  factory Path2SimulationWaypoint.fromMap(Map<String, dynamic> map) {
    final rotation = map['rotationRadians'];
    return Path2SimulationWaypoint(
      position: Translation2d(
        (map['x'] as num).toDouble(),
        (map['y'] as num).toDouble(),
      ),
      rotation:
          rotation is num ? Rotation2d.fromRadians(rotation.toDouble()) : null,
      maxVelocity: (map['maxVelocity'] as num).toDouble(),
      handoffDistance: (map['handoffDistance'] as num).toDouble(),
      maxAngularVelocityRadiansPerSecond:
          (map['maxAngularVelocityRadiansPerSecond'] as num).toDouble(),
      maxAngularAccelerationRadiansPerSecondSquared:
          (map['maxAngularAccelerationRadiansPerSecondSquared'] as num)
              .toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'x': position.x.toDouble(),
        'y': position.y.toDouble(),
        'rotationRadians': rotation?.radians.toDouble(),
        'maxVelocity': maxVelocity,
        'handoffDistance': handoffDistance,
        'maxAngularVelocityRadiansPerSecond':
            maxAngularVelocityRadiansPerSecond,
        'maxAngularAccelerationRadiansPerSecondSquared':
            maxAngularAccelerationRadiansPerSecondSquared,
      };
}

/// The controller portion of the supplied `FollowDynamicPath` command.
///
/// Robot lifecycle, alliance flipping, arbitrary Boolean handoff conditions,
/// beaching, and subsystem output have deliberately been left out. The caller
/// passes the returned robot-relative speeds through the swerve setpoint
/// generator before integrating the simulated robot state.
class Path2PathFollower {
  static const double periodSeconds = 0.02;

  final List<Path2SimulationWaypoint> waypoints;
  final List<Path2SimulationEventMarker> eventMarkers;
  final List<Path2SimulationConstraintsZone> constraintZones;
  final List<Path2SimulationPointTowardsZone> pointTowardsZones;
  final double endToleranceMeters;
  final double endAngleToleranceRadians;

  final _PidController _translationController =
      _PidController(4.0, periodSeconds);
  final _PidController _crossTrackController =
      _PidController(2.0, periodSeconds);
  final _PidController _unprofiledRotationController =
      _PidController(5.0, periodSeconds);
  late final _ProfiledPidController _rotationController;

  late int _targetWaypointIndex;
  late Translation2d _segmentStart;
  late Translation2d _segmentEnd;
  Rotation2d? _heldHeading;
  late final List<_MarkerRuntime> _markerRuntimes;
  late final List<_ZoneRuntime<Path2SimulationConstraintsZone>>
      _constraintZoneRuntimes;
  late final List<_ZoneRuntime<Path2SimulationPointTowardsZone>>
      _pointTowardsZoneRuntimes;
  final List<Path2SimulationMarkerTransition> _pendingMarkerTransitions = [];
  bool _finalized = false;
  bool _usingUnprofiledRotation = false;

  Path2PathFollower({
    required this.waypoints,
    this.eventMarkers = const [],
    this.constraintZones = const [],
    this.pointTowardsZones = const [],
    required this.endToleranceMeters,
    required this.endAngleToleranceRadians,
    required Pose2d initialPose,
    required ChassisSpeeds initialRobotRelativeSpeeds,
    required bool targetFirstWaypoint,
  }) {
    if (waypoints.isEmpty) {
      throw ArgumentError.value(waypoints, 'waypoints', 'Must not be empty');
    }

    _targetWaypointIndex = targetFirstWaypoint || waypoints.length == 1 ? 0 : 1;
    _segmentStart = targetFirstWaypoint
        ? initialPose.translation
        : waypoints.first.position;
    _segmentEnd = waypoints[_targetWaypointIndex].position;

    _markerRuntimes = [
      for (var index = 0; index < eventMarkers.length; index++)
        _MarkerRuntime(
          index,
          eventMarkers[index],
          _createBoundaryTracker(
            eventMarkers[index].waypointRelativePosition,
            initialPose.translation,
          ),
          end: eventMarkers[index].endWaypointRelativePosition == null
              ? null
              : _createBoundaryTracker(
                  eventMarkers[index].endWaypointRelativePosition!,
                  initialPose.translation,
                ),
        ),
    ];
    _constraintZoneRuntimes = [
      for (final zone in constraintZones)
        _ZoneRuntime(
          zone,
          _createBoundaryTracker(
            zone.minWaypointRelativePosition,
            initialPose.translation,
          ),
          _createBoundaryTracker(
            zone.maxWaypointRelativePosition,
            initialPose.translation,
          ),
        ),
    ];
    _pointTowardsZoneRuntimes = [
      for (final zone in pointTowardsZones)
        _ZoneRuntime(
          zone,
          _createBoundaryTracker(
            zone.minWaypointRelativePosition,
            initialPose.translation,
          ),
          _createBoundaryTracker(
            zone.maxWaypointRelativePosition,
            initialPose.translation,
          ),
        ),
    ];

    _updateBoundaryStates(initialPose);

    final constraints = _trapezoidConstraints(_activeConstraints());
    _rotationController = _ProfiledPidController(
      5.0,
      periodSeconds,
      constraints,
    )
      ..enableContinuousInput(-math.pi, math.pi)
      ..setTolerance(endAngleToleranceRadians)
      ..reset(initialPose.rotation.radians.toDouble(),
          initialRobotRelativeSpeeds.omega.toDouble());

    _translationController
      ..setTolerance(endToleranceMeters)
      ..reset();
    _crossTrackController
      ..setTolerance(endToleranceMeters)
      ..reset();
    _unprofiledRotationController
      ..enableContinuousInput(-math.pi, math.pi)
      ..setTolerance(endAngleToleranceRadians)
      ..reset();
    _updateHeldHeading(initialPose.rotation);
  }

  int get targetWaypointIndex => _targetWaypointIndex;

  bool get isFinished =>
      _targetWaypointIndex == waypoints.length - 1 &&
      _translationController.atSetpoint &&
      (_usingUnprofiledRotation
          ? _unprofiledRotationController.atSetpoint
          : _rotationController.atSetpoint);

  /// Returns marker transitions emitted since the previous call.
  List<Path2SimulationMarkerTransition> takeMarkerTransitions() {
    final transitions = List<Path2SimulationMarkerTransition>.unmodifiable(
      _pendingMarkerTransitions,
    );
    _pendingMarkerTransitions.clear();
    return transitions;
  }

  /// Resolve pending closest-approach boundaries at the terminal pose.
  ///
  /// A path can finish while its final-boundary distance is still decreasing.
  /// Every pending marker is fired at the terminal sample, and active marker
  /// zones are always closed there so their simulation trace is finite.
  void finalize(Pose2d terminalPose) {
    if (_finalized) {
      return;
    }
    _finalized = true;
    _updateBoundaryStates(terminalPose);

    for (final marker in _markerRuntimes) {
      if (!marker.started && marker.start.force()) {
        _startMarker(marker);
      }
      if (marker.definition.isZoned && marker.started && !marker.ended) {
        marker.end?.force();
        _endMarker(marker);
      }
    }

    for (final zone in _constraintZoneRuntimes) {
      if (!zone.active && zone.start.forceIfApproached(_targetWaypointIndex)) {
        zone.active = true;
      }
      if (zone.active) {
        zone.end.forceIfApproached(_targetWaypointIndex);
        zone.active = false;
      }
    }
    for (final zone in _pointTowardsZoneRuntimes) {
      if (!zone.active && zone.start.forceIfApproached(_targetWaypointIndex)) {
        zone.active = true;
      }
      if (zone.active) {
        zone.end.forceIfApproached(_targetWaypointIndex);
        zone.active = false;
      }
    }
  }

  /// Calculate the unconstrained robot-relative request for one 20 ms tick.
  ChassisSpeeds calculate(
    Pose2d currentPose, [
    ChassisSpeeds currentRobotRelativeSpeeds = const ChassisSpeeds(),
  ]) {
    _advanceTargetIfNeeded(currentPose);
    _updateBoundaryStates(currentPose);

    final useUnprofiledRotation =
        _activePointTowardsZone()?.unprofiled ?? false;
    if (useUnprofiledRotation != _usingUnprofiledRotation) {
      if (useUnprofiledRotation) {
        _unprofiledRotationController.reset();
      } else {
        _rotationController.reset(
          currentPose.rotation.radians.toDouble(),
          currentRobotRelativeSpeeds.omega.toDouble(),
        );
      }
      _usingUnprofiledRotation = useUnprofiledRotation;
    }

    final activeConstraints = _activeConstraints();
    _rotationController.setConstraints(
      _trapezoidConstraints(activeConstraints),
    );

    final remainingDistance = _calculateRemainingPathDistance(currentPose);
    final toTarget = _segmentEnd - currentPose.translation;
    final angleToTarget = toTarget.angle;

    var translationOutput =
        -_translationController.calculate(remainingDistance, 0.0);
    final maxVelocity = activeConstraints.maxVelocity;
    translationOutput =
        translationOutput.clamp(-maxVelocity, maxVelocity).toDouble();

    var vx = translationOutput * angleToTarget.cosine;
    var vy = translationOutput * angleToTarget.sine;

    final crossTrackOutput = -_crossTrackController.calculate(
        _calculateCrossTrackError(currentPose), 0.0);
    final perpendicular = angleToTarget - Rotation2d.fromRadians(math.pi / 2.0);
    vx += crossTrackOutput * perpendicular.cosine;
    vy += crossTrackOutput * perpendicular.sine;

    final targetHeading = _rotationTarget(currentPose);
    final rotationOutput = _usingUnprofiledRotation
        ? _unprofiledRotationController.calculate(
            currentPose.rotation.radians.toDouble(),
            targetHeading.radians.toDouble(),
          )
        : _rotationController.calculate(
            currentPose.rotation.radians.toDouble(),
            targetHeading.radians.toDouble(),
          );

    return ChassisSpeeds.fromFieldRelativeSpeeds(
      ChassisSpeeds(vx: vx, vy: vy, omega: rotationOutput),
      currentPose.rotation,
    );
  }

  void _advanceTargetIfNeeded(Pose2d currentPose) {
    if (_targetWaypointIndex >= waypoints.length - 1) {
      return;
    }

    final target = waypoints[_targetWaypointIndex];
    final segmentLength = _segmentStart.getDistance(target.position).toDouble();
    final progress = _calculateSegmentProgress(
      _segmentStart,
      target.position,
      currentPose.translation,
    );
    final handoffThreshold = segmentLength >= 1e-6
        ? (1.0 - target.handoffDistance / segmentLength).clamp(0.0, 1.0)
        : 1.0;
    final closeEnough = target.position.getDistance(currentPose.translation) <=
        target.handoffDistance;

    if ((segmentLength >= 1e-6 && progress > handoffThreshold) || closeEnough) {
      _targetWaypointIndex++;
      _segmentStart = _segmentEnd;
      _segmentEnd = waypoints[_targetWaypointIndex].position;
      _updateHeldHeading(currentPose.rotation);
    }
  }

  Rotation2d _rotationTarget(Pose2d currentPose) {
    final pointTowardsZone = _activePointTowardsZone();
    if (pointTowardsZone != null) {
      return _pointTowardsHeading(
        pointTowardsZone,
        currentPose.translation,
        currentPose.rotation,
      );
    }

    int? nextPoseWaypointIndex;
    Rotation2d? nextPoseHeading;
    for (var i = _targetWaypointIndex; i < waypoints.length; i++) {
      final rotation = waypoints[i].rotation;
      if (rotation != null) {
        nextPoseWaypointIndex = i;
        nextPoseHeading = rotation;
        break;
      }
    }

    _ZoneRuntime<Path2SimulationPointTowardsZone>? nextPointZone;
    double? nextPointZonePosition;
    for (final zone in _pointTowardsZoneRuntimes) {
      if (zone.active || zone.start.fired) {
        continue;
      }
      final position = zone.definition.minWaypointRelativePosition;
      if (nextPointZonePosition == null || position < nextPointZonePosition) {
        nextPointZone = zone;
        nextPointZonePosition = position;
      }
    }

    if (nextPointZone != null &&
        (nextPoseWaypointIndex == null ||
            nextPointZonePosition! <= nextPoseWaypointIndex)) {
      final zone = nextPointZone.definition;
      final zoneStart = _sampleWaypointRelativePosition(
        waypoints,
        zone.minWaypointRelativePosition,
      );
      return _pointTowardsHeading(
        zone,
        zoneStart,
        currentPose.rotation,
      );
    }

    if (nextPoseHeading != null) {
      return nextPoseHeading;
    }
    return _heldHeading ??= currentPose.rotation;
  }

  static Rotation2d _pointTowardsHeading(
    Path2SimulationPointTowardsZone zone,
    Translation2d robotPosition,
    Rotation2d fallback,
  ) {
    final toTarget = zone.fieldPosition - robotPosition;
    if (toTarget.norm <= 1e-9) {
      return fallback;
    }
    return toTarget.angle + zone.rotationOffset;
  }

  void _updateHeldHeading(Rotation2d currentHeading) {
    final hasFuturePose = waypoints
        .skip(_targetWaypointIndex)
        .any((waypoint) => waypoint.rotation != null);
    _heldHeading = hasFuturePose ? null : currentHeading;
  }

  Path2SimulationConstraints _activeConstraints() {
    for (final zone in _constraintZoneRuntimes) {
      if (zone.active) {
        return zone.definition.constraints;
      }
    }
    return waypoints[_targetWaypointIndex].constraints;
  }

  Path2SimulationPointTowardsZone? _activePointTowardsZone() {
    for (final zone in _pointTowardsZoneRuntimes) {
      if (zone.active) {
        return zone.definition;
      }
    }
    return null;
  }

  static _TrapezoidConstraints _trapezoidConstraints(
    Path2SimulationConstraints constraints,
  ) {
    return _TrapezoidConstraints(
      constraints.maxAngularVelocityRadiansPerSecond,
      constraints.maxAngularAccelerationRadiansPerSecondSquared,
    );
  }

  _BoundaryTracker _createBoundaryTracker(
    double waypointRelativePosition,
    Translation2d initialPosition,
  ) {
    return _BoundaryTracker(
      fieldPosition: _sampleWaypointRelativePosition(
        waypoints,
        waypointRelativePosition,
      ),
      requiredTargetWaypointIndex: (waypointRelativePosition.floor() + 1)
          .clamp(0, waypoints.length - 1)
          .toInt(),
      initialPosition: initialPosition,
    );
  }

  void _updateBoundaryStates(Pose2d currentPose) {
    for (final marker in _markerRuntimes) {
      if (marker.start.update(
        currentPose.translation,
        _targetWaypointIndex,
        armed: !marker.started,
      )) {
        _startMarker(marker);
      }
      final end = marker.end;
      if (end != null &&
          end.update(
            currentPose.translation,
            _targetWaypointIndex,
            armed: marker.started && !marker.ended,
          )) {
        _endMarker(marker);
      }
    }

    for (final zone in _constraintZoneRuntimes) {
      if (zone.start.update(
        currentPose.translation,
        _targetWaypointIndex,
        armed: !zone.active,
      )) {
        zone.active = true;
      }
      if (zone.end.update(
        currentPose.translation,
        _targetWaypointIndex,
        armed: zone.active,
      )) {
        zone.active = false;
      }
    }

    final hadActivePointTowardsZone = _activePointTowardsZone() != null;
    for (final zone in _pointTowardsZoneRuntimes) {
      if (zone.start.update(
        currentPose.translation,
        _targetWaypointIndex,
        armed: !zone.active,
      )) {
        zone.active = true;
      }
      if (zone.end.update(
        currentPose.translation,
        _targetWaypointIndex,
        armed: zone.active,
      )) {
        zone.active = false;
      }
    }
    if (hadActivePointTowardsZone && _activePointTowardsZone() == null) {
      _updateHeldHeading(currentPose.rotation);
    }
  }

  void _startMarker(_MarkerRuntime marker) {
    if (marker.started) {
      return;
    }
    marker.started = true;
    _pendingMarkerTransitions.add(
      Path2SimulationMarkerTransition(
        markerIndex: marker.index,
        isZoned: marker.definition.isZoned,
        active: true,
      ),
    );
  }

  void _endMarker(_MarkerRuntime marker) {
    if (!marker.definition.isZoned || !marker.started || marker.ended) {
      return;
    }
    marker.ended = true;
    _pendingMarkerTransitions.add(
      Path2SimulationMarkerTransition(
        markerIndex: marker.index,
        isZoned: true,
        active: false,
      ),
    );
  }

  static Translation2d _sampleWaypointRelativePosition(
    List<Path2SimulationWaypoint> waypoints,
    double waypointRelativePosition,
  ) {
    if (waypoints.length == 1) {
      return waypoints.first.position;
    }
    final position =
        waypointRelativePosition.clamp(0.0, waypoints.length - 1.0).toDouble();
    var startIndex = position.floor();
    if (startIndex >= waypoints.length - 1) {
      startIndex = waypoints.length - 2;
    }
    return waypoints[startIndex].position.interpolate(
          waypoints[startIndex + 1].position,
          position - startIndex,
        );
  }

  double _calculateRemainingPathDistance(Pose2d currentPose) {
    var currentPosition = currentPose.translation;
    var remainingDistance = 0.0;
    for (var i = _targetWaypointIndex; i < waypoints.length; i++) {
      remainingDistance +=
          currentPosition.getDistance(waypoints[i].position).toDouble();
      currentPosition = waypoints[i].position;
    }
    return remainingDistance;
  }

  double _calculateCrossTrackError(Pose2d currentPose) {
    final progress = _calculateSegmentProgress(
      _segmentStart,
      _segmentEnd,
      currentPose.translation,
    );
    final closestPoint = _segmentStart.interpolate(_segmentEnd, progress);
    final pathVectorX = _segmentEnd.x - _segmentStart.x;
    final pathVectorY = _segmentEnd.y - _segmentStart.y;
    final robotVectorX = currentPose.x - _segmentStart.x;
    final robotVectorY = currentPose.y - _segmentStart.y;
    final crossProduct =
        pathVectorX * robotVectorY - pathVectorY * robotVectorX;

    var signedError =
        currentPose.translation.getDistance(closestPoint).toDouble();
    if (crossProduct < 0) {
      signedError = -signedError;
    }
    return signedError;
  }

  static double _calculateSegmentProgress(
    Translation2d segmentStart,
    Translation2d segmentEnd,
    Translation2d point,
  ) {
    final dx = segmentEnd.x - segmentStart.x;
    final dy = segmentEnd.y - segmentStart.y;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared < 1e-6) {
      return 0.0;
    }
    final pointDx = point.x - segmentStart.x;
    final pointDy = point.y - segmentStart.y;
    return ((pointDx * dx + pointDy * dy) / lengthSquared)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

class _BoundaryTracker {
  static const double _distanceEpsilonMeters = 1e-9;
  static const double _boundaryToleranceMeters = 1e-6;

  final Translation2d fieldPosition;
  final int requiredTargetWaypointIndex;
  late double _previousDistance;
  late final bool _startedAtBoundary;
  bool _hasDecreased = false;
  bool _hasIncreasedFromBoundary = false;
  bool _fired = false;

  bool get fired => _fired;

  _BoundaryTracker({
    required this.fieldPosition,
    required this.requiredTargetWaypointIndex,
    required Translation2d initialPosition,
  }) {
    _previousDistance = fieldPosition.getDistance(initialPosition).toDouble();
    _startedAtBoundary = _previousDistance <= _boundaryToleranceMeters;
  }

  bool update(
    Translation2d currentPosition,
    int targetWaypointIndex, {
    required bool armed,
  }) {
    final distance = fieldPosition.getDistance(currentPosition).toDouble();
    final decreased = distance < _previousDistance - _distanceEpsilonMeters;
    final increased = distance > _previousDistance + _distanceEpsilonMeters;
    if (decreased) {
      _hasDecreased = true;
    }
    if (_startedAtBoundary && increased) {
      _hasIncreasedFromBoundary = true;
    }

    final shouldFire = !_fired &&
        armed &&
        targetWaypointIndex >= requiredTargetWaypointIndex &&
        (targetWaypointIndex > requiredTargetWaypointIndex ||
            _hasIncreasedFromBoundary ||
            (_hasDecreased && increased));
    _previousDistance = distance;
    if (shouldFire) {
      _fired = true;
    }
    return shouldFire;
  }

  bool forceIfApproached(int targetWaypointIndex) {
    if (_fired ||
        targetWaypointIndex < requiredTargetWaypointIndex ||
        (!_startedAtBoundary && !_hasDecreased)) {
      return false;
    }
    _fired = true;
    return true;
  }

  bool force() {
    if (_fired) {
      return false;
    }
    _fired = true;
    return true;
  }
}

class _MarkerRuntime {
  final int index;
  final Path2SimulationEventMarker definition;
  final _BoundaryTracker start;
  final _BoundaryTracker? end;
  bool started = false;
  bool ended = false;

  _MarkerRuntime(
    this.index,
    this.definition,
    this.start, {
    this.end,
  });
}

class _ZoneRuntime<T> {
  final T definition;
  final _BoundaryTracker start;
  final _BoundaryTracker end;
  bool active = false;

  _ZoneRuntime(this.definition, this.start, this.end);
}

class _PidController {
  final double proportionalGain;
  final double period;

  double _positionTolerance = 0.05;
  double _velocityTolerance = double.infinity;
  double _positionError = 0.0;
  double _velocityError = 0.0;
  double _previousError = 0.0;
  bool _hasMeasurement = false;
  bool _continuous = false;
  double _minimumInput = 0.0;
  double _maximumInput = 0.0;

  _PidController(this.proportionalGain, this.period);

  void setTolerance(double positionTolerance,
      [double velocityTolerance = double.infinity]) {
    _positionTolerance = positionTolerance;
    _velocityTolerance = velocityTolerance;
  }

  void enableContinuousInput(double minimumInput, double maximumInput) {
    _continuous = true;
    _minimumInput = minimumInput;
    _maximumInput = maximumInput;
  }

  void reset() {
    _positionError = 0.0;
    _velocityError = 0.0;
    _previousError = 0.0;
    _hasMeasurement = false;
  }

  double calculate(double measurement, double setpoint) {
    _positionError = setpoint - measurement;
    if (_continuous) {
      final errorBound = (_maximumInput - _minimumInput) / 2.0;
      _positionError = _inputModulus(
        _positionError,
        -errorBound,
        errorBound,
      );
    }
    _velocityError =
        _hasMeasurement ? (_positionError - _previousError) / period : 0.0;
    _previousError = _positionError;
    _hasMeasurement = true;
    return proportionalGain * _positionError;
  }

  bool get atSetpoint =>
      _hasMeasurement &&
      _positionError.abs() < _positionTolerance &&
      _velocityError.abs() < _velocityTolerance;
}

class _ProfiledPidController {
  final _PidController _controller;
  final double period;
  _TrapezoidConstraints _constraints;
  _TrapezoidState _setpoint = const _TrapezoidState(0.0, 0.0);
  bool _continuous = false;
  double _minimumInput = 0.0;
  double _maximumInput = 0.0;

  _ProfiledPidController(
    double proportionalGain,
    this.period,
    this._constraints,
  ) : _controller = _PidController(proportionalGain, period);

  void enableContinuousInput(double minimumInput, double maximumInput) {
    _continuous = true;
    _minimumInput = minimumInput;
    _maximumInput = maximumInput;
  }

  void setConstraints(_TrapezoidConstraints constraints) {
    _constraints = constraints;
  }

  void setTolerance(double positionTolerance,
      [double velocityTolerance = double.infinity]) {
    _controller.setTolerance(positionTolerance, velocityTolerance);
  }

  void reset(double measurement, double velocity) {
    _setpoint = _TrapezoidState(measurement, velocity);
    _controller.reset();
  }

  double calculate(double measurement, double goalPosition) {
    var goal = _TrapezoidState(goalPosition, 0.0);
    if (_continuous) {
      final errorBound = (_maximumInput - _minimumInput) / 2.0;
      goal = _TrapezoidState(
        _inputModulus(goal.position - measurement, -errorBound, errorBound) +
            measurement,
        goal.velocity,
      );
      _setpoint = _TrapezoidState(
        _inputModulus(
                _setpoint.position - measurement, -errorBound, errorBound) +
            measurement,
        _setpoint.velocity,
      );
    }

    _setpoint =
        _TrapezoidProfile(_constraints).calculate(period, _setpoint, goal);
    return _controller.calculate(measurement, _setpoint.position);
  }

  bool get atSetpoint => _controller.atSetpoint;
}

class _TrapezoidConstraints {
  final double maxVelocity;
  final double maxAcceleration;

  const _TrapezoidConstraints(this.maxVelocity, this.maxAcceleration);
}

class _TrapezoidState {
  final double position;
  final double velocity;

  const _TrapezoidState(this.position, this.velocity);
}

/// The same analytic trapezoid step used by WPILib's `TrapezoidProfile`.
class _TrapezoidProfile {
  final _TrapezoidConstraints constraints;

  const _TrapezoidProfile(this.constraints);

  _TrapezoidState calculate(
    double time,
    _TrapezoidState current,
    _TrapezoidState goal,
  ) {
    final direction = current.position > goal.position ? -1.0 : 1.0;
    current = _direct(current, direction);
    goal = _direct(goal, direction);

    final currentVelocity = current.velocity
        .clamp(-constraints.maxVelocity, constraints.maxVelocity);
    current = _TrapezoidState(current.position, currentVelocity.toDouble());

    final cutoffBegin = current.velocity / constraints.maxAcceleration;
    final cutoffDistanceBegin =
        cutoffBegin * cutoffBegin * constraints.maxAcceleration / 2.0;
    final cutoffEnd = goal.velocity / constraints.maxAcceleration;
    final cutoffDistanceEnd =
        cutoffEnd * cutoffEnd * constraints.maxAcceleration / 2.0;

    final fullTrapezoidDistance = cutoffDistanceBegin +
        (goal.position - current.position) +
        cutoffDistanceEnd;
    var accelerationTime =
        constraints.maxVelocity / constraints.maxAcceleration;
    var fullSpeedDistance = fullTrapezoidDistance -
        accelerationTime * accelerationTime * constraints.maxAcceleration;
    if (fullSpeedDistance < 0.0) {
      accelerationTime = math.sqrt(
          math.max(0.0, fullTrapezoidDistance) / constraints.maxAcceleration);
      fullSpeedDistance = 0.0;
    }

    final endAcceleration = accelerationTime - cutoffBegin;
    final endFullSpeed =
        endAcceleration + fullSpeedDistance / constraints.maxVelocity;
    final endDeceleration = endFullSpeed + accelerationTime - cutoffEnd;

    late _TrapezoidState result;
    if (time < endAcceleration) {
      final velocity = current.velocity + time * constraints.maxAcceleration;
      result = _TrapezoidState(
        current.position +
            (current.velocity + time * constraints.maxAcceleration / 2.0) *
                time,
        velocity,
      );
    } else if (time < endFullSpeed) {
      result = _TrapezoidState(
        current.position +
            (current.velocity + constraints.maxVelocity) /
                2.0 *
                endAcceleration +
            constraints.maxVelocity * (time - endAcceleration),
        constraints.maxVelocity,
      );
    } else if (time <= endDeceleration) {
      final timeLeft = endDeceleration - time;
      final velocity = goal.velocity + timeLeft * constraints.maxAcceleration;
      result = _TrapezoidState(
        goal.position - (goal.velocity + velocity) / 2.0 * timeLeft,
        velocity,
      );
    } else {
      result = goal;
    }

    return _direct(result, direction);
  }

  static _TrapezoidState _direct(_TrapezoidState state, double direction) =>
      _TrapezoidState(
        state.position * direction,
        state.velocity * direction,
      );
}

double _inputModulus(double input, double minimumInput, double maximumInput) {
  final modulus = maximumInput - minimumInput;
  final numMax = ((input - minimumInput) / modulus).truncate();
  input -= numMax * modulus;
  final numMin = ((input - maximumInput) / modulus).truncate();
  input -= numMin * modulus;
  return input;
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180.0;
