import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/path2/simulation/path2_path_follower.dart';
import 'package:pathplanner/path2/simulation/path2_simulator.dart';
import 'package:pathplanner/path2/simulation/simulation_state.dart';
import 'package:pathplanner/trajectory/config.dart';
import 'package:pathplanner/trajectory/dc_motor.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/util/wpimath/kinematics.dart';

void main() {
  late Path2RobotConfigSnapshot config;

  setUp(() {
    config = Path2RobotConfigSnapshot.fromRobotConfig(
      RobotConfig(
        massKG: 74.0,
        moi: 6.8,
        bumperSize: const Size(0.9, 0.9),
        bumperOffset: const Translation2d(),
        moduleConfig: ModuleConfig(
          wheelRadiusMeters: 0.048,
          maxDriveVelocityMPS: 5.0,
          driveMotor: DCMotor.getKrakenX60(1).withReduction(5.14),
          driveCurrentLimit: 60.0,
          wheelCOF: 1.2,
        ),
        moduleLocations: const [
          Translation2d(0.273, 0.273),
          Translation2d(0.273, -0.273),
          Translation2d(-0.273, 0.273),
          Translation2d(-0.273, -0.273),
        ],
        holonomic: true,
      ),
    );
  });

  Path2SimulationWaypoint waypoint(
    double x,
    double y, {
    double? heading,
    double maxVelocity = 3.0,
    double handoffDistance = 0.25,
    double maxAngularVelocity = 2 * math.pi,
    double maxAngularAcceleration = 4 * math.pi,
  }) {
    return Path2SimulationWaypoint(
      position: Translation2d(x, y),
      rotation: heading == null ? null : Rotation2d.fromRadians(heading),
      maxVelocity: maxVelocity,
      handoffDistance: handoffDistance,
      maxAngularVelocityRadiansPerSecond: maxAngularVelocity,
      maxAngularAccelerationRadiansPerSecondSquared: maxAngularAcceleration,
    );
  }

  Path2SimulationPathSnapshot path(
    String name,
    List<Path2SimulationWaypoint> waypoints,
  ) {
    return Path2SimulationPathSnapshot(
      name: name,
      waypoints: waypoints,
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 2 * math.pi / 180.0,
    );
  }

  test('simulates a straight path at exact 20 ms timestamps', () {
    final outcome = Path2Simulator.simulatePath(
      path('straight', [
        waypoint(0, 0, heading: 0),
        waypoint(2, 0, heading: 0),
      ]),
      config,
    );

    expect(outcome.failure, isNull);
    final result = outcome.result!;
    expect(result.samples.length, greaterThan(2));
    expect(result.totalTimeSeconds,
        closeTo((result.samples.length - 1) * 0.02, 1e-12));
    for (var i = 1; i < result.samples.length; i++) {
      expect(
        result.samples[i].timeSeconds - result.samples[i - 1].timeSeconds,
        closeTo(0.02, 1e-12),
      );
    }
    expect(result.terminalState.pose.x, closeTo(2.0, 0.12));
    expect(result.terminalState.pose.y, closeTo(0.0, 0.02));
  });

  test('standalone translation start uses zero heading', () {
    final outcome = Path2Simulator.simulatePath(
      path('translation start', [
        waypoint(1, 2),
        waypoint(2, 2),
      ]),
      config,
    );

    expect(outcome.failure, isNull);
    expect(outcome.result!.samples.first.pose.translation,
        const Translation2d(1, 2));
    expect(outcome.result!.samples.first.pose.rotation.radians, 0);
  });

  test('translation targets anticipate the next pose heading', () {
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0),
        waypoint(2, 0, heading: math.pi / 2),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    final desired = follower.calculate(
      const Pose2d(Translation2d(), Rotation2d()),
    );
    expect(desired.omega, greaterThan(0));
  });

  test('translation-only suffix captures and holds its entry heading', () {
    const heading = 0.7;
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: heading),
        waypoint(1, 0),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d(heading)),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    final desired = follower.calculate(
      const Pose2d(Translation2d(), Rotation2d(heading)),
    );
    expect(desired.omega, closeTo(0, 1e-9));
  });

  test('projected progress hands off before reaching the waypoint center', () {
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: 0, handoffDistance: 0.2),
        waypoint(2, 0, heading: 0),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    follower.calculate(
      const Pose2d(Translation2d(0.9, 0), Rotation2d()),
    );
    expect(follower.targetWaypointIndex, 2);
  });

  test('target angular constraints limit the profiled rotation request', () {
    Path2PathFollower followerWithAcceleration(double acceleration) {
      return Path2PathFollower(
        waypoints: [
          waypoint(0, 0, heading: 0),
          waypoint(
            1,
            0,
            heading: math.pi / 2,
            maxAngularVelocity: 10,
            maxAngularAcceleration: acceleration,
          ),
        ],
        endToleranceMeters: 0.1,
        endAngleToleranceRadians: 0.05,
        initialPose: const Pose2d(Translation2d(), Rotation2d()),
        initialRobotRelativeSpeeds: const ChassisSpeeds(),
        targetFirstWaypoint: false,
      );
    }

    final slow = followerWithAcceleration(1).calculate(
      const Pose2d(Translation2d(), Rotation2d()),
    );
    final fast = followerWithAcceleration(10).calculate(
      const Pose2d(Translation2d(), Rotation2d()),
    );
    expect(slow.omega.abs(), lessThan(fast.omega.abs()));
  });

  test('zero-length intermediate segments are handed off without NaN', () {
    final outcome = Path2Simulator.simulatePath(
      path('zero length', [
        waypoint(0, 0, heading: 0),
        waypoint(0, 0),
        waypoint(1, 0, heading: 0),
      ]),
      config,
    );

    expect(outcome.failure, isNull);
    expect(outcome.result!.terminalState.pose.x, closeTo(1, 0.12));
  });

  test('one-waypoint paths finish on a 20 ms boundary', () {
    final outcome = Path2Simulator.simulatePath(
      path('single', [waypoint(1, 2, heading: 0.4)]),
      config,
    );

    expect(outcome.failure, isNull);
    expect(outcome.result!.samples, hasLength(2));
    expect(outcome.result!.totalTimeSeconds, 0.02);
  });

  test('auto carries state and bridges disconnected paths without seam gaps',
      () {
    final outcome = Path2Simulator.simulateAuto(
      [
        path('first', [
          waypoint(0, 0, heading: 0),
          waypoint(1, 0, heading: 0),
        ]),
        path('second', [
          waypoint(2, 0, heading: 0),
          waypoint(3, 0, heading: 0),
        ]),
      ],
      config,
      const Pose2d(Translation2d(), Rotation2d()),
    );

    expect(outcome.failure, isNull);
    final samples = outcome.result!.samples;
    expect(samples.last.pose.x, closeTo(3.0, 0.12));
    expect(samples.any((sample) => sample.pose.x > 1.2 && sample.pose.x < 1.8),
        isTrue);
    for (var i = 1; i < samples.length; i++) {
      expect(
        samples[i].timeSeconds - samples[i - 1].timeSeconds,
        closeTo(0.02, 1e-12),
      );
    }
  });

  test('rejects invalid waypoint constraints as a typed failure', () {
    final outcome = Path2Simulator.simulatePath(
      path('invalid', [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: 0, maxAngularVelocity: 0),
      ]),
      config,
    );

    expect(outcome.result, isNull);
    expect(outcome.failure!.kind, Path2SimulationFailureKind.invalidPath);
  });

  test('reports a stalled path instead of looping forever', () {
    final outcome = Path2Simulator.simulatePath(
      path('stalled', [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: 0, maxVelocity: 0),
      ]),
      config,
    );

    expect(outcome.result, isNull);
    expect(outcome.failure!.kind, Path2SimulationFailureKind.stalled);
  });
}
