import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/path2/simulation/path2_path_follower.dart';
import 'package:pathplanner/path2/simulation/simulation_state.dart';
import 'package:pathplanner/path2/simulation/swerve_math.dart';
import 'package:pathplanner/path2/simulation/swerve_setpoint_generator.dart';
import 'package:pathplanner/trajectory/config.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';

/// Immutable path data sent to the simulation isolate.
class Path2SimulationPathSnapshot {
  final String name;
  final List<Path2SimulationWaypoint> waypoints;
  final List<Path2SimulationEventMarker> eventMarkers;
  final List<Path2SimulationConstraintsZone> constraintZones;
  final List<Path2SimulationPointTowardsZone> pointTowardsZones;
  final double endToleranceMeters;
  final double endAngleToleranceRadians;

  Path2SimulationPathSnapshot({
    required this.name,
    required List<Path2SimulationWaypoint> waypoints,
    List<Path2SimulationEventMarker> eventMarkers = const [],
    List<Path2SimulationConstraintsZone> constraintZones = const [],
    List<Path2SimulationPointTowardsZone> pointTowardsZones = const [],
    required this.endToleranceMeters,
    required this.endAngleToleranceRadians,
  })  : waypoints = List.unmodifiable(waypoints),
        eventMarkers = List.unmodifiable(eventMarkers),
        constraintZones = List.unmodifiable(constraintZones),
        pointTowardsZones = List.unmodifiable(pointTowardsZones);

  factory Path2SimulationPathSnapshot.fromPath(path2.Path path) {
    return Path2SimulationPathSnapshot(
      name: path.name,
      waypoints: path.waypoints
          .map(Path2SimulationWaypoint.fromWaypoint)
          .toList(growable: false),
      eventMarkers: path.eventMarkers
          .map(Path2SimulationEventMarker.fromMarker)
          .toList(growable: false),
      constraintZones: path.constraintZones
          .map(Path2SimulationConstraintsZone.fromZone)
          .toList(growable: false),
      pointTowardsZones: path.pointTowardsZones
          .map(Path2SimulationPointTowardsZone.fromZone)
          .toList(growable: false),
      endToleranceMeters: path.endToleranceMeters.toDouble(),
      endAngleToleranceRadians:
          path.endAngleToleranceDegrees.toDouble() * math.pi / 180.0,
    );
  }

  factory Path2SimulationPathSnapshot.fromMap(Map<String, dynamic> map) {
    return Path2SimulationPathSnapshot(
      name: map['name'] as String,
      waypoints: (map['waypoints'] as List<dynamic>)
          .map((waypoint) => Path2SimulationWaypoint.fromMap(
                Map<String, dynamic>.from(waypoint as Map),
              ))
          .toList(growable: false),
      eventMarkers: (map['eventMarkers'] as List<dynamic>? ?? const [])
          .map((marker) => Path2SimulationEventMarker.fromMap(
                Map<String, dynamic>.from(marker as Map),
              ))
          .toList(growable: false),
      constraintZones: (map['constraintZones'] as List<dynamic>? ?? const [])
          .map((zone) => Path2SimulationConstraintsZone.fromMap(
                Map<String, dynamic>.from(zone as Map),
              ))
          .toList(growable: false),
      pointTowardsZones:
          (map['pointTowardsZones'] as List<dynamic>? ?? const [])
              .map((zone) => Path2SimulationPointTowardsZone.fromMap(
                    Map<String, dynamic>.from(zone as Map),
                  ))
              .toList(growable: false),
      endToleranceMeters: (map['endToleranceMeters'] as num).toDouble(),
      endAngleToleranceRadians:
          (map['endAngleToleranceRadians'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'waypoints': waypoints
            .map((waypoint) => waypoint.toMap())
            .toList(growable: false),
        'eventMarkers': eventMarkers
            .map((marker) => marker.toMap())
            .toList(growable: false),
        'constraintZones':
            constraintZones.map((zone) => zone.toMap()).toList(growable: false),
        'pointTowardsZones': pointTowardsZones
            .map((zone) => zone.toMap())
            .toList(growable: false),
        'endToleranceMeters': endToleranceMeters,
        'endAngleToleranceRadians': endAngleToleranceRadians,
      };
}

/// A non-throwing result envelope suitable for a Flutter isolate boundary.
class Path2SimulationOutcome {
  final Path2SimulationResult? result;
  final Path2SimulationFailure? failure;

  const Path2SimulationOutcome._({this.result, this.failure});

  const Path2SimulationOutcome.success(Path2SimulationResult result)
      : this._(result: result);

  const Path2SimulationOutcome.failed(Path2SimulationFailure failure)
      : this._(failure: failure);

  factory Path2SimulationOutcome.fromMap(Map<String, dynamic> map) {
    final resultMap = map['result'];
    if (resultMap is Map) {
      return Path2SimulationOutcome.success(
        Path2SimulationResult.fromMap(
          Map<String, dynamic>.from(resultMap),
        ),
      );
    }
    final failureMap = Map<String, dynamic>.from(map['failure'] as Map);
    return Path2SimulationOutcome.failed(
      Path2SimulationFailure(
        Path2SimulationFailureKind.values.byName(
          failureMap['kind'] as String,
        ),
        failureMap['message'] as String,
      ),
    );
  }

  bool get isSuccess => result != null;

  Map<String, dynamic> toMap() {
    final successfulResult = result;
    if (successfulResult != null) {
      return {'result': successfulResult.toMap()};
    }
    return {
      'failure': {
        'kind': failure!.kind.name,
        'message': failure!.message,
      },
    };
  }
}

/// Deterministic, Path2-native path and auto simulation.
abstract final class Path2Simulator {
  static const double periodSeconds = 0.02;
  static const int maximumStepsPerPath = 6000;
  static const int stalledStepLimit = 250;

  static Future<Path2SimulationOutcome> simulatePathInBackground(
    path2.Path path,
    RobotConfig robotConfig,
  ) async {
    try {
      final pathSnapshot = Path2SimulationPathSnapshot.fromPath(path);
      final configSnapshot =
          Path2RobotConfigSnapshot.fromRobotConfig(robotConfig);
      final request = <String, dynamic>{
        'paths': [pathSnapshot.toMap()],
        'config': configSnapshot.toMap(),
        'initialState': _standaloneInitialState(pathSnapshot).toMap(),
        'standalone': true,
      };
      return Path2SimulationOutcome.fromMap(
        await compute(_runPath2SimulationRequest, request),
      );
    } on Path2SimulationFailure catch (failure) {
      return Path2SimulationOutcome.failed(failure);
    } catch (error) {
      return Path2SimulationOutcome.failed(
        Path2SimulationFailure(
          Path2SimulationFailureKind.invalidConfiguration,
          error.toString(),
        ),
      );
    }
  }

  static Future<Path2SimulationOutcome> simulateAutoInBackground(
    List<path2.Path> paths,
    Pose2d startingPose,
    RobotConfig robotConfig,
  ) async {
    if (paths.isEmpty) {
      return const Path2SimulationOutcome.failed(
        Path2SimulationFailure(
          Path2SimulationFailureKind.invalidPath,
          'The auto does not contain any paths.',
        ),
      );
    }
    try {
      final snapshots = paths
          .map(Path2SimulationPathSnapshot.fromPath)
          .toList(growable: false);
      final configSnapshot =
          Path2RobotConfigSnapshot.fromRobotConfig(robotConfig);
      final request = <String, dynamic>{
        'paths': snapshots.map((path) => path.toMap()).toList(growable: false),
        'config': configSnapshot.toMap(),
        'initialState': Path2SimulationState.atRest(startingPose).toMap(),
        'standalone': false,
      };
      return Path2SimulationOutcome.fromMap(
        await compute(_runPath2SimulationRequest, request),
      );
    } on Path2SimulationFailure catch (failure) {
      return Path2SimulationOutcome.failed(failure);
    } catch (error) {
      return Path2SimulationOutcome.failed(
        Path2SimulationFailure(
          Path2SimulationFailureKind.invalidConfiguration,
          error.toString(),
        ),
      );
    }
  }

  static Path2SimulationOutcome simulatePath(
    Path2SimulationPathSnapshot path,
    Path2RobotConfigSnapshot robotConfig,
  ) {
    return _simulate(
      [path],
      robotConfig,
      _standaloneInitialState(path),
      standalone: true,
    );
  }

  static Path2SimulationOutcome simulateAuto(
    List<Path2SimulationPathSnapshot> paths,
    Path2RobotConfigSnapshot robotConfig,
    Pose2d startingPose,
  ) {
    return _simulate(
      paths,
      robotConfig,
      Path2SimulationState.atRest(startingPose),
      standalone: false,
    );
  }

  static Path2SimulationOutcome _simulate(
    List<Path2SimulationPathSnapshot> paths,
    Path2RobotConfigSnapshot robotConfig,
    Path2SimulationState initialState, {
    required bool standalone,
  }) {
    if (paths.isEmpty) {
      return const Path2SimulationOutcome.failed(
        Path2SimulationFailure(
          Path2SimulationFailureKind.invalidPath,
          'At least one path is required for simulation.',
        ),
      );
    }

    try {
      _validateState(initialState);
      var currentState = initialState;
      final combinedSamples = <Path2SimulationSample>[];
      final combinedMarkerActivations = <Path2SimulationMarkerActivation>[];
      var timeOffset = 0.0;

      for (var pathIndex = 0; pathIndex < paths.length; pathIndex++) {
        final path = paths[pathIndex];
        _validatePath(path);
        final pathResult = _simulateSinglePath(
          path,
          robotConfig,
          currentState,
          targetFirstWaypoint: !standalone || pathIndex > 0,
        );
        combinedMarkerActivations.addAll(
          pathResult.markerActivations.map(
            (activation) => activation.shifted(
              pathIndex: pathIndex,
              timeOffsetSeconds: timeOffset,
            ),
          ),
        );

        if (combinedSamples.isEmpty) {
          combinedSamples.addAll(pathResult.samples);
        } else {
          for (final sample in pathResult.samples.skip(1)) {
            combinedSamples.add(
              Path2SimulationSample(
                timeSeconds: timeOffset + sample.timeSeconds,
                state: sample.state,
              ),
            );
          }
        }
        timeOffset = combinedSamples.last.timeSeconds;
        currentState = pathResult.terminalState;
      }

      return Path2SimulationOutcome.success(
        Path2SimulationResult(
          combinedSamples,
          markerActivations: combinedMarkerActivations,
        ),
      );
    } on Path2SimulationFailure catch (failure) {
      return Path2SimulationOutcome.failed(failure);
    } catch (error) {
      return Path2SimulationOutcome.failed(
        Path2SimulationFailure(
          Path2SimulationFailureKind.invalidConfiguration,
          error.toString(),
        ),
      );
    }
  }

  static Path2SimulationResult _simulateSinglePath(
    Path2SimulationPathSnapshot path,
    Path2RobotConfigSnapshot robotConfig,
    Path2SimulationState initialState, {
    required bool targetFirstWaypoint,
  }) {
    final follower = Path2PathFollower(
      waypoints: path.waypoints,
      eventMarkers: path.eventMarkers,
      constraintZones: path.constraintZones,
      pointTowardsZones: path.pointTowardsZones,
      endToleranceMeters: path.endToleranceMeters,
      endAngleToleranceRadians: path.endAngleToleranceRadians,
      initialPose: initialState.pose,
      initialRobotRelativeSpeeds: initialState.robotRelativeSpeeds,
      targetFirstWaypoint: targetFirstWaypoint,
    );
    final generator = SwerveSetpointGenerator(robotConfig);
    var setpoint = Path2SwerveSetpoint.fromSimulationState(initialState);
    var currentState = initialState;
    var lastProgressState = initialState;
    var stalledSteps = 0;
    final samples = <Path2SimulationSample>[
      Path2SimulationSample(timeSeconds: 0.0, state: initialState),
    ];
    final markerActivations = <Path2SimulationMarkerActivation>[];
    final activeMarkerStarts = <int, double>{};

    void recordMarkerTransitions(double timeSeconds) {
      for (final transition in follower.takeMarkerTransitions()) {
        if (!transition.isZoned) {
          if (transition.active) {
            markerActivations.add(
              Path2SimulationMarkerActivation(
                pathIndex: 0,
                markerIndex: transition.markerIndex,
                startTimeSeconds: timeSeconds,
              ),
            );
          }
          continue;
        }

        if (transition.active) {
          activeMarkerStarts.putIfAbsent(
            transition.markerIndex,
            () => timeSeconds,
          );
        } else {
          final startTime = activeMarkerStarts.remove(transition.markerIndex);
          if (startTime != null) {
            markerActivations.add(
              Path2SimulationMarkerActivation(
                pathIndex: 0,
                markerIndex: transition.markerIndex,
                startTimeSeconds: startTime,
                endTimeSeconds: timeSeconds,
              ),
            );
          }
        }
      }
    }

    Path2SimulationResult completedResult() {
      markerActivations.sort((a, b) {
        final timeOrder = a.startTimeSeconds.compareTo(b.startTimeSeconds);
        return timeOrder != 0
            ? timeOrder
            : a.markerIndex.compareTo(b.markerIndex);
      });
      return Path2SimulationResult(
        samples,
        markerActivations: markerActivations,
      );
    }

    recordMarkerTransitions(0.0);

    for (var step = 1; step <= maximumStepsPerPath; step++) {
      final desiredSpeeds = follower.calculate(
        currentState.pose,
        currentState.robotRelativeSpeeds,
      );
      recordMarkerTransitions(samples.last.timeSeconds);
      setpoint = generator.generateSetpoint(setpoint, desiredSpeeds);
      final nextPose = Path2SimulationMath.integratePose(
        currentState.pose,
        setpoint.robotRelativeSpeeds,
        periodSeconds,
      );
      currentState = Path2SimulationState(
        pose: nextPose,
        robotRelativeSpeeds: setpoint.robotRelativeSpeeds,
        moduleStates: setpoint.moduleStates,
      );
      _validateState(currentState);
      samples.add(
        Path2SimulationSample(
          timeSeconds: step * periodSeconds,
          state: currentState,
        ),
      );

      if (_madePhysicalProgress(lastProgressState, currentState)) {
        lastProgressState = currentState;
        stalledSteps = 0;
      } else {
        stalledSteps++;
      }

      if (follower.isFinished) {
        follower.finalize(currentState.pose);
        recordMarkerTransitions(samples.last.timeSeconds);
        return completedResult();
      }
      if (stalledSteps >= stalledStepLimit) {
        throw Path2SimulationFailure(
          Path2SimulationFailureKind.stalled,
          'Simulation of "${path.name}" stopped making progress.',
        );
      }
    }

    throw Path2SimulationFailure(
      Path2SimulationFailureKind.timedOut,
      'Simulation of "${path.name}" exceeded 120 seconds.',
    );
  }

  static Path2SimulationState _standaloneInitialState(
    Path2SimulationPathSnapshot path,
  ) {
    if (path.waypoints.isEmpty) {
      throw const Path2SimulationFailure(
        Path2SimulationFailureKind.invalidPath,
        'A path must contain at least one waypoint.',
      );
    }
    final first = path.waypoints.first;
    return Path2SimulationState.atRest(
      Pose2d(first.position, first.rotation ?? const Rotation2d()),
    );
  }

  static bool _madePhysicalProgress(
    Path2SimulationState previous,
    Path2SimulationState current,
  ) {
    if (previous.pose.translation.getDistance(current.pose.translation) >
            1e-5 ||
        (current.pose.rotation - previous.pose.rotation).radians.abs() > 1e-5 ||
        (current.robotRelativeSpeeds.vx - previous.robotRelativeSpeeds.vx)
                .abs() >
            1e-5 ||
        (current.robotRelativeSpeeds.vy - previous.robotRelativeSpeeds.vy)
                .abs() >
            1e-5 ||
        (current.robotRelativeSpeeds.omega - previous.robotRelativeSpeeds.omega)
                .abs() >
            1e-5) {
      return true;
    }
    for (var index = 0; index < current.moduleStates.length; index++) {
      final before = previous.moduleStates[index];
      final after = current.moduleStates[index];
      if ((after.speedMetersPerSecond - before.speedMetersPerSecond).abs() >
              1e-5 ||
          (after.angle - before.angle).radians.abs() > 1e-5) {
        return true;
      }
    }
    return false;
  }

  static void _validatePath(Path2SimulationPathSnapshot path) {
    if (path.waypoints.isEmpty) {
      throw Path2SimulationFailure(
        Path2SimulationFailureKind.invalidPath,
        'Path "${path.name}" does not contain any waypoints.',
      );
    }
    if (!path.endToleranceMeters.isFinite ||
        path.endToleranceMeters < 0.0 ||
        !path.endAngleToleranceRadians.isFinite ||
        path.endAngleToleranceRadians < 0.0) {
      throw Path2SimulationFailure(
        Path2SimulationFailureKind.invalidPath,
        'Path "${path.name}" has invalid end tolerances.',
      );
    }
    for (final waypoint in path.waypoints) {
      if (!waypoint.position.x.toDouble().isFinite ||
          !waypoint.position.y.toDouble().isFinite ||
          !(waypoint.rotation?.radians.toDouble().isFinite ?? true) ||
          !waypoint.maxVelocity.isFinite ||
          waypoint.maxVelocity < 0.0 ||
          !waypoint.handoffDistance.isFinite ||
          waypoint.handoffDistance < 0.0 ||
          !waypoint.maxAngularVelocityRadiansPerSecond.isFinite ||
          waypoint.maxAngularVelocityRadiansPerSecond <= 0.0 ||
          !waypoint.maxAngularAccelerationRadiansPerSecondSquared.isFinite ||
          waypoint.maxAngularAccelerationRadiansPerSecondSquared <= 0.0) {
        throw Path2SimulationFailure(
          Path2SimulationFailureKind.invalidPath,
          'Path "${path.name}" contains invalid waypoint values.',
        );
      }
    }

    final lastWaypointRelativePosition = path.waypoints.length - 1.0;
    for (final marker in path.eventMarkers) {
      final endPosition = marker.endWaypointRelativePosition;
      if (!marker.waypointRelativePosition.isFinite ||
          marker.waypointRelativePosition < 0.0 ||
          marker.waypointRelativePosition > lastWaypointRelativePosition ||
          (endPosition != null &&
              (!endPosition.isFinite ||
                  endPosition < marker.waypointRelativePosition ||
                  endPosition > lastWaypointRelativePosition))) {
        throw Path2SimulationFailure(
          Path2SimulationFailureKind.invalidPath,
          'Path "${path.name}" contains an invalid event marker.',
        );
      }
    }
    for (final zone in path.constraintZones) {
      final constraints = zone.constraints;
      if (!zone.minWaypointRelativePosition.isFinite ||
          !zone.maxWaypointRelativePosition.isFinite ||
          zone.minWaypointRelativePosition < 0.0 ||
          zone.maxWaypointRelativePosition < zone.minWaypointRelativePosition ||
          zone.maxWaypointRelativePosition > lastWaypointRelativePosition ||
          !constraints.maxVelocity.isFinite ||
          constraints.maxVelocity < 0.0 ||
          !constraints.maxAngularVelocityRadiansPerSecond.isFinite ||
          constraints.maxAngularVelocityRadiansPerSecond <= 0.0 ||
          !constraints.maxAngularAccelerationRadiansPerSecondSquared.isFinite ||
          constraints.maxAngularAccelerationRadiansPerSecondSquared <= 0.0) {
        throw Path2SimulationFailure(
          Path2SimulationFailureKind.invalidPath,
          'Path "${path.name}" contains an invalid constraints zone.',
        );
      }
    }
    for (final zone in path.pointTowardsZones) {
      if (!zone.minWaypointRelativePosition.isFinite ||
          !zone.maxWaypointRelativePosition.isFinite ||
          zone.minWaypointRelativePosition < 0.0 ||
          zone.maxWaypointRelativePosition < zone.minWaypointRelativePosition ||
          zone.maxWaypointRelativePosition > lastWaypointRelativePosition ||
          !zone.fieldPosition.x.toDouble().isFinite ||
          !zone.fieldPosition.y.toDouble().isFinite ||
          !zone.rotationOffset.radians.toDouble().isFinite) {
        throw Path2SimulationFailure(
          Path2SimulationFailureKind.invalidPath,
          'Path "${path.name}" contains an invalid point-towards zone.',
        );
      }
    }
  }

  static void _validateState(Path2SimulationState state) {
    if (!Path2SimulationMath.isFinitePose(state.pose) ||
        !Path2SimulationMath.isFiniteChassisSpeeds(
          state.robotRelativeSpeeds,
        ) ||
        state.moduleStates.any(
          (module) =>
              !module.speedMetersPerSecond.isFinite ||
              !module.angle.radians.toDouble().isFinite,
        )) {
      throw const Path2SimulationFailure(
        Path2SimulationFailureKind.nonFiniteState,
        'The simulated robot state became non-finite.',
      );
    }
  }
}

Map<String, dynamic> _runPath2SimulationRequest(
  Map<String, dynamic> request,
) {
  try {
    final paths = (request['paths'] as List<dynamic>)
        .map((path) => Path2SimulationPathSnapshot.fromMap(
              Map<String, dynamic>.from(path as Map),
            ))
        .toList(growable: false);
    final config = Path2RobotConfigSnapshot.fromMap(
      Map<String, dynamic>.from(request['config'] as Map),
    );
    final initialState = Path2SimulationState.fromMap(
      Map<String, dynamic>.from(request['initialState'] as Map),
    );
    final outcome = Path2Simulator._simulate(
      paths,
      config,
      initialState,
      standalone: request['standalone'] == true,
    );
    return outcome.toMap();
  } on Path2SimulationFailure catch (failure) {
    return Path2SimulationOutcome.failed(failure).toMap();
  } catch (error) {
    return Path2SimulationOutcome.failed(
      Path2SimulationFailure(
        Path2SimulationFailureKind.invalidConfiguration,
        error.toString(),
      ),
    ).toMap();
  }
}
