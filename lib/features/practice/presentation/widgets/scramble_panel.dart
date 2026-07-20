import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../cube/domain/cube_model.dart';
import '../../application/practice_controller.dart';
import 'practice_panel.dart';

class PracticeScramblePanel extends StatelessWidget {
  const PracticeScramblePanel({
    required this.practice,
    this.compact = false,
    this.dense = false,
    this.fillHeight = false,
    this.bounded = false,
    super.key,
  });

  final PracticeController practice;
  final bool compact;
  final bool dense;
  final bool fillHeight;
  final bool bounded;

  @override
  Widget build(BuildContext context) {
    final canChangeScramble =
        practice.phase != PracticePhase.inspectionDelay &&
        practice.phase != PracticePhase.inspection &&
        practice.phase != PracticePhase.solving;
    final scramble = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ScrambleProgressText(
          practice: practice,
          compact: compact,
          dense: dense,
        ),
        if (practice.smartCubeWorkflowActive) ...[
          SizedBox(
            height: dense
                ? 1
                : compact
                ? 5
                : 14,
          ),
          _ScrambleGuidance(practice: practice, compact: compact, dense: dense),
        ],
      ],
    );
    final actions = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('new-scramble'),
            onPressed: canChangeScramble ? practice.newScramble : null,
            style: compact
                ? OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  )
                : null,
            icon: const Icon(Icons.shuffle_rounded, size: 18),
            label: Text(compact ? 'New' : 'New scramble'),
          ),
        ),
      ],
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
        SizedBox(
          height: dense
              ? 3
              : compact
              ? 7
              : 14,
        ),
        scramble,
        SizedBox(
          height: dense
              ? 3
              : compact
              ? 7
              : 16,
        ),
        actions,
      ],
    );

    return PracticePanel(
      key: const Key('scramble-panel'),
      padding: compact
          ? EdgeInsets.all(dense ? 9 : 12)
          : const EdgeInsets.all(18),
      child: bounded
          ? SingleChildScrollView(
              key: const Key('scramble-content-scroll'),
              child: content,
            )
          : content,
    );
  }
}

class _ScrambleProgressText extends StatelessWidget {
  const _ScrambleProgressText({
    required this.practice,
    required this.compact,
    required this.dense,
  });

  final PracticeController practice;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final completed = practice.completedScrambleMoveCount;
    final partialTurns = practice.partialScrambleMoveTurnCount;
    final recoveryMoves = practice.scrambleRecoveryMoves;
    final correction =
        practice.guidanceIsCorrection && recoveryMoves.isNotEmpty;
    final showNext = practice.phase == PracticePhase.scrambling && !correction;
    final moves = practice.scramble.moves;
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
          '${practice.scramble}',
      child: Wrap(
        key: const Key('scramble-text'),
        spacing: dense
            ? 2
            : compact
            ? 3
            : 5,
        runSpacing: dense
            ? 2
            : compact
            ? 3
            : 5,
        children: [
          for (var index = 0; index < completed; index++)
            _ScrambleMoveToken(
              move: moves[index],
              index: index,
              completed: true,
              next: false,
              partialTurns: 0,
              recovery: false,
              compact: compact,
              dense: dense,
            ),
          for (var index = 0; index < recoveryMoves.length; index++)
            _ScrambleMoveToken(
              move: recoveryMoves[index],
              index: index,
              completed: false,
              next: index == 0,
              partialTurns: 0,
              recovery: true,
              compact: compact,
              dense: dense,
            ),
          for (var index = completed; index < moves.length; index++)
            _ScrambleMoveToken(
              move: moves[index],
              index: index,
              completed: false,
              next: showNext && index == completed,
              partialTurns: index == completed ? partialTurns : 0,
              recovery: false,
              compact: compact,
              dense: dense,
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
    required this.compact,
    required this.dense,
  });

  final CubeMove move;
  final int index;
  final bool completed;
  final bool next;
  final int partialTurns;
  final bool recovery;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final partiallyCompleted = partialTurns > 0 && !completed;
    final partialFraction = partiallyCompleted
        ? partialTurns / move.turns
        : 0.0;
    final color = recovery
        ? CrubikColors.warning
        : completed || partiallyCompleted
        ? CrubikColors.lime
        : next
        ? CrubikColors.cyan
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
            horizontal: dense
                ? 2
                : compact
                ? 3
                : 5,
            vertical: dense
                ? 1
                : compact
                ? 2
                : 3,
          ),
          decoration: BoxDecoration(
            color: recovery
                ? CrubikColors.warning.withValues(alpha: next ? 0.22 : 0.12)
                : completed
                ? CrubikColors.lime.withValues(alpha: 0.14)
                : null,
            gradient: recovery
                ? null
                : partiallyCompleted
                ? LinearGradient(
                    colors: [
                      CrubikColors.lime.withValues(alpha: 0.24),
                      CrubikColors.lime.withValues(alpha: 0.24),
                      CrubikColors.cyan.withValues(alpha: 0.10),
                      CrubikColors.cyan.withValues(alpha: 0.10),
                    ],
                    stops: [0, partialFraction, partialFraction, 1],
                  )
                : next
                ? LinearGradient(
                    colors: [
                      CrubikColors.cyan.withValues(alpha: 0.10),
                      CrubikColors.cyan.withValues(alpha: 0.10),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(5),
            border: recovery
                ? Border.all(
                    color: CrubikColors.warning.withValues(
                      alpha: next ? 0.95 : 0.55,
                    ),
                    width: next ? 1.5 : 1,
                  )
                : partiallyCompleted
                ? Border.all(color: CrubikColors.lime.withValues(alpha: 0.8))
                : next
                ? Border.all(color: CrubikColors.cyan.withValues(alpha: 0.7))
                : null,
          ),
          child: Text(
            move.notation,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: dense
                  ? 15
                  : compact
                  ? 18
                  : 20,
              fontWeight: recovery
                  ? next
                        ? FontWeight.w900
                        : FontWeight.w800
                  : completed || next
                  ? FontWeight.w800
                  : FontWeight.w600,
              decoration: completed ? TextDecoration.lineThrough : null,
              decorationColor: CrubikColors.lime,
              decorationThickness: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrambleGuidance extends StatelessWidget {
  const _ScrambleGuidance({
    required this.practice,
    required this.compact,
    required this.dense,
  });

  final PracticeController practice;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final nextMove = practice.nextScrambleMove;
    final partialTurns = practice.partialScrambleMoveTurnCount;
    final recoveryMoves = practice.scrambleRecoveryMoves;
    final correction =
        practice.guidanceIsCorrection &&
        nextMove != null &&
        recoveryMoves.isNotEmpty;
    final color = correction ? CrubikColors.warning : _phaseColor(practice);
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
        'Scramble verified · inspection starts in 3 seconds',
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
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
            : EdgeInsets.all(compact ? 7 : 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            if (!dense) ...[
              Icon(
                correction
                    ? Icons.warning_amber_rounded
                    : practice.phase == PracticePhase.needsSolvedCube
                    ? Icons.restart_alt_rounded
                    : Icons.route_rounded,
                size: compact ? 15 : 18,
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
                  fontSize: dense ? 10 : null,
                  height: dense ? 1 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _phaseColor(PracticeController practice) => switch (practice.phase) {
  PracticePhase.needsSolvedCube => CrubikColors.warning,
  PracticePhase.scrambling ||
  PracticePhase.inspectionDelay ||
  PracticePhase.inspection => CrubikColors.cyan,
  PracticePhase.solving => CrubikColors.lime,
  PracticePhase.manualReady ||
  PracticePhase.awaitingCubeState => CrubikColors.muted,
};
