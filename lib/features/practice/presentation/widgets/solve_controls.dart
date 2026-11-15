import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/practice_controller.dart';
import 'practice_panel.dart';
import 'practice_formatters.dart';
import 'practice_phase_presentation.dart';
import 'solve_analysis_panel.dart';

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
    if (review != null) {
      return KeyedSubtree(
        key: const Key('finish-card'),
        child: SolveAnalysisPanel(
          practice: practice,
          solve: review,
          onContinue: practice.continueAfterSolve,
        ),
      );
    }
    final content = _ReadyActionContent(
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
    return KeyedSubtree(
      key: const Key('finish-card'),
      child: SolveAnalysisPanel(
        key: const Key('mobile-review-layout'),
        practice: practice,
        solve: solve,
        onContinue: practice.continueAfterSolve,
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
