import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../cube/domain/cube_model.dart';
import '../../application/practice_controller.dart';
import 'practice_formatters.dart';
import 'practice_panel.dart';
import 'practice_phase_presentation.dart';

enum ScramblePanelDensity {
  full,
  compact,
  dense;

  bool get isCompact => this != full;

  bool get isDense => this == dense;

  T layoutSize<T>({required T dense, required T compact, required T full}) =>
      switch (this) {
        ScramblePanelDensity.dense => dense,
        ScramblePanelDensity.compact => compact,
        ScramblePanelDensity.full => full,
      };
}

class PracticeScramblePanel extends StatelessWidget {
  const PracticeScramblePanel({
    required this.practice,
    this.density = ScramblePanelDensity.full,
    this.fillHeight = false,
    this.bounded = false,
    super.key,
  });

  final PracticeController practice;
  final ScramblePanelDensity density;
  final bool fillHeight;
  final bool bounded;

  @override
  Widget build(BuildContext context) {
    final canChangeScramble = practice.canChangeScramble;
    final hasScramble = practice.hasScramble;
    final displayedScramble = practice.displayedScramble;
    final preparationFailed = practice.scramblePreparationError != null;
    final preparedBody = displayedScramble != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ScrambleProgressText(
                practice: practice,
                scramble: displayedScramble,
                density: density,
              ),
              if (practice.smartCubeWorkflowActive) ...[
                SizedBox(
                  height: density.layoutSize(dense: 1, compact: 5, full: 14),
                ),
                _ScrambleGuidance(practice: practice, density: density),
              ],
              SizedBox(
                height: density.layoutSize(dense: 3, compact: 7, full: 16),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('new-scramble'),
                      onPressed: canChangeScramble
                          ? practice.newScramble
                          : null,
                      style: density.isCompact
                          ? OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            )
                          : null,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: Text(density.isCompact ? 'New' : 'New scramble'),
                    ),
                  ),
                ],
              ),
            ],
          )
        : null;
    final preparationStatus = _ScramblePreparationStatus(
      practice: practice,
      failed: preparationFailed,
    );
    final scrambleBody = preparedBody == null
        ? preparationStatus
        : _DelayedScramblePreparationOverlay(
            active: !hasScramble,
            delay: practice.isPreparingScramble,
            status: preparationStatus,
            child: preparedBody,
          );

    final content = Column(
      mainAxisAlignment: fillHeight
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PracticeSectionHeader(
          practice.pendingSolveReview == null
              ? 'PRACTICE SCRAMBLE'
              : 'NEXT PRACTICE SCRAMBLE',
        ),
        SizedBox(height: density.layoutSize(dense: 3, compact: 7, full: 14)),
        scrambleBody,
      ],
    );

    return PracticePanel(
      key: const Key('scramble-panel'),
      padding: EdgeInsets.all(
        density.layoutSize(dense: 9, compact: 12, full: 18),
      ),
      child: bounded
          ? SingleChildScrollView(
              key: const Key('scramble-content-scroll'),
              child: content,
            )
          : content,
    );
  }
}

class _DelayedScramblePreparationOverlay extends StatefulWidget {
  const _DelayedScramblePreparationOverlay({
    required this.active,
    required this.delay,
    required this.status,
    required this.child,
  });

  static const delayDuration = Duration(milliseconds: 150);

  final bool active;
  final bool delay;
  final Widget status;
  final Widget child;

  @override
  State<_DelayedScramblePreparationOverlay> createState() =>
      _DelayedScramblePreparationOverlayState();
}

class _DelayedScramblePreparationOverlayState
    extends State<_DelayedScramblePreparationOverlay> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _syncVisibility();
  }

  @override
  void didUpdateWidget(_DelayedScramblePreparationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active || widget.delay != oldWidget.delay) {
      _syncVisibility();
    }
  }

  void _syncVisibility() {
    _timer?.cancel();
    if (!widget.active) {
      _visible = false;
      return;
    }
    if (!widget.delay) {
      _visible = true;
      return;
    }
    _visible = false;
    _timer = Timer(_DelayedScramblePreparationOverlay.delayDuration, () {
      if (mounted && widget.active && widget.delay) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IgnorePointer(
          ignoring: widget.active,
          child: ExcludeSemantics(
            excluding: widget.active,
            child: _visible
                ? Opacity(opacity: 0.28, child: widget.child)
                : widget.child,
          ),
        ),
        if (_visible) Positioned.fill(child: widget.status),
      ],
    );
  }
}

class _ScramblePreparationStatus extends StatelessWidget {
  const _ScramblePreparationStatus({
    required this.practice,
    required this.failed,
  });

  final PracticeController practice;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: Key(failed ? 'scramble-error' : 'scramble-loading'),
      liveRegion: true,
      label: failed ? 'Unable to prepare a scramble.' : 'Preparing a scramble.',
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (failed)
                    const Icon(
                      Icons.error_outline_rounded,
                      color: CrubikColors.warning,
                    )
                  else
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      failed
                          ? 'Unable to prepare scramble.'
                          : 'Preparing scramble…',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              if (failed) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('retry-scramble'),
                  onPressed: practice.retryScramble,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrambleProgressText extends StatelessWidget {
  const _ScrambleProgressText({
    required this.practice,
    required this.scramble,
    required this.density,
  });

  final PracticeController practice;
  final CubeScramble scramble;
  final ScramblePanelDensity density;

  @override
  Widget build(BuildContext context) {
    final completed = practice.completedScrambleMoveCount;
    final partialTurns = practice.partialScrambleMoveTurnCount;
    final recoveryMoves = practice.scrambleRecoveryMoves;
    final correction =
        practice.guidanceIsCorrection && recoveryMoves.isNotEmpty;
    final showNext = practice.phase == PracticePhase.scrambling && !correction;
    final moves = scramble.moves;
    final recoveryNotation = recoveryMoves
        .map((move) => move.notation)
        .join(' ');
    final recoveryDescription = correction
        ? '${recoveryMoves.length} recovery '
              '${recoveryMoves.length == 1 ? 'move' : 'moves'} inserted: '
              '$recoveryNotation. '
        : '';

    return Semantics(
      label:
          'Scramble. $completed of ${moves.length} moves completed. '
          '${partialTurns > 0 ? 'The next move is partially completed. ' : ''}'
          '$recoveryDescription'
          '$scramble',
      child: Wrap(
        key: const Key('scramble-text'),
        spacing: density.layoutSize(dense: 2, compact: 3, full: 5),
        runSpacing: density.layoutSize(dense: 2, compact: 3, full: 5),
        children: [
          for (var index = 0; index < completed; index++)
            _ScrambleMoveToken(
              move: moves[index],
              index: index,
              completed: true,
              next: false,
              partialTurns: 0,
              recovery: false,
              density: density,
            ),
          for (var index = 0; index < recoveryMoves.length; index++)
            _ScrambleMoveToken(
              move: recoveryMoves[index],
              index: index,
              completed: false,
              next: index == 0,
              partialTurns: 0,
              recovery: true,
              density: density,
            ),
          for (var index = completed; index < moves.length; index++)
            _ScrambleMoveToken(
              move: moves[index],
              index: index,
              completed: false,
              next: showNext && index == completed,
              partialTurns: index == completed ? partialTurns : 0,
              recovery: false,
              density: density,
            ),
        ],
      ),
    );
  }
}

class _ScrambleMoveToken extends StatelessWidget {
  const _ScrambleMoveToken({
    required this.move,
    required this.index,
    required this.completed,
    required this.next,
    required this.partialTurns,
    required this.recovery,
    required this.density,
  });

  final CubeMove move;
  final int index;
  final bool completed;
  final bool next;
  final int partialTurns;
  final bool recovery;
  final ScramblePanelDensity density;

  @override
  Widget build(BuildContext context) {
    final partiallyCompleted = partialTurns > 0 && !completed;
    final partialFraction = partiallyCompleted
        ? partialTurns / move.turns
        : 0.0;
    final color = recovery
        ? CrubikColors.warning
        : completed || partiallyCompleted
        ? CrubikColors.primaryAccent
        : next
        ? CrubikColors.secondaryAccent
        : CrubikColors.text;
    return Semantics(
      label:
          '${move.notation}, '
          '${recovery
              ? next
                    ? 'next recovery move'
                    : 'recovery move'
              : completed
              ? 'completed'
              : partiallyCompleted
              ? 'partially completed, $partialTurns of ${move.turns} turns'
              : next
              ? 'next move'
              : 'not completed'}',
      child: KeyedSubtree(
        key: recovery ? Key('scramble-recovery-step-$index') : null,
        child: Container(
          key: next
              ? const Key('next-scramble-move')
              : recovery
              ? null
              : Key('scramble-step-$index'),
          padding: EdgeInsets.symmetric(
            horizontal: density.layoutSize(dense: 2, compact: 3, full: 5),
            vertical: density.layoutSize(dense: 1, compact: 2, full: 3),
          ),
          decoration: BoxDecoration(
            color: recovery
                ? CrubikColors.warning.withValues(alpha: next ? 0.22 : 0.12)
                : completed
                ? CrubikColors.primaryAccent.withValues(alpha: 0.14)
                : null,
            gradient: recovery
                ? null
                : partiallyCompleted
                ? LinearGradient(
                    colors: [
                      CrubikColors.primaryAccent.withValues(alpha: 0.24),
                      CrubikColors.primaryAccent.withValues(alpha: 0.24),
                      CrubikColors.secondaryAccent.withValues(alpha: 0.10),
                      CrubikColors.secondaryAccent.withValues(alpha: 0.10),
                    ],
                    stops: [0, partialFraction, partialFraction, 1],
                  )
                : next
                ? LinearGradient(
                    colors: [
                      CrubikColors.secondaryAccent.withValues(alpha: 0.10),
                      CrubikColors.secondaryAccent.withValues(alpha: 0.10),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(5),
            // Container adds border widths to its padding; reserve the same
            // inset in every state to keep baselines and wrapping unchanged.
            border: Border.all(
              width: 1.5,
              color: recovery
                  ? CrubikColors.warning.withValues(alpha: next ? 0.95 : 0.55)
                  : partiallyCompleted
                  ? CrubikColors.primaryAccent.withValues(alpha: 0.8)
                  : next
                  ? CrubikColors.secondaryAccent.withValues(alpha: 0.7)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            move.notation,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: density.layoutSize(dense: 15, compact: 18, full: 20),
              fontWeight: FontWeight.w800,
              decoration: completed ? TextDecoration.lineThrough : null,
              decorationColor: CrubikColors.primaryAccent,
              decorationThickness: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrambleGuidance extends StatelessWidget {
  const _ScrambleGuidance({required this.practice, required this.density});

  final PracticeController practice;
  final ScramblePanelDensity density;

  @override
  Widget build(BuildContext context) {
    final nextMove = practice.nextScrambleMove;
    final partialTurns = practice.partialScrambleMoveTurnCount;
    final recoveryMoves = practice.scrambleRecoveryMoves;
    final correction =
        practice.guidanceIsCorrection &&
        nextMove != null &&
        recoveryMoves.isNotEmpty;
    final color = correction
        ? CrubikColors.warning
        : PracticePhasePresentation.color(practice.phase);
    final status = switch (practice.phase) {
      PracticePhase.awaitingCubeState => 'Waiting for the physical cube state',
      PracticePhase.needsSolvedCube =>
        'Solve the physical cube before scrambling',
      PracticePhase.scrambling when correction =>
        'Wrong turn detected · ${recoveryMoves.length} recovery '
            '${recoveryMoves.length == 1 ? 'move' : 'moves'} needed',
      PracticePhase.scrambling when partialTurns > 0 =>
        '${practice.completedScrambleMoveCount} complete · current step '
            '$partialTurns of ${practice.scramble.moves[practice.completedScrambleMoveCount].turns} turns',
      PracticePhase.scrambling =>
        '${practice.completedScrambleMoveCount} of '
            '${practice.scramble.moves.length} moves complete',
      PracticePhase.inspectionDelay =>
        'Scramble verified · inspection starts in '
            '${formatPracticeDelay(practice.preInspectionDelay)}',
      PracticePhase.inspection => 'Scramble verified · inspection started',
      PracticePhase.solving => 'Scramble verified · solve in progress',
      PracticePhase.manualReady => 'Ready',
    };
    final recoveryNotation = recoveryMoves
        .map((move) => move.notation)
        .join(' ');

    return Semantics(
      liveRegion: true,
      label: correction
          ? '$status. Recovery sequence: $recoveryNotation. '
                'Next recovery move: ${nextMove.notation}.'
          : status,
      child: Container(
        key: const Key('scramble-guidance'),
        width: double.infinity,
        padding: density.isDense
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
            : EdgeInsets.all(
                density.layoutSize(dense: 2, compact: 7, full: 11),
              ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            if (!density.isDense) ...[
              Icon(
                correction
                    ? Icons.warning_amber_rounded
                    : practice.phase == PracticePhase.needsSolvedCube
                    ? Icons.restart_alt_rounded
                    : Icons.route_rounded,
                size: density.layoutSize(dense: 15, compact: 15, full: 18),
                color: color,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                status,
                key: const Key('scramble-guidance-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: density.isDense ? 10 : null,
                  height: density.isDense ? 1 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
