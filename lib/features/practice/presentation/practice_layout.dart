import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../application/practice_controller.dart';
import '../application/practice_input_controller.dart';
import 'sessions_view.dart';
import 'widgets/cube_3d_view.dart';
import 'widgets/manual_move_input.dart';
import 'widgets/practice_brand.dart';
import 'widgets/practice_connection.dart';
import 'widgets/practice_panel.dart';
import 'widgets/scramble_panel.dart';
import 'widgets/solve_controls.dart';

/// Arranges practice content and session history for desktop viewports.
class DesktopPracticeLayout extends StatelessWidget {
  const DesktopPracticeLayout({
    required this.practice,
    required this.input,
    required this.onConnectPressed,
    super.key,
  });

  final PracticeController practice;
  final PracticeInputController input;
  final VoidCallback onConnectPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: PracticeBrand()),
              PracticeConnectionButton(
                input: input,
                onPressed: onConnectPressed,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: Column(
                          children: [
                            _DesktopPracticeHero(
                              practice: practice,
                              input: input,
                            ),
                            const SizedBox(height: 16),
                            PracticeScramblePanel(
                              practice: practice,
                              demoMode: input.isDemo,
                            ),
                            if (input.isDemo) ...[
                              const SizedBox(height: 16),
                              ManualMoveInputPanel(practice: practice),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(width: 330, child: SessionSidebar(practice: practice)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Selects the portrait or landscape practice layout for mobile viewports.
class MobilePracticeLayout extends StatelessWidget {
  const MobilePracticeLayout({
    required this.practice,
    required this.input,
    super.key,
  });

  final PracticeController practice;
  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final useScrollablePortrait =
            textScale >= 1.3 ||
            (!landscape && practice.pendingSolveReview != null);
        if (useScrollablePortrait) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: _MobilePracticePortrait(
              practice: practice,
              input: input,
              scrollFallback: true,
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.all(landscape ? 8 : 12),
          child: landscape
              ? _MobilePracticeLandscape(practice: practice, input: input)
              : _MobilePracticePortrait(practice: practice, input: input),
        );
      },
    );
  }
}

class _MobilePracticePortrait extends StatelessWidget {
  const _MobilePracticePortrait({
    required this.practice,
    required this.input,
    this.scrollFallback = false,
  });

  final PracticeController practice;
  final PracticeInputController input;
  final bool scrollFallback;

  @override
  Widget build(BuildContext context) {
    final cube = _CompactCubePanel(practice: practice, input: input);
    final showFooter = showsPracticeAccessory(practice);
    return Column(
      mainAxisSize: scrollFallback ? MainAxisSize.min : MainAxisSize.max,
      children: [
        PracticeScramblePanel(
          practice: practice,
          demoMode: input.isDemo,
          onManualMoves: () =>
              showManualMovesDialog(context, practice: practice),
          compact: true,
        ),
        const SizedBox(height: 8),
        if (scrollFallback)
          SizedBox(height: 240, child: cube)
        else
          Expanded(child: cube),
        if (showFooter) ...[
          const SizedBox(height: 8),
          PracticeAccessoryPanel(
            practice: practice,
            contained: true,
            compact: true,
          ),
        ],
      ],
    );
  }
}

class _MobilePracticeLandscape extends StatelessWidget {
  const _MobilePracticeLandscape({required this.practice, required this.input});

  final PracticeController practice;
  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    final showFooter = showsPracticeAccessory(practice);
    final reviewVisible = practice.pendingSolveReview != null;
    final rightColumn = Column(
      mainAxisSize: reviewVisible ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (reviewVisible)
          PracticeScramblePanel(
            practice: practice,
            demoMode: input.isDemo,
            onManualMoves: () =>
                showManualMovesDialog(context, practice: practice),
            compact: true,
          )
        else
          Expanded(
            child: PracticeScramblePanel(
              practice: practice,
              demoMode: input.isDemo,
              onManualMoves: () =>
                  showManualMovesDialog(context, practice: practice),
              compact: true,
              dense: true,
              fillHeight: true,
            ),
          ),
        if (showFooter) ...[
          const SizedBox(height: 8),
          PracticeAccessoryPanel(
            practice: practice,
            contained: true,
            compact: true,
            dense: true,
          ),
        ],
      ],
    );
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _CompactCubePanel(practice: practice, input: input),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: reviewVisible
              ? SingleChildScrollView(child: rightColumn)
              : rightColumn,
        ),
      ],
    );
  }
}

class _CompactCubePanel extends StatelessWidget {
  const _CompactCubePanel({required this.practice, required this.input});

  final PracticeController practice;
  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    return PracticePanel(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maximumDimension = constraints.maxWidth;
          final availableDimension = constraints.maxHeight - 48;
          final dimension = availableDimension
              .clamp(96.0, maximumDimension)
              .toDouble();
          return Column(
            children: [
              Row(
                children: [
                  const PracticeSectionLabel('LIVE CUBE'),
                  const Spacer(),
                  _CubeConnectionStatus(practice: practice, input: input),
                ],
              ),
              Expanded(
                child: Center(
                  child: Cube3DView(
                    state: practice.cubeState,
                    lastMove: practice.lastAppliedMove,
                    moveRevision: practice.cubeMoveRevision,
                    dimension: dimension,
                  ),
                ),
              ),
              Text(
                '${practice.currentMoves.length} moves captured',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: CrubikColors.muted),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DesktopPracticeHero extends StatelessWidget {
  const _DesktopPracticeHero({required this.practice, required this.input});

  final PracticeController practice;
  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    final cube = _DesktopCubeStage(practice: practice, input: input);
    final showAccessory = showsPracticeAccessory(practice);
    return PracticePanel(
      padding: const EdgeInsets.all(20),
      child: !showAccessory
          ? Center(child: cube)
          : Row(
              children: [
                Expanded(child: cube),
                Container(width: 1, height: 280, color: CrubikColors.border),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: PracticeAccessoryPanel(practice: practice),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DesktopCubeStage extends StatelessWidget {
  const _DesktopCubeStage({required this.practice, required this.input});

  final PracticeController practice;
  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const PracticeSectionLabel('LIVE CUBE'),
            const Spacer(),
            _CubeConnectionStatus(practice: practice, input: input),
          ],
        ),
        Cube3DView(
          state: practice.cubeState,
          lastMove: practice.lastAppliedMove,
          moveRevision: practice.cubeMoveRevision,
          dimension: 280,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.swipe, size: 16),
            const SizedBox(width: 7),
            Text(
              '${practice.currentMoves.length} moves captured',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: CrubikColors.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _CubeConnectionStatus extends StatelessWidget {
  const _CubeConnectionStatus({required this.practice, required this.input});

  final PracticeController practice;
  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    final color = input.isPhysicalCubeConnected
        ? CrubikColors.lime
        : practice.smartCubeWorkflowActive
        ? CrubikColors.warning
        : CrubikColors.muted;
    final label = input.isDemo
        ? 'DEMO'
        : input.isPhysicalCubeConnected
        ? 'LINKED'
        : practice.smartCubeWorkflowActive
        ? 'RECONNECT'
        : 'NOT CONNECTED';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
      ],
    );
  }
}
