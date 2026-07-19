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
  final double endToleranceMeters;
  final double endAngleToleranceRadians;

  Path2SimulationPathSnapshot({
    required this.name,
    required List<Path2SimulationWaypoint> waypoints,
    required this.endToleranceMeters,
    required this.endAngleToleranceRadians,
  }) : waypoints = List.unmodifiable(waypoints);

  factory Path2SimulationPathSnapshot.fromPath(path2.Path path) {
    return Path2SimulationPathSnapshot(
      name: path.name,
      waypoints: path.waypoints
          .map(Path2SimulationWaypoint.fromWaypoint)
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
        Path2SimulationResult(combinedSamples),
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

    for (var step = 1; step <= maximumStepsPerPath; step++) {
      final desiredSpeeds = follower.calculate(currentState.pose);
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
        return Path2SimulationResult(samples);
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
