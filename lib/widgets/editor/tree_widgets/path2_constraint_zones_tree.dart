import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pathplanner/path2/constraints_zone.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/util/wpimath/math_util.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/item_count.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/tree_card_node.dart';
import 'package:pathplanner/widgets/number_text_field.dart';
import 'package:pathplanner/widgets/renamable_title.dart';
import 'package:undo/undo.dart';

class Path2ConstraintZonesTree extends StatefulWidget {
  final path2.Path path;
  final VoidCallback? onPathChanged;
  final VoidCallback? onPathChangedNoSim;
  final ValueChanged<int?>? onZoneHovered;
  final ValueChanged<int?>? onZoneSelected;
  final int? initiallySelectedZone;
  final ChangeStack undoStack;

  const Path2ConstraintZonesTree({
    super.key,
    required this.path,
    required this.undoStack,
    this.onPathChanged,
    this.onPathChangedNoSim,
    this.onZoneHovered,
    this.onZoneSelected,
    this.initiallySelectedZone,
  });

  @override
  State<Path2ConstraintZonesTree> createState() =>
      _Path2ConstraintZonesTreeState();
}

class _Path2ConstraintZonesTreeState extends State<Path2ConstraintZonesTree> {
  List<ConstraintsZone> get zones => widget.path.constraintZones;

  late List<ExpansibleController> _controllers;
  int? _selectedZone;
  double _sliderChangeStart = 0;

  double get _maxPosition =>
      (widget.path.waypoints.length - 1).clamp(0, double.infinity).toDouble();

  @override
  void initState() {
    super.initState();
    _selectedZone = widget.initiallySelectedZone;
    _controllers = _newControllers();
  }

  @override
  Widget build(BuildContext context) {
    _syncControllers();
    return TreeCardNode(
      title: const Text('Constraint Zones'),
      leading: const Icon(Icons.speed_rounded),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Add New Constraint Zone',
            onPressed: _addZone,
          ),
          const SizedBox(width: 8),
          ItemCount(count: zones.length),
        ],
      ),
      initiallyExpanded: widget.path.constraintZonesExpanded,
      onExpansionChanged: (expanded) {
        if (expanded == null) return;
        widget.path.constraintZonesExpanded = expanded;
        if (!expanded) _clearSelection();
      },
      elevation: 1,
      children: [
        const Center(
          child: Text('Zones at the top of the list have higher priority'),
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < zones.length; index++)
          _buildZoneCard(index),
      ],
    );
  }

  Widget _buildZoneCard(int zoneIdx) {
    final colorScheme = Theme.of(context).colorScheme;
    final zone = zones[zoneIdx];

    return TreeCardNode(
      controller: _controllers[zoneIdx],
      onHoverStart: () => widget.onZoneHovered?.call(zoneIdx),
      onHoverEnd: () => widget.onZoneHovered?.call(null),
      onExpansionChanged: (expanded) {
        if (expanded ?? false) {
          final selected = _selectedZone;
          if (selected != null && selected != zoneIdx) {
            _controllers[selected].collapse();
          }
          _selectedZone = zoneIdx;
          widget.onZoneSelected?.call(zoneIdx);
        } else if (_selectedZone == zoneIdx) {
          _selectedZone = null;
          widget.onZoneSelected?.call(null);
        }
      },
      title: Row(
        children: [
          RenamableTitle(
            title: zone.name,
            onRename: (name) => _addZoneChange(
              zoneIdx,
              (updated) => updated.name = name,
              simulate: false,
            ),
          ),
          const Spacer(),
          if (_selectedZone == null) ...[
            Tooltip(
              message: 'Move Zone Up',
              waitDuration: const Duration(seconds: 1),
              child: IconButton(
                icon: const Icon(Icons.expand_less),
                color: colorScheme.onSurface,
                onPressed: zoneIdx == 0 ? null : () => _moveZone(zoneIdx, -1),
              ),
            ),
            Tooltip(
              message: 'Move Zone Down',
              waitDuration: const Duration(seconds: 1),
              child: IconButton(
                icon: const Icon(Icons.expand_more),
                color: colorScheme.onSurface,
                onPressed: zoneIdx == zones.length - 1
                    ? null
                    : () => _moveZone(zoneIdx, 1),
              ),
            ),
          ],
          Tooltip(
            message: 'Delete Zone',
            waitDuration: const Duration(seconds: 1),
            child: IconButton(
              icon: const Icon(Icons.delete_forever),
              color: colorScheme.error,
              onPressed: () => _deleteZone(zoneIdx),
            ),
          ),
        ],
      ),
      initiallyExpanded: zoneIdx == _selectedZone,
      elevation: 4,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: NumberTextField(
            key: ValueKey('path2ConstraintZone${zoneIdx}MaxVelocity'),
            initialValue: zone.constraints.maxVelocity,
            label: 'Max Velocity (M/S)',
            minValue: 0.1,
            onSubmitted: (value) {
              if (value != null) {
                _addConstraintsChange(
                  zoneIdx,
                  (constraints) => constraints.maxVelocity = value,
                );
              }
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: NumberTextField(
                  key: ValueKey(
                      'path2ConstraintZone${zoneIdx}MaxAngularVelocity'),
                  initialValue: zone.constraints.maxAngularVelocity,
                  label: 'Max Angular Velocity (Deg/S)',
                  arrowKeyIncrement: 1,
                  minValue: 0.1,
                  onSubmitted: (value) {
                    if (value != null) {
                      _addConstraintsChange(
                        zoneIdx,
                        (constraints) => constraints.maxAngularVelocity = value,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumberTextField(
                  key: ValueKey(
                      'path2ConstraintZone${zoneIdx}MaxAngularAcceleration'),
                  initialValue: zone.constraints.maxAngularAcceleration,
                  label: 'Max Angular Acceleration (Deg/S²)',
                  arrowKeyIncrement: 1,
                  minValue: 0.1,
                  onSubmitted: (value) {
                    if (value != null) {
                      _addConstraintsChange(
                        zoneIdx,
                        (constraints) =>
                            constraints.maxAngularAcceleration = value,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildRangeEditor(zoneIdx, start: true),
        const SizedBox(height: 8),
        _buildRangeEditor(zoneIdx, start: false),
      ],
    );
  }

  Widget _buildRangeEditor(int zoneIdx, {required bool start}) {
    final zone = zones[zoneIdx];
    final position =
        start ? zone.minWaypointRelativePos : zone.maxWaypointRelativePos;

    return Row(
      children: [
        Expanded(
          child: Slider(
            value: position.toDouble().clamp(0, _maxPosition),
            secondaryTrackValue: start
                ? zone.maxWaypointRelativePos.toDouble().clamp(0, _maxPosition)
                : null,
            min: 0,
            max: _maxPosition,
            label: position.toStringAsFixed(2),
            onChangeStart: _maxPosition == 0
                ? null
                : (value) => _sliderChangeStart = value,
            onChanged: _maxPosition == 0
                ? null
                : (value) {
                    final valid = start
                        ? value <= zone.maxWaypointRelativePos
                        : value >= zone.minWaypointRelativePos;
                    if (!valid) return;
                    setState(() {
                      if (start) {
                        zone.minWaypointRelativePos = value;
                      } else {
                        zone.maxWaypointRelativePos = value;
                      }
                    });
                    _notify(simulate: false);
                  },
            onChangeEnd: _maxPosition == 0
                ? null
                : (_) => _addRangeChange(
                      zoneIdx,
                      _sliderChangeStart,
                      start
                          ? zone.minWaypointRelativePos
                          : zone.maxWaypointRelativePos,
                      start: start,
                    ),
          ),
        ),
        SizedBox(
          width: 75,
          child: NumberTextField(
            initialValue: position,
            precision: 2,
            label: start ? 'Start Pos' : 'End Pos',
            onSubmitted: (value) {
              if (value == null) return;
              final updated = start
                  ? MathUtil.clamp(value, 0, zone.maxWaypointRelativePos)
                  : MathUtil.clamp(
                      value,
                      zone.minWaypointRelativePos,
                      _maxPosition,
                    );
              _addZoneChange(zoneIdx, (changed) {
                if (start) {
                  changed.minWaypointRelativePos = updated;
                } else {
                  changed.maxWaypointRelativePos = updated;
                }
              });
            },
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  void _addZone() {
    final before = _cloneZones(zones);
    final waypoint =
        widget.path.waypoints[math.min(1, widget.path.waypoints.length - 1)];
    final after = _cloneZones(zones)
      ..add(ConstraintsZone(
        constraints: WaypointConstraints.fromWaypoint(waypoint),
      ));
    _addZonesListChange(before, after);
  }

  void _deleteZone(int zoneIdx) {
    final before = _cloneZones(zones);
    final after = _cloneZones(zones)..removeAt(zoneIdx);
    _addZonesListChange(before, after, clearSelection: true);
  }

  void _moveZone(int zoneIdx, int offset) {
    final before = _cloneZones(zones);
    final after = _cloneZones(zones);
    final destination = zoneIdx + offset;
    final moved = after.removeAt(zoneIdx);
    after.insert(destination, moved);
    _addZonesListChange(before, after, clearSelection: true);
  }

  void _addZonesListChange(
    List<ConstraintsZone> before,
    List<ConstraintsZone> after, {
    bool clearSelection = false,
  }) {
    widget.undoStack.add(Change<List<ConstraintsZone>>(
      before,
      () => _replaceZones(after, clearSelection: clearSelection),
      (oldValue) => _replaceZones(oldValue, clearSelection: clearSelection),
    ));
  }

  void _replaceZones(
    List<ConstraintsZone> replacement, {
    required bool clearSelection,
  }) {
    _apply(() {
      widget.path.constraintZones = _cloneZones(replacement);
      if (clearSelection) _clearSelection();
    });
  }

  void _addZoneChange(
    int zoneIdx,
    ValueChanged<ConstraintsZone> mutate, {
    bool simulate = true,
  }) {
    final before = zones[zoneIdx].clone();
    final after = before.clone();
    mutate(after);
    widget.undoStack.add(Change<ConstraintsZone>(
      before,
      () => _apply(
        () => zones[zoneIdx] = after.clone(),
        simulate: simulate,
      ),
      (oldValue) => _apply(
        () => zones[zoneIdx] = oldValue.clone(),
        simulate: simulate,
      ),
    ));
  }

  void _addConstraintsChange(
    int zoneIdx,
    ValueChanged<WaypointConstraints> mutate,
  ) {
    _addZoneChange(zoneIdx, (zone) => mutate(zone.constraints));
  }

  void _addRangeChange(
    int zoneIdx,
    num before,
    num after, {
    required bool start,
  }) {
    if (before == after) return;
    widget.undoStack.add(Change<num>(
      before,
      () => _apply(() {
        if (start) {
          zones[zoneIdx].minWaypointRelativePos = after;
        } else {
          zones[zoneIdx].maxWaypointRelativePos = after;
        }
      }),
      (oldValue) => _apply(() {
        if (start) {
          zones[zoneIdx].minWaypointRelativePos = oldValue;
        } else {
          zones[zoneIdx].maxWaypointRelativePos = oldValue;
        }
      }),
    ));
  }

  void _apply(VoidCallback mutation, {bool simulate = true}) {
    if (mounted) {
      setState(mutation);
    } else {
      mutation();
    }
    _notify(simulate: simulate);
  }

  void _notify({required bool simulate}) {
    if (simulate) {
      widget.onPathChanged?.call();
    } else if (widget.onPathChangedNoSim != null) {
      widget.onPathChangedNoSim!.call();
    } else {
      widget.onPathChanged?.call();
    }
  }

  void _clearSelection() {
    _selectedZone = null;
    widget.onZoneHovered?.call(null);
    widget.onZoneSelected?.call(null);
  }

  List<ExpansibleController> _newControllers() => List.generate(
        zones.length,
        (_) => ExpansibleController(),
      );

  void _syncControllers() {
    if (_controllers.length != zones.length) {
      _controllers = _newControllers();
      if (_selectedZone != null && _selectedZone! >= zones.length) {
        _clearSelection();
      }
    }
  }

  static List<ConstraintsZone> _cloneZones(Iterable<ConstraintsZone> zones) =>
      [for (final zone in zones) zone.clone()];
}
