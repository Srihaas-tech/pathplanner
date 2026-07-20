import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:pathplanner/commands/command.dart';
import 'package:pathplanner/commands/command_groups.dart';
import 'package:pathplanner/commands/named_command.dart';
import 'package:pathplanner/path2/event_marker.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/services/project_event_registry.dart';
import 'package:pathplanner/util/wpimath/math_util.dart';
import 'package:pathplanner/widgets/editor/info_card.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/commands/add_command_button.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/commands/command_group_widget.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/commands/named_command_widget.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/item_count.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/tree_card_node.dart';
import 'package:pathplanner/widgets/number_text_field.dart';
import 'package:undo/undo.dart';

class Path2EventMarkersTree extends StatefulWidget {
  final path2.Path path;
  final VoidCallback? onPathChanged;
  final VoidCallback? onPathChangedNoSim;
  final ValueChanged<int?>? onMarkerHovered;
  final ValueChanged<int?>? onMarkerSelected;
  final int? initiallySelectedMarker;
  final ChangeStack undoStack;

  const Path2EventMarkersTree({
    super.key,
    required this.path,
    required this.undoStack,
    this.onPathChanged,
    this.onPathChangedNoSim,
    this.onMarkerHovered,
    this.onMarkerSelected,
    this.initiallySelectedMarker,
  });

  @override
  State<Path2EventMarkersTree> createState() => _Path2EventMarkersTreeState();
}

class _Path2EventMarkersTreeState extends State<Path2EventMarkersTree> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<EventMarker> get markers => widget.path.eventMarkers;

  late List<ExpansibleController> _controllers;
  int? _selectedMarker;
  double _sliderChangeStart = 0;

  double get _maxPosition =>
      (widget.path.waypoints.length - 1).clamp(0, double.infinity).toDouble();

  @override
  void initState() {
    super.initState();
    _selectedMarker = widget.initiallySelectedMarker;
    _controllers = _newControllers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncControllers();
    return TreeCardNode(
      title: const Text('Event Markers'),
      leading: const Icon(Icons.pin_drop_rounded),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Add New Event Marker',
            onPressed: _addMarker,
          ),
          const SizedBox(width: 8),
          ItemCount(count: markers.length),
        ],
      ),
      initiallyExpanded: widget.path.eventMarkersExpanded,
      onExpansionChanged: (expanded) {
        if (expanded == null) return;
        widget.path.eventMarkersExpanded = expanded;
        if (!expanded) _clearSelection();
      },
      elevation: 1,
      children: [
        for (var index = 0; index < markers.length; index++)
          _buildMarkerCard(index),
      ],
    );
  }

  Widget _buildMarkerCard(int markerIdx) {
    final colorScheme = Theme.of(context).colorScheme;
    final marker = markers[markerIdx];

    return TreeCardNode(
      leading: const Icon(Icons.pin_drop_rounded),
      controller: _controllers[markerIdx],
      onHoverStart: () => widget.onMarkerHovered?.call(markerIdx),
      onHoverEnd: () => widget.onMarkerHovered?.call(null),
      onExpansionChanged: (expanded) {
        if (expanded ?? false) {
          final selected = _selectedMarker;
          if (selected != null && selected != markerIdx) {
            _controllers[selected].collapse();
          }
          _selectedMarker = markerIdx;
          widget.onMarkerSelected?.call(markerIdx);
        } else if (_selectedMarker == markerIdx) {
          _selectedMarker = null;
          widget.onMarkerSelected?.call(null);
        }
      },
      title: Row(
        children: [
          Expanded(child: _buildEventNameDropdown(markerIdx)),
          const SizedBox(width: 12),
          InfoCard(
            value: marker.isZoned
                ? '${marker.waypointRelativePos.toStringAsFixed(2)}-'
                    '${marker.endWaypointRelativePos!.toStringAsFixed(2)}'
                : marker.waypointRelativePos.toStringAsFixed(2),
          ),
          Tooltip(
            message: 'Delete Marker',
            waitDuration: const Duration(seconds: 1),
            child: IconButton(
              icon: const Icon(Icons.delete_forever),
              color: colorScheme.error,
              onPressed: () => _deleteMarker(markerIdx),
            ),
          ),
        ],
      ),
      initiallyExpanded: markerIdx == _selectedMarker,
      elevation: 4,
      children: [
        Row(
          children: [
            Checkbox(
              value: marker.isZoned,
              onChanged: (zoned) {
                _addMarkerChange(
                  markerIdx,
                  (updated) => updated.endWaypointRelativePos =
                      (zoned ?? false) ? updated.waypointRelativePos : null,
                );
              },
            ),
            const SizedBox(width: 4),
            const Text('Zoned Event', style: TextStyle(fontSize: 15)),
          ],
        ),
        _buildStartPositionEditor(markerIdx),
        if (marker.isZoned) ...[
          const SizedBox(height: 8),
          _buildEndPositionEditor(markerIdx),
          const SizedBox(height: 12),
        ],
        const Divider(),
        if (marker.command != null) _buildCommandCard(markerIdx),
        if (marker.command == null)
          Center(
            child: AddCommandButton(
              allowPathCommand: false,
              allowWaitCommand: false,
              onTypeChosen: (type) => _replaceCommand(
                markerIdx,
                Command.fromType(type),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEventNameDropdown(int markerIdx) {
    final colorScheme = Theme.of(context).colorScheme;
    final marker = markers[markerIdx];
    final eventNames = ProjectEventRegistry.events
        .where((event) => event.isNotEmpty)
        .toList()
      ..sort();

    return DropdownButtonHideUnderline(
      child: DropdownButton2<String>(
        hint: const Text('Event Name'),
        value: marker.name.isEmpty ? null : marker.name,
        items: eventNames.isEmpty
            ? const [
                DropdownMenuItem<String>(
                  value: '',
                  enabled: false,
                  child: Text(''),
                ),
              ]
            : [
                for (final event in eventNames)
                  DropdownMenuItem<String>(
                    value: event,
                    child: Text(
                      event,
                      style: TextStyle(
                        fontWeight: FontWeight.normal,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
              ],
        buttonStyleData: ButtonStyleData(
          padding: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.onSurface),
          ),
          height: 42,
        ),
        dropdownStyleData: DropdownStyleData(
          maxHeight: 300,
          isOverButton: true,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        ),
        menuItemStyleData: const MenuItemStyleData(),
        dropdownSearchData: DropdownSearchData(
          searchController: _searchController,
          searchInnerWidgetHeight: 42,
          searchInnerWidget: Container(
            height: 46,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: TextFormField(
              focusNode: _searchFocusNode,
              autofocus: true,
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                hintText: 'Search or add new...',
                hintStyle: const TextStyle(fontSize: 14),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onFieldSubmitted: (value) {
                Navigator.of(context).pop();
                final name = value.trim();
                if (name.isEmpty) return;
                ProjectEventRegistry.events.add(name);
                _addMarkerChange(
                  markerIdx,
                  (updated) => updated.name = name,
                  simulate: false,
                );
              },
            ),
          ),
          searchMatchFn: (item, searchValue) => item.value
              .toString()
              .toLowerCase()
              .startsWith(searchValue.toLowerCase()),
        ),
        onMenuStateChange: (isOpen) {
          if (!isOpen) {
            _searchController.clear();
          } else {
            Future<void>.delayed(const Duration(milliseconds: 50), () {
              if (mounted) _searchFocusNode.requestFocus();
            });
          }
        },
        onChanged: (value) {
          if (value == null || value.isEmpty) return;
          _addMarkerChange(
            markerIdx,
            (updated) => updated.name = value,
            simulate: false,
          );
        },
      ),
    );
  }

  Widget _buildStartPositionEditor(int markerIdx) {
    final marker = markers[markerIdx];
    final maxAllowed = marker.isZoned
        ? marker.endWaypointRelativePos!.toDouble()
        : _maxPosition;

    return Row(
      children: [
        Expanded(
          child: Slider(
            value: marker.waypointRelativePos.toDouble().clamp(0, _maxPosition),
            secondaryTrackValue: marker.endWaypointRelativePos
                ?.toDouble()
                .clamp(0, _maxPosition),
            min: 0,
            max: _maxPosition,
            label: marker.waypointRelativePos.toStringAsFixed(2),
            onChangeStart: _maxPosition == 0
                ? null
                : (value) => _sliderChangeStart = value,
            onChanged: _maxPosition == 0
                ? null
                : (value) {
                    if (value <= maxAllowed) {
                      setState(() => marker.waypointRelativePos = value);
                      _notify(simulate: false);
                    }
                  },
            onChangeEnd: _maxPosition == 0
                ? null
                : (_) => _addPositionChange(
                      markerIdx,
                      _sliderChangeStart,
                      marker.waypointRelativePos,
                      endPosition: false,
                    ),
          ),
        ),
        SizedBox(
          width: 75,
          child: NumberTextField(
            initialValue: marker.waypointRelativePos,
            precision: 2,
            label: marker.isZoned ? 'Start Pos' : 'Position',
            onSubmitted: (value) {
              if (value == null) return;
              final position = MathUtil.clamp(value, 0, maxAllowed);
              _addMarkerChange(
                markerIdx,
                (updated) => updated.waypointRelativePos = position,
              );
            },
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildEndPositionEditor(int markerIdx) {
    final marker = markers[markerIdx];
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: marker.endWaypointRelativePos!
                .toDouble()
                .clamp(0, _maxPosition),
            min: 0,
            max: _maxPosition,
            label: marker.endWaypointRelativePos!.toStringAsFixed(2),
            onChangeStart: _maxPosition == 0
                ? null
                : (value) => _sliderChangeStart = value,
            onChanged: _maxPosition == 0
                ? null
                : (value) {
                    if (value >= marker.waypointRelativePos) {
                      setState(() => marker.endWaypointRelativePos = value);
                      _notify(simulate: false);
                    }
                  },
            onChangeEnd: _maxPosition == 0
                ? null
                : (_) => _addPositionChange(
                      markerIdx,
                      _sliderChangeStart,
                      marker.endWaypointRelativePos!,
                      endPosition: true,
                    ),
          ),
        ),
        SizedBox(
          width: 75,
          child: NumberTextField(
            initialValue: marker.endWaypointRelativePos!,
            precision: 2,
            label: 'End Pos',
            onSubmitted: (value) {
              if (value == null) return;
              final position = MathUtil.clamp(
                value,
                marker.waypointRelativePos,
                _maxPosition,
              );
              _addMarkerChange(
                markerIdx,
                (updated) => updated.endWaypointRelativePos = position,
              );
            },
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildCommandCard(int markerIdx) {
    final command = markers[markerIdx].command!;
    if (command is NamedCommand) {
      return Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: NamedCommandWidget(
            command: command,
            undoStack: widget.undoStack,
            onUpdated: () => _notify(simulate: false),
            onRemoved: () => _replaceCommand(markerIdx, null),
          ),
        ),
      );
    }
    if (command is CommandGroup) {
      return Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: CommandGroupWidget(
            command: command,
            undoStack: widget.undoStack,
            onUpdated: () => _notify(simulate: false),
            onRemoved: () => _replaceCommand(markerIdx, null),
            onGroupTypeChanged: (type) {
              _replaceCommand(
                markerIdx,
                Command.fromType(
                  type,
                  commands: [
                    for (final child in command.commands) child.clone()
                  ],
                ),
              );
            },
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _addMarker() {
    final before = _cloneMarkers(markers);
    final after = _cloneMarkers(markers)..add(EventMarker());
    _addMarkersListChange(before, after);
  }

  void _deleteMarker(int markerIdx) {
    final before = _cloneMarkers(markers);
    final after = _cloneMarkers(markers)..removeAt(markerIdx);
    _addMarkersListChange(before, after, clearSelection: true);
  }

  void _addMarkersListChange(
    List<EventMarker> before,
    List<EventMarker> after, {
    bool clearSelection = false,
  }) {
    widget.undoStack.add(Change<List<EventMarker>>(
      before,
      () => _replaceMarkers(after, clearSelection: clearSelection),
      (oldValue) => _replaceMarkers(oldValue, clearSelection: clearSelection),
    ));
  }

  void _replaceMarkers(
    List<EventMarker> replacement, {
    required bool clearSelection,
  }) {
    _apply(() {
      widget.path.eventMarkers = _cloneMarkers(replacement);
      if (clearSelection) _clearSelection();
    });
  }

  void _addMarkerChange(
    int markerIdx,
    ValueChanged<EventMarker> mutate, {
    bool simulate = true,
  }) {
    final before = markers[markerIdx].clone();
    final after = before.clone();
    mutate(after);
    widget.undoStack.add(Change<EventMarker>(
      before,
      () => _apply(
        () => markers[markerIdx] = after.clone(),
        simulate: simulate,
      ),
      (oldValue) => _apply(
        () => markers[markerIdx] = oldValue.clone(),
        simulate: simulate,
      ),
    ));
  }

  void _addPositionChange(
    int markerIdx,
    num before,
    num after, {
    required bool endPosition,
  }) {
    if (before == after) return;
    widget.undoStack.add(Change<num>(
      before,
      () => _apply(() {
        if (endPosition) {
          markers[markerIdx].endWaypointRelativePos = after;
        } else {
          markers[markerIdx].waypointRelativePos = after;
        }
      }),
      (oldValue) => _apply(() {
        if (endPosition) {
          markers[markerIdx].endWaypointRelativePos = oldValue;
        } else {
          markers[markerIdx].waypointRelativePos = oldValue;
        }
      }),
    ));
  }

  void _replaceCommand(int markerIdx, Command? command) {
    final before = markers[markerIdx].command?.clone();
    final after = command?.clone();
    widget.undoStack.add(Change<Command?>(
      before,
      () => _apply(
        () => markers[markerIdx].command = after?.clone(),
        simulate: false,
      ),
      (oldValue) => _apply(
        () => markers[markerIdx].command = oldValue?.clone(),
        simulate: false,
      ),
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
    _selectedMarker = null;
    widget.onMarkerHovered?.call(null);
    widget.onMarkerSelected?.call(null);
  }

  List<ExpansibleController> _newControllers() => List.generate(
        markers.length,
        (_) => ExpansibleController(),
      );

  void _syncControllers() {
    if (_controllers.length != markers.length) {
      _controllers = _newControllers();
      if (_selectedMarker != null && _selectedMarker! >= markers.length) {
        _clearSelection();
      }
    }
  }

  static List<EventMarker> _cloneMarkers(Iterable<EventMarker> markers) =>
      [for (final marker in markers) marker.clone()];
}
