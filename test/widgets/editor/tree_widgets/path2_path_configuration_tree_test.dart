import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathplanner/path2/path.dart' as path2;
import 'package:pathplanner/widgets/editor/tree_widgets/path2_path_configuration_tree.dart';
import 'package:pathplanner/widgets/number_text_field.dart';
import 'package:undo/undo.dart';

void main() {
  late path2.Path path;
  late ChangeStack undoStack;
  late int changeCount;

  setUp(() {
    path = path2.Path.defaultPath(
      name: 'Path2',
      pathDir: '/paths',
      fs: MemoryFileSystem(),
    )..pathConfigurationExpanded = true;
    undoStack = ChangeStack();
    changeCount = 0;
  });

  Future<void> pumpTree(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Path2PathConfigurationTree(
            path: path,
            undoStack: undoStack,
            onPathChanged: () => changeCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    final field = find.widgetWithText(NumberTextField, label);
    expect(field, findsOneWidget);
    await tester.enterText(field, value);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  testWidgets('edits both end tolerances and supports undo', (tester) async {
    await pumpTree(tester);

    expect(find.text('End Tolerance'), findsOneWidget);
    await submit(tester, 'End Tolerance Distance (M)', '0.25');
    await submit(tester, 'End Tolerance Rotation (Deg)', '4.5');

    expect(path.endToleranceMeters, closeTo(0.25, 0.001));
    expect(path.endAngleToleranceDegrees, closeTo(4.5, 0.001));
    expect(changeCount, 2);

    undoStack.undo();
    expect(path.endToleranceMeters, closeTo(0.25, 0.001));
    expect(path.endAngleToleranceDegrees, closeTo(2, 0.001));

    undoStack.undo();
    expect(path.endToleranceMeters, closeTo(0.1, 0.001));
    expect(path.endAngleToleranceDegrees, closeTo(2, 0.001));
    expect(changeCount, 4);
  });

  testWidgets('clamps negative tolerances to zero', (tester) async {
    await pumpTree(tester);

    await submit(tester, 'End Tolerance Distance (M)', '-1');
    await submit(tester, 'End Tolerance Rotation (Deg)', '-10');

    expect(path.endToleranceMeters, 0);
    expect(path.endAngleToleranceDegrees, 0);
  });
}
