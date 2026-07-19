import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:pathplanner/auto/pathplanner_auto.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/util/prefs.dart';
import 'package:pathplanner/widgets/editor/path2_painter.dart';
import 'package:pathplanner/widgets/editor/preview_seekbar.dart';
import 'package:pathplanner/widgets/editor/tree_widgets/path2_auto_tree.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undo/undo.dart';

/// Static Path2 auto editor. Simulation is intentionally disabled.
class SplitPath2AutoEditor extends StatefulWidget {
  final SharedPreferences prefs;
  final PathPlannerAuto auto;
  final List<path2.Path> autoPaths;
  final List<String> allPathNames;
  final VoidCallback? onAutoChanged;
  final FieldImage fieldImage;
  final ChangeStack undoStack;
  final ValueChanged<String?>? onEditPathPressed;

  const SplitPath2AutoEditor({
    super.key,
    required this.prefs,
    required this.auto,
    required this.autoPaths,
    required this.allPathNames,
    required this.fieldImage,
    required this.undoStack,
    this.onAutoChanged,
    this.onEditPathPressed,
  });

  @override
  State<SplitPath2AutoEditor> createState() => _SplitPath2AutoEditorState();
}

class _SplitPath2AutoEditorState extends State<SplitPath2AutoEditor>
    with SingleTickerProviderStateMixin {
  final MultiSplitViewController _controller = MultiSplitViewController();
  late final AnimationController _previewController;
  late bool _treeOnRight;
  String? _hoveredPath;

  @override
  void initState() {
    super.initState();
    _previewController = AnimationController(vsync: this, value: 0);
    _treeOnRight =
        widget.prefs.getBool(PrefsKeys.treeOnRight) ?? Defaults.treeOnRight;
    final treeWeight = widget.prefs.getDouble(PrefsKeys.editorTreeWeight) ??
        Defaults.editorTreeWeight;
    _controller.areas = [
      Area(
        weight: _treeOnRight ? 1 - treeWeight : treeWeight,
        minimalWeight: 0.4,
      ),
      Area(
        weight: _treeOnRight ? treeWeight : 1 - treeWeight,
        minimalWeight: 0.4,
      ),
    ];
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final seekbar = PreviewSeekbar(
      previewController: _previewController,
      totalPathTime: 0,
      enabled: false,
    );
    final tree = Card(
      margin: EdgeInsets.zero,
      elevation: 4,
      color: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: _treeOnRight ? const Radius.circular(12) : Radius.zero,
          topRight: _treeOnRight ? Radius.zero : const Radius.circular(12),
          bottomLeft: _treeOnRight ? const Radius.circular(12) : Radius.zero,
          bottomRight: _treeOnRight ? Radius.zero : const Radius.circular(12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Path2AutoTree(
          auto: widget.auto,
          allPathNames: widget.allPathNames,
          undoStack: widget.undoStack,
          onPathHovered: (pathName) => setState(() => _hoveredPath = pathName),
          onAutoChanged: widget.onAutoChanged,
          onEditPathPressed: widget.onEditPathPressed,
          onSideSwapped: _swapTreeSide,
        ),
      ),
    );

    return Stack(
      children: [
        Center(
          child: InteractiveViewer(
            maxScale: 10,
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Stack(
                children: [
                  widget.fieldImage.getWidget(),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: Path2Painter(
                        colorScheme: colorScheme,
                        paths: widget.autoPaths,
                        fieldImage: widget.fieldImage,
                        prefs: widget.prefs,
                        simple: true,
                        hideOtherPathsOnHover:
                            widget.prefs.getBool(PrefsKeys.hidePathsOnHover) ??
                                Defaults.hidePathsOnHover,
                        hoveredPath: _hoveredPath,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        MultiSplitViewTheme(
          data: MultiSplitViewThemeData(
            dividerPainter: DividerPainters.grooved1(
              color: colorScheme.surfaceContainerHighest,
              highlightedColor: colorScheme.primary,
            ),
          ),
          child: MultiSplitView(
            axis: Axis.horizontal,
            controller: _controller,
            onWeightChange: () {
              final newWeight = _treeOnRight
                  ? _controller.areas[1].weight
                  : _controller.areas[0].weight;
              widget.prefs.setDouble(
                PrefsKeys.editorTreeWeight,
                newWeight ?? Defaults.editorTreeWeight,
              );
            },
            children: _treeOnRight ? [seekbar, tree] : [tree, seekbar],
          ),
        ),
      ],
    );
  }

  void _swapTreeSide() {
    setState(() {
      _treeOnRight = !_treeOnRight;
      widget.prefs.setBool(PrefsKeys.treeOnRight, _treeOnRight);
      _controller.areas = _controller.areas.reversed.toList();
    });
  }
}
