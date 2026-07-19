import 'package:flutter/material.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/widgets/editor/tree_widgets/tree_card_node.dart';
import 'package:pathplanner/widgets/number_text_field.dart';
import 'package:undo/undo.dart';

class Path2PathConfigurationTree extends StatelessWidget {
  final path2.Path path;
  final VoidCallback? onPathChanged;
  final ChangeStack undoStack;

  const Path2PathConfigurationTree({
    super.key,
    required this.path,
    required this.undoStack,
    this.onPathChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TreeCardNode(
      title: const Text('End Tolerance'),
      leading: const Icon(Icons.tune_rounded),
      initiallyExpanded: path.pathConfigurationExpanded,
      onExpansionChanged: (expanded) {
        if (expanded != null) {
          path.pathConfigurationExpanded = expanded;
        }
      },
      elevation: 1,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: NumberTextField(
                  key: const ValueKey('path2EndToleranceDistance'),
                  initialValue: path.endToleranceMeters,
                  label: 'End Tolerance Distance (M)',
                  minValue: 0,
                  onSubmitted: (value) {
                    if (value != null && value.isFinite) {
                      _addChange(
                        distanceMeters: value,
                        rotationDegrees: path.endAngleToleranceDegrees,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumberTextField(
                  key: const ValueKey('path2EndToleranceRotation'),
                  initialValue: path.endAngleToleranceDegrees,
                  label: 'End Tolerance Rotation (Deg)',
                  arrowKeyIncrement: 1,
                  minValue: 0,
                  onSubmitted: (value) {
                    if (value != null && value.isFinite) {
                      _addChange(
                        distanceMeters: path.endToleranceMeters,
                        rotationDegrees: value,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _addChange({
    required num distanceMeters,
    required num rotationDegrees,
  }) {
    final oldValue = _Path2EndTolerance(
      path.endToleranceMeters,
      path.endAngleToleranceDegrees,
    );

    undoStack.add(Change<_Path2EndTolerance>(
      oldValue,
      () => _applyTolerance(distanceMeters, rotationDegrees),
      (previous) => _applyTolerance(
        previous.distanceMeters,
        previous.rotationDegrees,
      ),
    ));
  }

  void _applyTolerance(num distanceMeters, num rotationDegrees) {
    path.endToleranceMeters = distanceMeters;
    path.endAngleToleranceDegrees = rotationDegrees;
    onPathChanged?.call();
  }
}

class _Path2EndTolerance {
  final num distanceMeters;
  final num rotationDegrees;

  const _Path2EndTolerance(this.distanceMeters, this.rotationDegrees);
}
