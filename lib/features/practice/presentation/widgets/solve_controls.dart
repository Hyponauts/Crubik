import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/practice_controller.dart';
import '../../domain/solve_record.dart';
import 'practice_panel.dart';
import 'practice_formatters.dart';

bool showsPracticeAccessory(PracticeController practice) =>
    practice.pendingSolveReview != null ||
    (practice.inputMode == PracticeInputMode.demo &&
        practice.phase == PracticePhase.manualReady);

class PracticeAccessoryPanel extends StatelessWidget {
  const PracticeAccessoryPanel({
    required this.practice,
    this.contained = false,
    this.compact = false,
    this.dense = false,
    super.key,
  });

  final PracticeController practice;
  final bool contained;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final review = practice.pendingSolveReview;
    final Widget content = review != null
        ? _FinishCardContent(
            onContinue: practice.continueAfterSolve,
            solve: review,
            compact: compact,
            dense: dense,
          )
        : _ReadyActionContent(
            onStart: practice.toggleTimer,
            compact: compact,
            dense: dense,
          );

    if (!contained) return content;
    return PracticePanel(
      padding: EdgeInsets.all(dense ? 9 : 12),
      child: content,
    );
  }
}

class PracticeMobileReviewPanel extends StatelessWidget {
  const PracticeMobileReviewPanel({required this.practice, super.key});

  final PracticeController practice;

  @override
  Widget build(BuildContext context) {
    final solve = practice.pendingSolveReview!;
    final elapsed = formatPracticeDuration(solve.elapsed);
    final inspection = solve.inspectionElapsed == null
        ? '—'
        : formatPracticeDuration(solve.inspectionElapsed!);
    final tps = solve.moveCount == 0 ? null : solve.turnsPerSecond;
    final tpsText = tps == null ? '—' : tps.toStringAsFixed(1);
    return PracticePanel(
      key: const Key('mobile-review-layout'),
      padding: const EdgeInsets.all(16),
      child: Semantics(
        key: const Key('finish-card'),
        container: true,
        liveRegion: true,
        label:
            'Solve complete. Time $elapsed. ${solve.moveCount} moves. '
            'TPS $tpsText. Inspection $inspection. '
            'Completed scramble ${solve.scramble}.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: CrubikColors.lime,
                  size: 21,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'SOLVE COMPLETE',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: CrubikColors.lime,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                elapsed,
                key: const Key('finish-time'),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: CrubikColors.text,
                  fontSize: 56,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                key: const Key('review-details-scroll'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _FinishMetric(
                          label: 'MOVES',
                          value: solve.moveCount.toString(),
                          valueKey: const Key('finish-moves'),
                          dense: false,
                        ),
                        _FinishMetric(
                          label: 'TPS',
                          value: tpsText,
                          valueKey: const Key('finish-tps'),
                          dense: false,
                        ),
                        _FinishMetric(
                          label: 'INSPECTION',
                          value: inspection,
                          valueKey: const Key('finish-inspection'),
                          dense: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Text(
                      'COMPLETED SCRAMBLE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: CrubikColors.muted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      solve.scramble,
                      key: const Key('completed-scramble'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: CrubikColors.text,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('continue-after-solve'),
                onPressed: practice.continueAfterSolve,
                style: FilledButton.styleFrom(
                  backgroundColor: CrubikColors.lime,
                  foregroundColor: CrubikColors.background,
                  minimumSize: const Size(0, 48),
                ),
                icon: const Icon(Icons.close_rounded),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('DISMISS'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PracticeTimerPanel extends StatelessWidget {
  const PracticeTimerPanel({
    required this.practice,
    this.dense = false,
    super.key,
  });

  final PracticeController practice;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return PracticePanel(
      key: const Key('focus-timer-panel'),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 14,
        vertical: dense ? 6 : 9,
      ),
      child: _TimerStatusContent(
        practice: practice,
        fontSize: dense ? 48 : 64,
        dense: dense,
      ),
    );
  }
}

class PracticeAttemptActionBar extends StatelessWidget {
  const PracticeAttemptActionBar({
    required this.practice,
    this.dense = false,
    super.key,
  });

  final PracticeController practice;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final primary = _PrimaryActionButton(
      practice: practice,
      dense: dense,
      compact: true,
    );
    return SizedBox(
      key: const Key('focus-action-bar'),
      child: SizedBox(width: double.infinity, child: primary),
    );
  }
}

class _TimerStatusContent extends StatelessWidget {
  const _TimerStatusContent({
    required this.practice,
    required this.fontSize,
    required this.dense,
  });

  final PracticeController practice;
  final double fontSize;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final phaseLabel = _phaseLabel(practice);
    final phaseColor = _phaseColor(practice);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          phaseLabel,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: phaseColor,
            fontWeight: FontWeight.w700,
            letterSpacing: dense ? 1.2 : 1.8,
          ),
        ),
        SizedBox(height: dense ? 1 : 4),
        _ClockTimeText(
          practice: practice,
          phaseLabel: phaseLabel,
          phaseColor: phaseColor,
          fontSize: fontSize,
        ),
      ],
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.practice,
    required this.dense,
    required this.compact,
  });

  final PracticeController practice;
  final bool dense;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final aborting = _attemptAborts(practice);
    return FilledButton.icon(
      key: const Key('timer-toggle'),
      onPressed: practice.primaryActionEnabled ? practice.toggleTimer : null,
      style: FilledButton.styleFrom(
        backgroundColor: aborting ? CrubikColors.danger : CrubikColors.lime,
        foregroundColor: CrubikColors.background,
        minimumSize: const Size(0, 48),
        padding: EdgeInsets.symmetric(
          vertical: dense
              ? 10
              : compact
              ? 12
              : 16,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(_primaryActionIcon(practice)),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(_primaryActionLabel(practice)),
      ),
    );
  }
}

class _ClockTimeText extends StatelessWidget {
  const _ClockTimeText({
    required this.practice,
    required this.phaseLabel,
    required this.phaseColor,
    required this.fontSize,
  });

  final PracticeController practice;
  final String phaseLabel;
  final Color phaseColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: practice.clockTicks,
      builder: (context, _) {
        final formatted = formatPracticeDuration(_displayedTime(practice));
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatted,
            key: const Key('timer-display'),
            semanticsLabel: '$phaseLabel $formatted',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              fontSize: fontSize,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: phaseColor,
            ),
          ),
        );
      },
    );
  }
}

class _ReadyActionContent extends StatelessWidget {
  const _ReadyActionContent({
    required this.onStart,
    required this.compact,
    required this.dense,
  });

  final VoidCallback onStart;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      key: const Key('timer-toggle'),
      onPressed: onStart,
      style: FilledButton.styleFrom(
        backgroundColor: CrubikColors.lime,
        foregroundColor: CrubikColors.background,
        padding: EdgeInsets.symmetric(vertical: dense ? 10 : 14),
      ),
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('START SOLVE'),
    );
    final status = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: dense
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          'READY',
          key: const Key('ready-action-label'),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: CrubikColors.lime,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
          ),
        ),
        if (!dense) ...[
          const SizedBox(height: 5),
          Text(
            'Start whenever you are ready.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CrubikColors.muted),
          ),
        ],
      ],
    );

    return Semantics(
      label: 'Ready. Start solve. Spacebar also starts timing.',
      child: dense
          ? Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 8),
                Flexible(child: button),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                status,
                SizedBox(height: compact ? 9 : 16),
                SizedBox(width: double.infinity, child: button),
                const SizedBox(height: 8),
                Text(
                  'Spacebar also starts timing',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: CrubikColors.muted),
                ),
              ],
            ),
    );
  }
}

class _FinishCardContent extends StatelessWidget {
  const _FinishCardContent({
    required this.solve,
    required this.onContinue,
    required this.compact,
    required this.dense,
  });

  final SolveRecord solve;
  final VoidCallback onContinue;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final elapsed = formatPracticeDuration(solve.elapsed);
    final inspection = solve.inspectionElapsed == null
        ? '—'
        : formatPracticeDuration(solve.inspectionElapsed!);
    final tps = solve.moveCount == 0 ? null : solve.turnsPerSecond;
    final tpsText = tps == null ? '—' : tps.toStringAsFixed(1);
    final metrics = Row(
      children: [
        _FinishMetric(
          label: 'MOVES',
          value: solve.moveCount.toString(),
          valueKey: const Key('finish-moves'),
          dense: dense,
        ),
        _FinishMetric(
          label: 'TPS',
          value: tpsText,
          valueKey: const Key('finish-tps'),
          dense: dense,
        ),
        _FinishMetric(
          label: 'INSPECTION',
          value: inspection,
          valueKey: const Key('finish-inspection'),
          dense: dense,
        ),
      ],
    );
    final header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_rounded,
          color: CrubikColors.lime,
          size: dense ? 17 : 21,
        ),
        SizedBox(width: dense ? 5 : 7),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'SOLVE COMPLETE',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: CrubikColors.lime,
                fontWeight: FontWeight.w800,
                letterSpacing: dense ? 1.1 : 1.6,
                fontSize: dense ? 10 : null,
              ),
            ),
          ),
        ),
      ],
    );
    final time = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        elapsed,
        key: const Key('finish-time'),
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          color: CrubikColors.text,
          fontSize: dense
              ? 29
              : compact
              ? 48
              : 62,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    final completedScramble = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'COMPLETED SCRAMBLE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: CrubikColors.muted,
            fontWeight: FontWeight.w700,
            letterSpacing: dense ? 0.8 : 1.1,
            fontSize: dense ? 8 : null,
          ),
        ),
        SizedBox(height: dense ? 1 : 4),
        Text(
          solve.scramble,
          key: const Key('completed-scramble'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: CrubikColors.text,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
            fontSize: dense ? 9 : null,
            height: dense ? 1.05 : 1.3,
          ),
        ),
      ],
    );
    final dismissButton = FilledButton.icon(
      key: const Key('continue-after-solve'),
      onPressed: onContinue,
      style: FilledButton.styleFrom(
        backgroundColor: CrubikColors.lime,
        foregroundColor: CrubikColors.background,
        minimumSize: const Size(0, 48),
        visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
        padding: EdgeInsets.symmetric(vertical: dense ? 8 : 12),
      ),
      icon: Icon(Icons.close_rounded, size: dense ? 17 : 20),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('DISMISS')),
    );

    return Semantics(
      key: const Key('finish-card'),
      container: true,
      liveRegion: true,
      label:
          'Solve complete. Time $elapsed. ${solve.moveCount} moves. '
          'TPS $tpsText. Inspection $inspection. '
          'Completed scramble ${solve.scramble}.',
      child: dense
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: header),
                    Flexible(child: time),
                  ],
                ),
                const SizedBox(height: 3),
                metrics,
                const SizedBox(height: 4),
                completedScramble,
                const SizedBox(height: 5),
                SizedBox(width: double.infinity, child: dismissButton),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                SizedBox(height: compact ? 5 : 8),
                Align(alignment: Alignment.centerLeft, child: time),
                SizedBox(height: compact ? 8 : 12),
                metrics,
                SizedBox(height: compact ? 8 : 12),
                const Divider(height: 1),
                SizedBox(height: compact ? 8 : 12),
                completedScramble,
                SizedBox(height: compact ? 9 : 14),
                SizedBox(width: double.infinity, child: dismissButton),
              ],
            ),
    );
  }
}

class _FinishMetric extends StatelessWidget {
  const _FinishMetric({
    required this.label,
    required this.value,
    required this.valueKey,
    required this.dense,
  });

  final String label;
  final String value;
  final Key valueKey;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: CrubikColors.muted,
              fontSize: dense ? 8 : null,
              letterSpacing: dense ? 0.6 : 1,
            ),
          ),
          SizedBox(height: dense ? 0 : 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              key: valueKey,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: CrubikColors.text,
                fontSize: dense ? 13 : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _phaseLabel(PracticeController practice) => switch (practice.phase) {
  PracticePhase.manualReady => 'READY',
  PracticePhase.awaitingCubeState => 'WAITING FOR CUBE',
  PracticePhase.needsSolvedCube => 'SOLVE CUBE FIRST',
  PracticePhase.scrambling => 'SCRAMBLING',
  PracticePhase.inspectionDelay => 'GET READY',
  PracticePhase.inspection => 'INSPECTION',
  PracticePhase.solving => 'SOLVING',
};

Color _phaseColor(PracticeController practice) => switch (practice.phase) {
  PracticePhase.needsSolvedCube => CrubikColors.warning,
  PracticePhase.scrambling ||
  PracticePhase.inspectionDelay ||
  PracticePhase.inspection => CrubikColors.cyan,
  PracticePhase.solving => CrubikColors.lime,
  PracticePhase.manualReady ||
  PracticePhase.awaitingCubeState => CrubikColors.muted,
};

Duration _displayedTime(PracticeController practice) =>
    switch (practice.phase) {
      PracticePhase.inspectionDelay => practice.preInspectionRemaining,
      PracticePhase.inspection => practice.inspectionRemaining,
      _ => practice.elapsed,
    };

bool _attemptAborts(PracticeController practice) =>
    practice.phase == PracticePhase.inspectionDelay ||
    practice.phase == PracticePhase.inspection ||
    (practice.smartCubeWorkflowActive &&
        practice.phase == PracticePhase.solving);

String _primaryActionLabel(PracticeController practice) {
  return switch (practice.phase) {
    PracticePhase.awaitingCubeState => 'WAITING FOR CUBE',
    PracticePhase.needsSolvedCube => 'SOLVE CUBE FIRST',
    PracticePhase.scrambling => 'FOLLOW SCRAMBLE',
    PracticePhase.inspectionDelay => 'ABORT',
    PracticePhase.inspection => 'ABORT',
    PracticePhase.solving =>
      practice.smartCubeWorkflowActive ? 'ABORT' : 'STOP & SAVE',
    PracticePhase.manualReady => 'START SOLVE',
  };
}

IconData _primaryActionIcon(PracticeController practice) {
  if (_attemptAborts(practice)) return Icons.close_rounded;
  if (!practice.smartCubeWorkflowActive &&
      practice.phase == PracticePhase.solving) {
    return Icons.stop_rounded;
  }
  if (practice.smartCubeWorkflowActive) return Icons.sync_rounded;
  return Icons.play_arrow_rounded;
}
