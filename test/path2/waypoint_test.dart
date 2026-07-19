import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/path2/waypoint.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';

void main() {
  group('Path2 waypoint persistence', () {
    test('translation waypoint round trips every common limit', () {
      final waypoint = TranslationWaypoint(
        position: const Translation2d(1.2, 3.4),
        maxVelocity: 5.6,
        handoffDistance: 0.7,
        maxAngularVelocity: 180,
        maxAngularAcceleration: 360,
      );

      final json = waypoint.toJson();
      final restored = Waypoint.fromJson(json);

      expect(json['type'], 'translation');
      expect(json['handoffDistance'], 0.7);
      expect(restored, waypoint);
      expect(restored, isA<TranslationWaypoint>());
    });

    test('pose waypoint round trips its heading and common limits', () {
      final waypoint = PoseWaypoint(
        position: const Translation2d(2, 4),
        rotation: Rotation2d.fromDegrees(123),
        maxVelocity: 3,
        handoffDistance: 0.5,
        maxAngularVelocity: 200,
        maxAngularAcceleration: 400,
      );

      final restored = Waypoint.fromJson(waypoint.toJson());

      expect(restored, waypoint);
      expect(restored, isA<PoseWaypoint>());
      expect((restored as PoseWaypoint).rotation.degrees, closeTo(123, 1E-9));
    });

    test('omitted optional limits use model defaults', () {
      final waypoint = Waypoint.fromJson({
        'type': 'translation',
        'position': {'x': 1, 'y': 2},
      });

      expect(waypoint.maxVelocity, Waypoint.defaultMaxVelocity);
      expect(waypoint.handoffDistance, Waypoint.defaultHandoffDistance);
      expect(waypoint.maxAngularVelocity, Waypoint.defaultMaxAngularVelocity);
      expect(waypoint.maxAngularAcceleration,
          Waypoint.defaultMaxAngularAcceleration);
    });

    test('required waypoint values are validated', () {
      expect(
          () => Waypoint.fromJson({
                'type': 'translation',
                'position': {'x': 1},
              }),
          throwsFormatException);
      expect(
          () => Waypoint.fromJson({
                'type': 'pose',
                'position': {'x': 1, 'y': 2},
              }),
          throwsFormatException);
      expect(
          () => Waypoint.fromJson({
                'type': 'other',
                'position': {'x': 1, 'y': 2},
              }),
          throwsFormatException);
    });
  });

  group('Path2 waypoint editing', () {
    test('clone preserves subtype and is independently editable', () {
      final original = PoseWaypoint(
        position: const Translation2d(1, 2),
        rotation: Rotation2d.fromDegrees(45),
        maxVelocity: 3,
        handoffDistance: 0.4,
        maxAngularVelocity: 100,
        maxAngularAcceleration: 200,
      );

      final clone = original.clone();
      clone.move(8, 9);

      expect(clone, isA<PoseWaypoint>());
      expect(original.position, const Translation2d(1, 2));
      expect(clone.position, const Translation2d(8, 9));
      expect(clone.rotation, original.rotation);
      expect(clone.maxVelocity, original.maxVelocity);
      expect(clone.handoffDistance, original.handoffDistance);
    });

    test('withRotation converts subtype and preserves common limits', () {
      final translation = TranslationWaypoint(
        position: const Translation2d(1, 2),
        maxVelocity: 3,
        handoffDistance: 0.4,
        maxAngularVelocity: 100,
        maxAngularAcceleration: 200,
      );

      final pose = translation.withRotation(Rotation2d.fromDegrees(90));
      final convertedBack = pose.withRotation(null);

      expect(pose, isA<PoseWaypoint>());
      expect((pose as PoseWaypoint).rotation.degrees, closeTo(90, 1E-9));
      expect(convertedBack, isA<TranslationWaypoint>());
      expect(convertedBack.position, translation.position);
      expect(convertedBack.maxVelocity, translation.maxVelocity);
      expect(convertedBack.handoffDistance, translation.handoffDistance);
      expect(convertedBack.maxAngularVelocity, translation.maxAngularVelocity);
      expect(convertedBack.maxAngularAcceleration,
          translation.maxAngularAcceleration);
    });

    test('anchor hit testing and dragging move only during an active drag', () {
      final waypoint = TranslationWaypoint(position: const Translation2d(2, 3));

      expect(waypoint.isPointInAnchor(2.1, 3.1, 0.25), true);
      expect(waypoint.startDragging(5, 5, 0.25), false);
      waypoint.dragUpdate(6, 7);
      expect(waypoint.position, const Translation2d(2, 3));

      expect(waypoint.startDragging(2, 3, 0.25), true);
      expect(waypoint.isDragging, true);
      waypoint.dragUpdate(6, 7);
      expect(waypoint.position, const Translation2d(6, 7));

      waypoint.stopDragging();
      waypoint.dragUpdate(8, 9);
      expect(waypoint.isDragging, false);
      expect(waypoint.position, const Translation2d(6, 7));
    });

    test('handoff uses the configured distance', () {
      final waypoint = TranslationWaypoint(
          position: const Translation2d(1, 1), handoffDistance: 0.5);

      expect(waypoint.shouldHandoff(const Translation2d(1.3, 1.4)), true);
      expect(waypoint.shouldHandoff(const Translation2d(1.4, 1.4)), false);
    });
  });
}
