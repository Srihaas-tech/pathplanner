import 'package:flutter/material.dart';
import 'package:pathplanner/auto/pathplanner_auto.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/commands/command_group_widget.dart';
import 'package:undo/undo.dart';

/// Auto command editor for the Path2 application stack.
class Path2AutoTree extends StatelessWidget {
  final PathPlannerAuto auto;
  final List<String> allPathNames;
  final ValueChanged<String?>? onPathHovered;
  final VoidCallback? onSideSwapped;
  final VoidCallback? onAutoChanged;
  final ChangeStack undoStack;
  final ValueChanged<String?>? onEditPathPressed;

  const Path2AutoTree({
    super.key,
    required this.auto,
    required this.allPathNames,
    required this.undoStack,
    this.onPathHovered,
    this.onSideSwapped,
    this.onAutoChanged,
    this.onEditPathPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Move to Other Side',
                onPressed: onSideSwapped,
                icon: const Icon(Icons.swap_horiz),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Card(
                  elevation: 1,
                  color: colorScheme.surface,
                  surfaceTintColor: colorScheme.surfaceTint,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: CommandGroupWidget(
                      command: auto.sequence,
                      allPathNames: allPathNames,
                      onPathCommandHovered: onPathHovered,
                      onUpdated: onAutoChanged,
                      undoStack: undoStack,
                      onEditPathPressed: onEditPathPressed,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
