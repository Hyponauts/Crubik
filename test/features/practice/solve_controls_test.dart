import 'dart:convert';
import 'dart:io';

import 'package:crubik/core/data/crubik_database.dart';
import 'package:crubik/core/theme/app_theme.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:crubik/features/practice/domain/solve_method.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:crubik/features/practice/domain/solve_recording.dart';
import 'package:crubik/features/practice/presentation/widgets/solve_controls.dart';
import 'package:crubik/features/practice/presentation/widgets/solve_analysis_panel.dart';
import 'package:crubik/features/practice/presentation/sessions_view.dart';
import 'package:crubik/features/practice/presentation/solve_export_file_io.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/practice_controller_factory.dart';
import '../../support/practice_test_clock.dart';

void main() {
  testWidgets('renders ready and finish states in isolation', (tester) async {
    final clock = PracticeTestClock();
    final practice = createTestPracticeController(
      clock: clock,
      preInspectionDelay: Duration.zero,
      monotonicClock: clock,
    )..activateDemoInput();
    addTearDown(practice.dispose);

    await tester.pumpWidget(_host(practice));
    expect(find.byKey(const Key('ready-action-label')), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    practice.applyMove(CubeMove.parse('R'));
    clock.value = const Duration(milliseconds: 12006);
    practice.stopSolve();
    await tester.pump();
    expect(find.byKey(const Key('finish-card')), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    expect(find.byKey(const Key('continue-after-solve')), findsOneWidget);
    expect(find.text('DISMISS'), findsOneWidget);
    expect(find.byKey(const Key('delete-solve-button')), findsOneWidget);
    await tester.tap(find.text('STATS'));
    await tester.pumpAndSettle();
    expect(find.text('12.00S'), findsOneWidget);
    expect(find.text('12.01S'), findsNothing);

    await tester.tap(find.byKey(const Key('continue-after-solve')));
    await tester.pump();
    expect(practice.pendingSolveReview, isNull);
    expect(practice.phase, PracticePhase.manualReady);
    expect(find.byKey(const Key('ready-action-label')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the completed solve requires confirmation', (
    tester,
  ) async {
    final clock = PracticeTestClock();
    final practice = createTestPracticeController(
      clock: clock,
      preInspectionDelay: Duration.zero,
      monotonicClock: clock,
    )..activateDemoInput();
    addTearDown(practice.dispose);

    practice.startSolve();
    practice.applyMove(CubeMove.parse('R'));
    clock.value = const Duration(seconds: 12);
    practice.stopSolve();
    await tester.pumpWidget(_host(practice));

    await tester.tap(find.byKey(const Key('delete-solve-button')));
    await tester.pumpAndSettle();
    expect(find.text('Delete solve?'), findsOneWidget);
    expect(practice.solves, hasLength(1));

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(practice.solves, hasLength(1));

    await tester.tap(find.byKey(const Key('delete-solve-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-solve')));
    await tester.pumpAndSettle();

    expect(practice.solves, isEmpty);
    expect(practice.pendingSolveReview, isNull);
  });

  testWidgets('solution and steps display countable turns and full-step TPS', (
    tester,
  ) async {
    final repository = MemorySolveHistoryRepository();
    final solve = SolveRecord(
      id: 'countable-ui',
      scramble: 'B2',
      elapsed: const Duration(seconds: 2),
      moveCount: 2,
      createdAt: DateTime.utc(2026, 10, 29),
      inputSource: SolveInputSource.smartCube,
      method: SolveMethodConfig(
        preset: SolveMethodPreset.custom,
        customStages: const [SolveStageKind.lastLayerPermuted],
      ),
    );
    await repository.add(
      solve,
      recording: SolveRecording(
        protocolFamily: CubeProtocolFamily.gan,
        cubeTimestampsAvailable: false,
        orientationAvailable: false,
        events: [
          for (var index = 0; index < 2; index++)
            RecordedMove(
              sequence: index,
              hostOffset: Duration(seconds: index + 1),
              move: CubeMove.parse('B'),
              serial: index,
              recovered: false,
            ),
        ],
      ),
    );
    final practice = createTestPracticeController(repository: repository);
    addTearDown(practice.dispose);
    await practice.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: CrubikTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 500,
            child: SolveAnalysisPanel(practice: practice, solve: solve),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('finish-moves'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('finish-tps'))).data,
      '0.5',
    );

    await tester.tap(find.text('STEPS'));
    await tester.pumpAndSettle();
    final steps = find.byKey(const Key('compact-steps-table'));
    expect(
      find.descendant(of: steps, matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: steps, matching: find.text('0.5')),
      findsOneWidget,
    );

    await tester.tap(find.text('SOLUTION'));
    await tester.pumpAndSettle();
    expect(find.text('B2'), findsOneWidget);
    expect(find.text('B B'), findsNothing);
  });

  testWidgets('analysis chart is tappable and steps use a compact table', (
    tester,
  ) async {
    final clock = PracticeTestClock();
    final practice = createTestPracticeController(
      clock: clock,
      preInspectionDelay: Duration.zero,
      monotonicClock: clock,
    );
    addTearDown(practice.dispose);
    practice.activateSmartCubeInput();
    practice.syncCubeState(CubeState.solved());
    for (final move in practice.scramble.moves) {
      clock.value += const Duration(milliseconds: 100);
      practice.applyMove(move, fromSmartCube: true);
    }
    for (final move in practice.scramble.inverse.moves) {
      clock.value += const Duration(milliseconds: 100);
      practice.applyMove(move, fromSmartCube: true);
    }

    await tester.pumpWidget(_host(practice));
    await tester.pump();
    final crossBar = find.byKey(const Key('stage-bar-cross'));
    expect(crossBar, findsOneWidget);
    final tooltip = tester.widget<Tooltip>(crossBar);
    expect(tooltip.triggerMode, TooltipTriggerMode.tap);
    expect(tooltip.message, contains('Step'));
    expect(tooltip.message, contains('Recognition Ao100'));
    expect(tooltip.message, isNot(contains('STEP')));
    expect(find.text('Recognition'), findsOneWidget);
    expect(find.text('Recognition Ao100'), findsOneWidget);
    Color legendColor(String label) {
      final row = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      final swatch = tester.widget<Container>(
        find.descendant(of: row, matching: find.byType(Container)).first,
      );
      return (swatch.decoration! as BoxDecoration).color!;
    }

    const lavender = Color(0xFFC0AAEC);
    const turquoise = Color(0xFF62C7D4);
    expect(legendColor('Recognition'), lavender);
    expect(legendColor('Execution'), turquoise);
    expect(
      legendColor('Recognition Ao100'),
      HSVColor.fromColor(lavender)
          .withHue((HSVColor.fromColor(lavender).hue + 10) % 360)
          .withAlpha(0.5)
          .toColor(),
    );
    expect(legendColor('Execution Ao100').a, closeTo(0.5, 0.01));
    expect(
      find.descendant(
        of: find.byKey(const Key('overview-axis')),
        matching: find.byType(Text),
      ),
      findsAtLeast(4),
    );
    final currentBar = find.byKey(const Key('stage-current-cross'));
    final averageBar = find.byKey(const Key('stage-average-cross'));
    final currentRect = tester.getRect(currentBar);
    final averageRect = tester.getRect(averageBar);
    expect(currentRect.width, 18);
    expect(averageRect.width, 6);
    expect(averageRect.left, closeTo(currentRect.right, 0.01));
    final currentSegments = find.descendant(
      of: currentBar,
      matching: find.byType(ColoredBox),
    );
    final averageSegments = find.descendant(
      of: averageBar,
      matching: find.byType(ColoredBox),
    );
    expect(currentSegments, findsWidgets);
    expect(averageSegments, findsWidgets);
    for (final segment in currentSegments.evaluate()) {
      expect(
        tester.getSize(find.byWidget(segment.widget)).width,
        greaterThan(0),
      );
    }
    for (final segment in averageSegments.evaluate()) {
      final coloredBox = segment.widget as ColoredBox;
      expect(tester.getSize(find.byWidget(coloredBox)).width, greaterThan(0));
      expect(coloredBox.color.a, lessThan(1));
    }
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.labelStyle?.fontSize, tabs.unselectedLabelStyle?.fontSize);
    expect(tabs.labelStyle?.fontSize, 9);

    await tester.tap(find.text('STEPS'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('compact-steps-table')), findsOneWidget);
    expect(find.text('RECOG'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(tester.widget<Text>(find.text('CROSS')).style?.fontSize, 11);

    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('TPS')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tps-bar-CROSS')), findsOneWidget);
    expect(find.text('TPS Ao100'), findsOneWidget);
    final currentTps = find.byKey(const Key('tps-current-CROSS'));
    final averageTps = find.byKey(const Key('tps-average-CROSS'));
    expect(tester.getSize(currentTps).width, 18);
    expect(tester.getSize(averageTps).width, 6);
    expect(
      tester.getRect(averageTps).left,
      closeTo(tester.getRect(currentTps).right, 0.01),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('tps-axis')),
        matching: find.byType(Text),
      ),
      findsAtLeast(4),
    );

    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copy-completed-scramble')), findsOneWidget);
    expect(find.text('SESSION'), findsOneWidget);
    expect(find.text('SOLVED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'unavailable timing stays readable in compact and wide review and history',
    (tester) async {
      final clock = PracticeTestClock(wallTime: () => DateTime.utc(2026));
      final practice = createTestPracticeController(
        monotonicClock: clock,
        preInspectionDelay: Duration.zero,
      );
      addTearDown(practice.dispose);
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      practice.activateSmartCubeInput();
      practice.syncCubeState(CubeState.solved());
      for (final move in practice.scramble.moves) {
        practice.applyMove(move, fromSmartCube: true);
      }
      for (final move in practice.scramble.inverse.moves) {
        practice.applyMove(move, fromSmartCube: true, recovered: true);
      }

      for (final size in [const Size(360, 640), const Size(1440, 900)]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(_host(practice));
        expect(find.text('Timing unavailable'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            theme: CrubikTheme.dark,
            home: Scaffold(
              body: SessionsView(practice: practice, mobile: size.width < 600),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Timing unavailable'), findsOneWidget);
        await tester.tap(find.byKey(const Key('export-solves-button')));
        await tester.pumpAndSettle();
        expect(
          find.text('Session history copied as Crubik JSON'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test(
    'Android export uses the cache supplied by the picker and cleans up',
    () async {
      final database = CrubikDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = DriftSolveHistoryRepository(database);
      final recording = SolveRecording(
        protocolFamily: CubeProtocolFamily.gan,
        cubeTimestampsAvailable: false,
        orientationAvailable: false,
        events: [
          for (var index = 0; index < 60; index++)
            RecordedMove(
              sequence: index,
              hostOffset: Duration(milliseconds: index * 100),
              move: CubeMove.parse('R'),
              serial: index,
              recovered: false,
            ),
        ],
      );
      for (var index = 0; index < 77; index++) {
        await repository.add(
          SolveRecord(
            id: 'export-$index',
            scramble: 'R U',
            elapsed: const Duration(seconds: 20),
            moveCount: 60,
            createdAt: DateTime.utc(2026).add(Duration(seconds: index)),
          ),
          recording: recording,
        );
      }
      await repository.add(
        SolveRecord(
          id: 'other-session-solve',
          scramble: 'R U',
          elapsed: const Duration(seconds: 25),
          moveCount: 60,
          createdAt: DateTime.utc(2026),
          sessionId: 'other',
        ),
        recording: recording,
      );
      final practice = createTestPracticeController(repository: repository);
      addTearDown(practice.dispose);
      await practice.initialize();
      final cache = await Directory.systemTemp.createTemp('android-cache-');
      addTearDown(() => cache.delete(recursive: true));
      const exportChannel = MethodChannel('crubik/solve_export');
      String? sourcePath;
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(exportChannel, (call) async {
            calls.add(call.method);
            if (call.method == 'chooseDestination') {
              expect(cache.listSync(), isEmpty);
              practice.createSession(name: 'Another session');
              return cache.path;
            }
            if (call.method == 'writeChosen') {
              sourcePath = (call.arguments as Map)['sourcePath'] as String;
              expect(File(sourcePath!).parent.parent.path, cache.path);
              final payload =
                  jsonDecode(File(sourcePath!).readAsStringSync())
                      as Map<String, dynamic>;
              expect(payload['format'], 'crubik-solve-history');
              expect(payload['solves'], hasLength(77));
              expect(
                (payload['solves'] as List).map((solve) => solve['id']),
                isNot(contains('other-session-solve')),
              );
              expect(File(sourcePath!).lengthSync(), greaterThan(100000));
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(exportChannel, null),
      );

      expect(await saveSolveExportFile(practice), isTrue);
      expect(calls, ['chooseDestination', 'writeChosen']);
      expect(sourcePath, isNotNull);
      expect(File(sourcePath!).existsSync(), isFalse);
    },
  );

  test('cancelling Android export does not prepare a file', () async {
    final practice = createTestPracticeController();
    addTearDown(practice.dispose);
    const exportChannel = MethodChannel('crubik/solve_export');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(exportChannel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(exportChannel, null),
    );

    expect(await saveSolveExportFile(practice), isFalse);
    expect(calls, ['chooseDestination']);
  });

  test(
    'failed Android export cleans up its temporary and destination files',
    () async {
      final practice = createTestPracticeController();
      addTearDown(practice.dispose);
      final cache = await Directory.systemTemp.createTemp('android-cache-');
      addTearDown(() => cache.delete(recursive: true));
      const exportChannel = MethodChannel('crubik/solve_export');
      final calls = <String>[];
      String? sourcePath;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(exportChannel, (call) async {
        calls.add(call.method);
        if (call.method == 'chooseDestination') return cache.path;
        if (call.method == 'writeChosen') {
          sourcePath = call.arguments['sourcePath'] as String;
          throw PlatformException(code: 'export_failed');
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(exportChannel, null),
      );

      await expectLater(
        saveSolveExportFile(practice),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, ['chooseDestination', 'writeChosen', 'clearDestination']);
      expect(sourcePath, isNotNull);
      expect(File(sourcePath!).existsSync(), isFalse);
    },
  );
}

Widget _host(PracticeController practice) {
  return MaterialApp(
    theme: CrubikTheme.dark,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: AnimatedBuilder(
            animation: practice,
            builder: (context, _) => PracticeAccessoryPanel(
              practice: practice,
              contained: true,
              compact: true,
            ),
          ),
        ),
      ),
    ),
  );
}
