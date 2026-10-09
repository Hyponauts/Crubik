import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/practice_controller.dart';
import '../../domain/solve_record.dart';
import 'practice_panel.dart';
import 'practice_formatters.dart';
import 'practice_phase_presentation.dart';

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
    final review = _SolveReviewData(solve);
    return PracticePanel(
      key: const Key('mobile-review-layout'),
      padding: const EdgeInsets.all(16),
      child: Semantics(
        key: const Key('finish-card'),
        container: true,
        liveRegion: true,
        label: review.semanticsLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SolveReviewHeader(expandTitle: true),
            const SizedBox(height: 6),
            _SolveReviewTime(
              elapsed: review.elapsed,
              fontSize: 56,
              alignment: Alignment.centerLeft,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                key: const Key('review-details-scroll'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SolveReviewMetrics(solve: solve, review: review),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _CompletedScramble(solve: solve, mobile: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _DismissSolveButton(
                onPressed: practice.continueAfterSolve,
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
      width: double.infinity,
      child: primary,
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
    final phaseLabel = PracticePhasePresentation.label(practice.phase);
    final phaseColor = PracticePhasePresentation.color(practice.phase);
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
    final aborting = PracticePhasePresentation.attemptAborts(practice);
    return FilledButton.icon(
      key: const Key('timer-toggle'),
      onPressed: practice.primaryActionEnabled ? practice.toggleTimer : null,
      style: FilledButton.styleFrom(
        backgroundColor: aborting
            ? CrubikColors.danger
            : CrubikColors.primaryAccent,
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
      icon: Icon(PracticePhasePresentation.primaryActionIcon(practice)),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(PracticePhasePresentation.primaryActionLabel(practice)),
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
        final formatted = formatPracticeDuration(
          PracticePhasePresentation.displayedTime(practice),
        );
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
        backgroundColor: CrubikColors.primaryAccent,
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
            color: CrubikColors.primaryAccent,
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
    final review = _SolveReviewData(solve);
    final metrics = _SolveReviewMetrics(
      solve: solve,
      review: review,
      dense: dense,
    );
    final header = _SolveReviewHeader(dense: dense);
    final time = _SolveReviewTime(
      elapsed: review.elapsed,
      fontSize: dense
          ? 29
          : compact
          ? 48
          : 62,
    );
    final completedScramble = _CompletedScramble(solve: solve, dense: dense);
    final dismissButton = _DismissSolveButton(
      onPressed: onContinue,
      dense: dense,
    );

    return Semantics(
      key: const Key('finish-card'),
      container: true,
      liveRegion: true,
      label: review.semanticsLabel,
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

final class _SolveReviewData {
  const _SolveReviewData._({
    required this.elapsed,
    required this.inspection,
    required this.tps,
    required this.semanticsLabel,
  });

  factory _SolveReviewData(SolveRecord solve) {
    final elapsed = solve.isTimingReliable
        ? formatPracticeDuration(solve.elapsed)
        : 'Timing unavailable';
    final inspection = solve.inspectionElapsed == null
        ? '—'
        : formatPracticeDuration(solve.inspectionElapsed!);
    final tps = solve.moveCount == 0 || solve.turnsPerSecond == null
        ? '—'
        : solve.turnsPerSecond!.toStringAsFixed(1);
    return _SolveReviewData._(
      elapsed: elapsed,
      inspection: inspection,
      tps: tps,
      semanticsLabel:
          'Solve complete. Time $elapsed. ${solve.moveCount} moves. '
          'TPS $tps. Inspection $inspection. '
          'Completed scramble ${solve.scramble}.',
    );
  }

  final String elapsed;
  final String inspection;
  final String tps;
  final String semanticsLabel;
}

class _SolveReviewHeader extends StatelessWidget {
  const _SolveReviewHeader({this.dense = false, this.expandTitle = false});

  final bool dense;
  final bool expandTitle;

  @override
  Widget build(BuildContext context) {
    final title = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        'SOLVE COMPLETE',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: CrubikColors.primaryAccent,
          fontWeight: FontWeight.w800,
          letterSpacing: dense ? 1.1 : 1.6,
          fontSize: dense ? 10 : null,
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_rounded,
          color: CrubikColors.primaryAccent,
          size: dense ? 17 : 21,
        ),
        SizedBox(width: dense ? 5 : 7),
        if (expandTitle) Expanded(child: title) else Flexible(child: title),
      ],
    );
  }
}

class _SolveReviewTime extends StatelessWidget {
  const _SolveReviewTime({
    required this.elapsed,
    required this.fontSize,
    this.alignment = Alignment.center,
  });

  final String elapsed;
  final double fontSize;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(
        elapsed,
        key: const Key('finish-time'),
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          color: CrubikColors.text,
          fontSize: fontSize,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _SolveReviewMetrics extends StatelessWidget {
  const _SolveReviewMetrics({
    required this.solve,
    required this.review,
    this.dense = false,
  });

  final SolveRecord solve;
  final _SolveReviewData review;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FinishMetric(
          label: 'MOVES',
          value: solve.moveCount.toString(),
          valueKey: const Key('finish-moves'),
          dense: dense,
        ),
        _FinishMetric(
          label: 'TPS',
          value: review.tps,
          valueKey: const Key('finish-tps'),
          dense: dense,
        ),
        _FinishMetric(
          label: 'INSPECTION',
          value: review.inspection,
          valueKey: const Key('finish-inspection'),
          dense: dense,
        ),
      ],
    );
  }
}

class _CompletedScramble extends StatelessWidget {
  const _CompletedScramble({
    required this.solve,
    this.dense = false,
    this.mobile = false,
  });

  final SolveRecord solve;
  final bool dense;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          style:
              (mobile
                      ? Theme.of(context).textTheme.bodyMedium
                      : Theme.of(context).textTheme.bodySmall)
                  ?.copyWith(
                    color: CrubikColors.text,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    fontSize: dense ? 9 : null,
                    height: mobile
                        ? 1.35
                        : dense
                        ? 1.05
                        : 1.3,
                  ),
        ),
      ],
    );
  }
}

class _DismissSolveButton extends StatelessWidget {
  const _DismissSolveButton({required this.onPressed, this.dense = false});

  final VoidCallback onPressed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: const Key('continue-after-solve'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: CrubikColors.primaryAccent,
        foregroundColor: CrubikColors.background,
        minimumSize: const Size(0, 48),
        visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
        padding: EdgeInsets.symmetric(vertical: dense ? 8 : 12),
      ),
      icon: Icon(Icons.close_rounded, size: dense ? 17 : 20),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('DISMISS')),
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
