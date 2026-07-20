import 'package:collection/collection.dart';
import 'package:pathplanner/commands/command.dart';

/// Grey-tinted colors spaced evenly around the full hue wheel.
const List<int> eventMarkerColorPalette = [
  0xFF874242,
  0xFF877542,
  0xFF648742,
  0xFF428753,
  0xFF428787,
  0xFF425387,
  0xFF644287,
  0xFF874275,
];

int eventMarkerColorForIndex(int index) =>
    eventMarkerColorPalette[index % eventMarkerColorPalette.length];

/// A waypoint-relative event marker on a Path 2 path.
class EventMarker {
  String name;
  num waypointRelativePos;
  num? endWaypointRelativePos;
  Command? command;

  EventMarker({
    this.name = '',
    this.waypointRelativePos = 0,
    this.endWaypointRelativePos,
    this.command,
  });

  EventMarker.fromJson(Map<String, dynamic> json)
      : name = _string(json, 'name'),
        waypointRelativePos = _finiteNum(json, 'waypointRelativePos'),
        endWaypointRelativePos =
            _optionalFiniteNum(json, 'endWaypointRelativePos'),
        command = _commandFromJson(json['command']);

  bool get isZoned => endWaypointRelativePos != null;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'waypointRelativePos': waypointRelativePos,
      'endWaypointRelativePos': endWaypointRelativePos,
      'command': command?.toJson(),
    };
  }

  EventMarker clone() {
    return EventMarker(
      name: name,
      waypointRelativePos: waypointRelativePos,
      endWaypointRelativePos: endWaypointRelativePos,
      command: command?.clone(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EventMarker &&
      other.name == name &&
      other.waypointRelativePos == waypointRelativePos &&
      other.endWaypointRelativePos == endWaypointRelativePos &&
      other.command == command;

  @override
  int get hashCode => Object.hash(
        name,
        waypointRelativePos,
        endWaypointRelativePos,
        const DeepCollectionEquality().hash(command?.toJson()),
      );
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

num? _optionalFiniteNum(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! num || !value.isFinite) {
    throw FormatException('$key must be a finite number or null');
  }
  return value;
}

Command? _commandFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! Map<String, dynamic>) {
    throw const FormatException('command must be an object or null');
  }
  final command = Command.fromJson(value);
  if (command == null) {
    throw const FormatException('command has an unknown type');
  }
  return command;
}
