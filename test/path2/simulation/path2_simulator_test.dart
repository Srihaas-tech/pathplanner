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
    List<Path2SimulationWaypoint> waypoints, {
    List<Path2SimulationEventMarker> eventMarkers = const [],
    List<Path2SimulationConstraintsZone> constraintZones = const [],
    List<Path2SimulationPointTowardsZone> pointTowardsZones = const [],
  }) {
    return Path2SimulationPathSnapshot(
      name: name,
      waypoints: waypoints,
      eventMarkers: eventMarkers,
      constraintZones: constraintZones,
      pointTowardsZones: pointTowardsZones,
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

  test('event markers fire once after passing their closest sample', () {
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: 0),
      ],
      eventMarkers: const [
        Path2SimulationEventMarker(waypointRelativePosition: 0.5),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    follower.calculate(
      const Pose2d(Translation2d(0.25, 0), Rotation2d()),
    );
    follower.calculate(
      const Pose2d(Translation2d(0.5, 0), Rotation2d()),
    );
    expect(follower.takeMarkerTransitions(), isEmpty);

    follower.calculate(
      const Pose2d(Translation2d(0.51, 0), Rotation2d()),
    );
    final transitions = follower.takeMarkerTransitions();
    expect(transitions, hasLength(1));
    expect(transitions.single.markerIndex, 0);
    expect(transitions.single.active, isTrue);
    expect(transitions.single.isZoned, isFalse);

    follower.calculate(
      const Pose2d(Translation2d(0.6, 0), Rotation2d()),
    );
    expect(follower.takeMarkerTransitions(), isEmpty);
  });

  test('a marker at the starting pose waits for a real increase', () {
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: 0),
      ],
      eventMarkers: const [
        Path2SimulationEventMarker(waypointRelativePosition: 0),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    expect(follower.takeMarkerTransitions(), isEmpty);
    follower.calculate(const Pose2d(Translation2d(), Rotation2d()));
    expect(follower.takeMarkerTransitions(), isEmpty);
    follower.calculate(
      const Pose2d(Translation2d(0.01, 0), Rotation2d()),
    );
    expect(follower.takeMarkerTransitions(), hasLength(1));
  });

  test('skipping past a marker target fires without a decreasing sample', () {
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: 0),
        waypoint(2, 0, heading: 0),
      ],
      eventMarkers: const [
        Path2SimulationEventMarker(waypointRelativePosition: 0.5),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    follower.calculate(
      const Pose2d(Translation2d(1, 0), Rotation2d()),
    );

    expect(follower.targetWaypointIndex, 2);
    expect(follower.takeMarkerTransitions(), hasLength(1));
  });

  test('integer marker stays gated until targeting the following waypoint', () {
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: 0, handoffDistance: 0.05),
        waypoint(2, 0, heading: 0),
      ],
      eventMarkers: const [
        Path2SimulationEventMarker(waypointRelativePosition: 1),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    follower.calculate(
      const Pose2d(Translation2d(0.9, 0.2), Rotation2d()),
    );
    follower.calculate(
      const Pose2d(Translation2d(0.9, 0.1), Rotation2d()),
    );
    follower.calculate(
      const Pose2d(Translation2d(0.9, 0.2), Rotation2d()),
    );
    expect(follower.targetWaypointIndex, 1);
    expect(follower.takeMarkerTransitions(), isEmpty);

    follower.calculate(
      const Pose2d(Translation2d(1, 0), Rotation2d()),
    );
    expect(follower.targetWaypointIndex, 2);
    expect(follower.takeMarkerTransitions(), isEmpty);
    follower.calculate(
      const Pose2d(Translation2d(1.01, 0), Rotation2d()),
    );
    expect(follower.takeMarkerTransitions(), hasLength(1));
  });

  test('terminal finalization flushes every pending marker boundary', () {
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: 0),
      ],
      eventMarkers: const [
        Path2SimulationEventMarker(waypointRelativePosition: 0.5),
        Path2SimulationEventMarker(
          waypointRelativePosition: 0.25,
          endWaypointRelativePosition: 0.75,
        ),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    follower.finalize(
      const Pose2d(Translation2d(1, 0), Rotation2d()),
    );
    final transitions = follower.takeMarkerTransitions();

    expect(transitions, hasLength(3));
    expect(
      transitions.where((transition) => transition.markerIndex == 0),
      hasLength(1),
    );
    expect(
      transitions
          .where((transition) => transition.markerIndex == 1)
          .map((transition) => transition.active),
      [true, false],
    );
  });

  test('constraints zones override the target waypoint constraints', () {
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: 0, maxVelocity: 3),
      ],
      constraintZones: const [
        Path2SimulationConstraintsZone(
          minWaypointRelativePosition: 0.25,
          maxWaypointRelativePosition: 0.75,
          constraints: Path2SimulationConstraints(
            maxVelocity: 0.1,
            maxAngularVelocityRadiansPerSecond: 1,
            maxAngularAccelerationRadiansPerSecondSquared: 1,
          ),
        ),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    follower.calculate(
      const Pose2d(Translation2d(0.25, 0), Rotation2d()),
    );
    final inside = follower.calculate(
      const Pose2d(Translation2d(0.26, 0), Rotation2d()),
    );

    expect(math.sqrt(inside.vx * inside.vx + inside.vy * inside.vy),
        lessThanOrEqualTo(0.100000001));
  });

  test('first overlapping constraints zone wins and constraints restore', () {
    const firstZone = Path2SimulationConstraintsZone(
      minWaypointRelativePosition: 0.25,
      maxWaypointRelativePosition: 0.75,
      constraints: Path2SimulationConstraints(
        maxVelocity: 0.1,
        maxAngularVelocityRadiansPerSecond: 1,
        maxAngularAccelerationRadiansPerSecondSquared: 1,
      ),
    );
    const secondZone = Path2SimulationConstraintsZone(
      minWaypointRelativePosition: 0.25,
      maxWaypointRelativePosition: 0.75,
      constraints: Path2SimulationConstraints(
        maxVelocity: 0.4,
        maxAngularVelocityRadiansPerSecond: 2,
        maxAngularAccelerationRadiansPerSecondSquared: 2,
      ),
    );
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(2, 0, heading: 0, maxVelocity: 1.5, handoffDistance: 0),
      ],
      constraintZones: const [firstZone, secondZone],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    follower.calculate(
      const Pose2d(Translation2d(0.5, 0), Rotation2d()),
    );
    final inside = follower.calculate(
      const Pose2d(Translation2d(0.51, 0), Rotation2d()),
    );
    final insideSpeed = math.sqrt(
      inside.vx * inside.vx + inside.vy * inside.vy,
    );
    expect(insideSpeed, closeTo(0.1, 1e-9));

    follower.calculate(
      const Pose2d(Translation2d(1.5, 0), Rotation2d()),
    );
    final outside = follower.calculate(
      const Pose2d(Translation2d(1.51, 0), Rotation2d()),
    );
    final outsideSpeed = math.sqrt(
      outside.vx * outside.vx + outside.vy * outside.vy,
    );
    expect(outsideSpeed, greaterThan(0.4));
  });

  test('point-towards zones override pose waypoint headings', () {
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: 0),
      ],
      pointTowardsZones: const [
        Path2SimulationPointTowardsZone(
          fieldPosition: Translation2d(0, 1),
          rotationOffset: Rotation2d(),
          minWaypointRelativePosition: 0.25,
          maxWaypointRelativePosition: 0.75,
        ),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    follower.calculate(
      const Pose2d(Translation2d(0.25, 0), Rotation2d()),
    );
    final inside = follower.calculate(
      const Pose2d(Translation2d(0.26, 0), Rotation2d()),
    );

    expect(inside.omega, greaterThan(0));
  });

  test('point-zone entry heading participates in heading lookahead', () {
    Path2PathFollower follower({
      required double zoneStart,
      required List<Path2SimulationWaypoint> waypoints,
    }) {
      return Path2PathFollower(
        waypoints: waypoints,
        pointTowardsZones: [
          Path2SimulationPointTowardsZone(
            fieldPosition: const Translation2d(1, 2),
            rotationOffset: const Rotation2d(),
            minWaypointRelativePosition: zoneStart,
            maxWaypointRelativePosition: zoneStart + 0.25,
          ),
        ],
        endToleranceMeters: 0.1,
        endAngleToleranceRadians: 0.05,
        initialPose: const Pose2d(Translation2d(), Rotation2d()),
        initialRobotRelativeSpeeds: const ChassisSpeeds(),
        targetFirstWaypoint: false,
      );
    }

    final zoneBeforePose = follower(
      zoneStart: 0.5,
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(2, 0, heading: 0),
      ],
    );
    expect(
      zoneBeforePose
          .calculate(const Pose2d(Translation2d(), Rotation2d()))
          .omega,
      greaterThan(0),
    );

    final poseBeforeZone = follower(
      zoneStart: 1.5,
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(1, 0, heading: -0.5),
        waypoint(2, 0, heading: 0),
      ],
    );
    expect(
      poseBeforeZone
          .calculate(const Pose2d(Translation2d(), Rotation2d()))
          .omega,
      lessThan(0),
    );
  });

  test('unprofiled point zone uses PID then resets the profile on exit', () {
    Path2PathFollower follower(bool unprofiled) {
      return Path2PathFollower(
        waypoints: [
          waypoint(0, 0, heading: 0),
          waypoint(2, 0, heading: -3),
        ],
        pointTowardsZones: [
          Path2SimulationPointTowardsZone(
            fieldPosition: const Translation2d(0.5, 2),
            rotationOffset: const Rotation2d(),
            minWaypointRelativePosition: 0.25,
            maxWaypointRelativePosition: 0.5,
            unprofiled: unprofiled,
          ),
        ],
        endToleranceMeters: 0.1,
        endAngleToleranceRadians: 0.05,
        initialPose: const Pose2d(Translation2d(), Rotation2d()),
        initialRobotRelativeSpeeds: const ChassisSpeeds(),
        targetFirstWaypoint: false,
      );
    }

    double enterZone(Path2PathFollower follower) {
      follower.calculate(
        const Pose2d(Translation2d(0.5, 0), Rotation2d()),
      );
      return follower
          .calculate(
            const Pose2d(Translation2d(0.51, 0), Rotation2d()),
          )
          .omega
          .abs()
          .toDouble();
    }

    final profiledOutput = enterZone(follower(false));
    final unprofiledFollower = follower(true);
    final unprofiledOutput = enterZone(unprofiledFollower);
    expect(unprofiledOutput, greaterThan(profiledOutput * 5));

    unprofiledFollower.calculate(
      Pose2d(
        const Translation2d(1, 0),
        Rotation2d.fromRadians(2.5),
      ),
      const ChassisSpeeds(omega: 0.7),
    );
    final firstProfiledOutput = unprofiledFollower.calculate(
      Pose2d(
        const Translation2d(1.01, 0),
        Rotation2d.fromRadians(2.5),
      ),
      const ChassisSpeeds(omega: 0.7),
    );
    expect(firstProfiledOutput.omega.abs(), lessThan(1));
  });

  test('simulated robot rotates toward a point-towards target', () {
    final outcome = Path2Simulator.simulatePath(
      path(
        'point target simulation',
        [
          waypoint(0, 0, heading: 0),
          waypoint(2, 0, heading: 0),
        ],
        pointTowardsZones: const [
          Path2SimulationPointTowardsZone(
            fieldPosition: Translation2d(1, 2),
            rotationOffset: Rotation2d(),
            minWaypointRelativePosition: 0.25,
            maxWaypointRelativePosition: 0.75,
          ),
        ],
      ),
      config,
    );

    expect(outcome.failure, isNull);
    final beforeZone = outcome.result!.samples.where(
      (sample) => sample.pose.x > 0.1 && sample.pose.x < 0.45,
    );
    expect(beforeZone, isNotEmpty);
    expect(
      beforeZone
          .map((sample) => sample.pose.rotation.radians.abs())
          .reduce(math.max),
      greaterThan(0.02),
    );
    final insideZone = outcome.result!.samples.where(
      (sample) => sample.pose.x > 0.7 && sample.pose.x < 1.3,
    );
    expect(insideZone, isNotEmpty);
    expect(
      insideZone
          .map((sample) => sample.pose.rotation.radians.abs())
          .reduce(math.max),
      greaterThan(0.2),
    );

    final intermediatePoseOutcome = Path2Simulator.simulatePath(
      path(
        'point target before an intermediate pose',
        [
          waypoint(0, 0, heading: 0),
          waypoint(1, 0, heading: 0),
          waypoint(2, 0, heading: 0),
        ],
        pointTowardsZones: const [
          Path2SimulationPointTowardsZone(
            fieldPosition: Translation2d(0.5, 2),
            rotationOffset: Rotation2d(),
            minWaypointRelativePosition: 0.25,
            maxWaypointRelativePosition: 0.75,
          ),
        ],
      ),
      config,
    );
    expect(intermediatePoseOutcome.failure, isNull);
    final beforeIntermediatePose = intermediatePoseOutcome.result!.samples
        .where((sample) => sample.pose.x > 0.35 && sample.pose.x < 0.7);
    expect(beforeIntermediatePose, isNotEmpty);
    expect(
      beforeIntermediatePose
          .map((sample) => sample.pose.rotation.radians.abs())
          .reduce(math.max),
      greaterThan(0.1),
    );
  });

  test('first point-towards zone wins and pose heading restores after exit',
      () {
    final follower = Path2PathFollower(
      waypoints: [
        waypoint(0, 0, heading: 0),
        waypoint(2, 0, heading: 0, handoffDistance: 0),
      ],
      pointTowardsZones: const [
        Path2SimulationPointTowardsZone(
          fieldPosition: Translation2d(1, 2),
          rotationOffset: Rotation2d(),
          minWaypointRelativePosition: 0.25,
          maxWaypointRelativePosition: 0.75,
        ),
        Path2SimulationPointTowardsZone(
          fieldPosition: Translation2d(1, -2),
          rotationOffset: Rotation2d(),
          minWaypointRelativePosition: 0.25,
          maxWaypointRelativePosition: 0.75,
        ),
      ],
      endToleranceMeters: 0.1,
      endAngleToleranceRadians: 0.05,
      initialPose: const Pose2d(Translation2d(), Rotation2d()),
      initialRobotRelativeSpeeds: const ChassisSpeeds(),
      targetFirstWaypoint: false,
    );

    follower.calculate(
      const Pose2d(Translation2d(0.5, 0), Rotation2d()),
    );
    final inside = follower.calculate(
      const Pose2d(Translation2d(0.51, 0), Rotation2d()),
    );
    expect(inside.omega, greaterThan(0));

    follower.calculate(
      const Pose2d(Translation2d(1.5, 0), Rotation2d()),
    );
    var restored = follower.calculate(
      const Pose2d(Translation2d(1.51, 0), Rotation2d()),
    );
    for (var i = 0; i < 20; i++) {
      restored = follower.calculate(
        const Pose2d(Translation2d(1.51, 0), Rotation2d()),
      );
    }
    expect(restored.omega, closeTo(0, 1e-9));
  });

  test('simulation records point and zoned marker trigger samples', () {
    final outcome = Path2Simulator.simulatePath(
      path(
        'markers',
        [
          waypoint(0, 0, heading: 0),
          waypoint(2, 0, heading: 0),
        ],
        eventMarkers: const [
          Path2SimulationEventMarker(waypointRelativePosition: 0.5),
          Path2SimulationEventMarker(
            waypointRelativePosition: 0.25,
            endWaypointRelativePosition: 0.75,
          ),
          Path2SimulationEventMarker(waypointRelativePosition: 1),
        ],
      ),
      config,
    );

    expect(outcome.failure, isNull);
    final result = outcome.result!;
    expect(result.markerActivations, hasLength(3));

    final point = result.markerActivations
        .singleWhere((activation) => activation.markerIndex == 0);
    expect(point.endTimeSeconds, isNull);
    expect(result.sampleAt(point.startTimeSeconds).pose.x, closeTo(1, 0.15));

    final zone = result.markerActivations
        .singleWhere((activation) => activation.markerIndex == 1);
    expect(zone.endTimeSeconds, isNotNull);
    expect(result.sampleAt(zone.startTimeSeconds).pose.x, closeTo(0.5, 0.15));
    expect(result.sampleAt(zone.endTimeSeconds!).pose.x, closeTo(1.5, 0.15));

    final terminal = result.markerActivations
        .singleWhere((activation) => activation.markerIndex == 2);
    expect(terminal.startTimeSeconds, result.totalTimeSeconds);
  });

  test('snapshot marker and zone primitives round trip through a map', () {
    final original = path(
      'snapshot',
      [waypoint(0, 0, heading: 0), waypoint(1, 0, heading: 0)],
      eventMarkers: const [
        Path2SimulationEventMarker(
          waypointRelativePosition: 0.2,
          endWaypointRelativePosition: 0.4,
        ),
      ],
      constraintZones: const [
        Path2SimulationConstraintsZone(
          minWaypointRelativePosition: 0.3,
          maxWaypointRelativePosition: 0.6,
          constraints: Path2SimulationConstraints(
            maxVelocity: 1,
            maxAngularVelocityRadiansPerSecond: 2,
            maxAngularAccelerationRadiansPerSecondSquared: 3,
          ),
        ),
      ],
      pointTowardsZones: const [
        Path2SimulationPointTowardsZone(
          fieldPosition: Translation2d(4, 5),
          rotationOffset: Rotation2d(0.2),
          minWaypointRelativePosition: 0.4,
          maxWaypointRelativePosition: 0.8,
          unprofiled: true,
        ),
      ],
    );

    final restored = Path2SimulationPathSnapshot.fromMap(original.toMap());

    expect(restored.eventMarkers.single.endWaypointRelativePosition, 0.4);
    expect(restored.constraintZones.single.constraints.maxVelocity, 1);
    expect(restored.pointTowardsZones.single.fieldPosition,
        const Translation2d(4, 5));
    expect(restored.pointTowardsZones.single.rotationOffset.radians, 0.2);
    expect(restored.pointTowardsZones.single.unprofiled, isTrue);
  });

  test('repeated auto paths retain occurrence indices and global times', () {
    final repeated = path(
      'repeated',
      [waypoint(0, 0, heading: 0), waypoint(1, 0, heading: 0)],
      eventMarkers: const [
        Path2SimulationEventMarker(waypointRelativePosition: 0.5),
      ],
    );
    final singleOccurrence = Path2Simulator.simulateAuto(
      [repeated],
      config,
      const Pose2d(Translation2d(), Rotation2d()),
    );
    final repeatedOccurrence = Path2Simulator.simulateAuto(
      [repeated, repeated],
      config,
      const Pose2d(Translation2d(), Rotation2d()),
    );

    expect(singleOccurrence.failure, isNull);
    expect(repeatedOccurrence.failure, isNull);
    final activations = repeatedOccurrence.result!.markerActivations;
    expect(activations, hasLength(2));
    expect(activations.map((activation) => activation.pathIndex), [0, 1]);
    expect(
      activations.first.startTimeSeconds,
      singleOccurrence.result!.markerActivations.single.startTimeSeconds,
    );
    expect(
      activations.last.startTimeSeconds,
      greaterThanOrEqualTo(singleOccurrence.result!.totalTimeSeconds),
    );
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
