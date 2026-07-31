import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart';
import 'package:pathplanner/services/log.dart';
import 'package:pathplanner/trajectory/trajectory.dart';
import 'package:pathplanner/util/wpimath/geometry.dart';
import 'package:pathplanner/util/wpimath/kinematics.dart';

class ChoreoEventMarker {
  final String name;
  final num time;

  const ChoreoEventMarker({
    required this.name,
    required this.time,
  });

  ChoreoEventMarker copyWithTime(num newTime) {
    return ChoreoEventMarker(
      name: name,
      time: newTime,
    );
  }
}

class ChoreoPath {
  final String name;
  final PathPlannerTrajectory trajectory;
  final List<ChoreoEventMarker> eventMarkers;

  final FileSystem fs;
  final String choreoDir;

  const ChoreoPath({
    required this.name,
    required this.trajectory,
    required this.fs,
    required this.choreoDir,
    required this.eventMarkers,
  });

  List<num> get eventMarkerTimes => [
        for (final marker in eventMarkers) marker.time,
      ];

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return null;
  }

  static String _parseMarkerName(
    Map<String, dynamic> event,
    int index,
  ) {
    final candidates = [
      event['name'],
      event['markerName'],
      event['eventName'],
      event['label'],
      event['title'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }

    return 'Marker ${index + 1}';
  }

  static num? _parseMarkerTime(Map<String, dynamic> event) {
    final directCandidates = [
      event['time'],
      event['timestamp'],
      event['targetTimestamp'],
      event['t'],
    ];

    for (final candidate in directCandidates) {
      if (candidate is num) {
        return candidate;
      }
    }

    final from = _asMap(event['from']);
    if (from != null) {
      final fromCandidates = [
        from['targetTimestamp'],
        from['time'],
        from['timestamp'],
        from['t'],
      ];

      for (final candidate in fromCandidates) {
        if (candidate is num) {
          return candidate;
        }
      }
    }

    return null;
  }

  static List<ChoreoEventMarker> _parseEventMarkers(
    Map<String, dynamic> json,
  ) {
    final events = json['events'];
    if (events is! List<dynamic>) {
      return [];
    }

    final markers = <ChoreoEventMarker>[];

    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      if (event is! Map<String, dynamic>) {
        continue;
      }

      final time = _parseMarkerTime(event);
      if (time == null) {
        continue;
      }

      markers.add(
        ChoreoEventMarker(
          name: _parseMarkerName(event, i),
          time: time,
        ),
      );
    }

    markers.sort((a, b) => a.time.compareTo(b.time));
    return markers;
  }

  static List<ChoreoEventMarker> _splitEventMarkers(
    List<ChoreoEventMarker> parentMarkers,
    num startTime,
    num? endTime,
  ) {
    final splitMarkers = <ChoreoEventMarker>[];

    for (final marker in parentMarkers) {
      final inRange = marker.time >= startTime &&
          (endTime == null || marker.time < endTime);

      if (inRange) {
        splitMarkers.add(
          marker.copyWithTime(marker.time - startTime),
        );
      }
    }

    return splitMarkers;
  }

  ChoreoPath.fromTrajJson(
    Map<String, dynamic> json,
    String name,
    String choreoDir,
    FileSystem fs,
  )   : this(
          name: name,
          trajectory: PathPlannerTrajectory.fromStates(
            [
              for (final dynamic sample
                  in (_asMap(json['trajectory'])?['samples']
                          as List<dynamic>? ??
                      const <dynamic>[]))
                if (sample is Map<String, dynamic>)
                  TrajectoryState.pregen(
                    sample['t'],
                    ChassisSpeeds(
                      vx: sample['vx'],
                      vy: sample['vy'],
                      omega: sample['omega'],
                    ),
                    Pose2d(
                      Translation2d(sample['x'], sample['y']),
                      Rotation2d.fromRadians(sample['heading']),
                    ),
                  ),
            ],
          ),
          fs: fs,
          choreoDir: choreoDir,
          eventMarkers: _parseEventMarkers(json),
        );

  static Future<List<ChoreoPath>> loadAllPathsInDir(
    String choreoDir,
    FileSystem fs,
  ) async {
    final paths = <ChoreoPath>[];

    final dir = fs.directory(choreoDir);

    if (await dir.exists()) {
      final files = dir.listSync();

      for (final FileSystemEntity e in files) {
        if (!e.path.endsWith('.traj')) {
          continue;
        }

        final file = fs.file(e.path);
        final pathName = basenameWithoutExtension(e.path);
        final jsonStr = await file.readAsString();

        try {
          final Map<String, dynamic> json = jsonDecode(jsonStr);

          final path =
              ChoreoPath.fromTrajJson(json, pathName, choreoDir, fs);

          if (path.trajectory.states.isEmpty) {
            Log.error(
              'Failed to load choreo path: $pathName. Path has no trajectory states',
            );
            continue;
          }

          paths.add(path);

          final trajectoryJson = _asMap(json['trajectory']);
          final splits = ((trajectoryJson?['splits'] as List<dynamic>? ??
                      const [])
                  .map((e) => (e as num).toInt()))
              .toList();

          if (splits.isEmpty || splits.first != 0) {
            splits.insert(0, 0);
          }

          for (int i = 0; i < splits.length; i++) {
            final splitName = '$pathName.$i';

            final startIdx = splits[i];
            final int endIdx;
            if (i == splits.length - 1) {
              endIdx = path.trajectory.states.length;
            } else {
              endIdx = splits[i + 1];
            }

            final startTime = path.trajectory.states[startIdx].timeSeconds;
            final num? endTime = i == splits.length - 1
                ? null
                : path.trajectory.states[endIdx].timeSeconds;

            final splitStates = [
              for (final TrajectoryState s
                  in path.trajectory.states.sublist(startIdx, endIdx))
                s.copyWithTime(s.timeSeconds - startTime),
            ];

            final splitTraj = PathPlannerTrajectory.fromStates(splitStates);

            final splitPath = ChoreoPath(
              name: splitName,
              trajectory: splitTraj,
              fs: fs,
              choreoDir: choreoDir,
              eventMarkers: _splitEventMarkers(
                path.eventMarkers,
                startTime,
                endTime,
              ),
            );

            paths.add(splitPath);
          }
        } catch (ex, stack) {
          Log.error('Failed to load choreo path: $pathName', ex, stack);
        }
      }
    }

    return paths;
  }

  List<Translation2d> get pathPositions => [
        for (final TrajectoryState s in trajectory.states) s.pose.translation,
      ];
}
