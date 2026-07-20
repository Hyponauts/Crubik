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
    final activeAttempt = isPracticeAttemptActive(practice);
    final reviewing = practice.pendingSolveReview != null;
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
                            if (reviewing)
                              PracticeAccessoryPanel(
                                practice: practice,
                                contained: true,
                              )
                            else
                              _DesktopPracticeHero(
                                practice: practice,
                                input: input,
                              ),
                            if (!activeAttempt) ...[
                              const SizedBox(height: 16),
                              PracticeScramblePanel(
                                practice: practice,
                                demoMode: input.isDemo,
                              ),
                            ],
                            if (input.isDemo && !reviewing) ...[
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        return Padding(
          padding: EdgeInsets.all(landscape ? 8 : 12),
          child: isPracticeAttemptActive(practice)
              ? landscape
                    ? _MobileAttemptLandscape(practice: practice, input: input)
                    : _MobileAttemptPortrait(practice: practice, input: input)
              : landscape
              ? _MobilePreparationLandscape(practice: practice, input: input)
              : _MobilePreparationPortrait(practice: practice, input: input),
        );
      },
    );
  }
}

class _MobilePreparationPortrait extends StatelessWidget {
  const _MobilePreparationPortrait({
    required this.practice,
    required this.input,
  });

  final PracticeController practice;
  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final reviewing = practice.pendingSolveReview != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 520 || textScale >= 1.3;
        final showReadyAction =
            !reviewing &&
            input.isDemo &&
            practice.phase == PracticePhase.manualReady;
        return Column(
          key: const Key('mobile-preparation-layout'),
          children: [
            Flexible(
              flex: compactHeight ? 3 : 4,
              child: PracticeScramblePanel(
                practice: practice,
                demoMode: input.isDemo,
                onManualMoves: reviewing
                    ? null
                    : () => showManualMovesDialog(context, practice: practice),
                compact: true,
                bounded: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: compactHeight ? 7 : 6,
              child: reviewing
                  ? PracticeMobileReviewPanel(practice: practice)
                  : _CompactCubePanel(practice: practice, input: input),
            ),
            if (showReadyAction) ...[
              const SizedBox(height: 8),
              PracticeAccessoryPanel(
                practice: practice,
                contained: true,
                compact: true,
                dense: compactHeight,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MobilePreparationLandscape extends StatelessWidget {
  const _MobilePreparationLandscape({
    required this.practice,
    required this.input,
  });

  final PracticeController practice;
  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    final reviewing = practice.pendingSolveReview != null;
    final showReadyAction =
        !reviewing &&
        input.isDemo &&
        practice.phase == PracticePhase.manualReady;
    return Row(
      key: const Key('mobile-preparation-landscape-layout'),
      children: [
        Expanded(
          flex: 5,
          child: reviewing
              ? PracticeMobileReviewPanel(practice: practice)
              : _CompactCubePanel(practice: practice, input: input),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Column(
            children: [
              Expanded(
                child: PracticeScramblePanel(
                  practice: practice,
                  demoMode: input.isDemo,
                  onManualMoves: reviewing
                      ? null
                      : () =>
                            showManualMovesDialog(context, practice: practice),
                  compact: true,
                  dense: true,
                  fillHeight: true,
                  bounded: true,
                ),
              ),
              if (showReadyAction) ...[
                const SizedBox(height: 8),
                PracticeAccessoryPanel(
                  practice: practice,
                  contained: true,
                  compact: true,
                  dense: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileAttemptPortrait extends StatelessWidget {
  const _MobileAttemptPortrait({required this.practice, required this.input});

  final PracticeController practice;
  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    final showManualMoves =
        input.isDemo && practice.phase == PracticePhase.solving;
    return Column(
      key: const Key('mobile-focus-layout'),
      children: [
        PracticeTimerPanel(practice: practice),
        const SizedBox(height: 8),
        Expanded(
          child: _CompactCubePanel(practice: practice, input: input),
        ),
        const SizedBox(height: 8),
        PracticeAttemptActionBar(
          practice: practice,
          onManualMoves: showManualMoves
              ? () => showManualMovesDialog(context, practice: practice)
              : null,
        ),
      ],
    );
  }
}

class _MobileAttemptLandscape extends StatelessWidget {
  const _MobileAttemptLandscape({required this.practice, required this.input});

  final PracticeController practice;
  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    final showManualMoves =
        input.isDemo && practice.phase == PracticePhase.solving;
    return Row(
      key: const Key('mobile-focus-landscape-layout'),
      children: [
        Expanded(
          flex: 5,
          child: _CompactCubePanel(practice: practice, input: input),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Column(
            children: [
              PracticeTimerPanel(practice: practice, dense: true),
              const Spacer(),
              PracticeAttemptActionBar(
                practice: practice,
                dense: true,
                onManualMoves: showManualMoves
                    ? () => showManualMovesDialog(context, practice: practice)
                    : null,
              ),
            ],
          ),
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
      key: const Key('cube-panel'),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maximumDimension = constraints.maxWidth;
          final availableDimension = constraints.maxHeight - 48;
          final dimension = availableDimension
              .clamp(96.0, maximumDimension)
              .toDouble();
          return Column(
            children: [
              PracticeSectionHeader(
                'LIVE CUBE',
                key: const Key('cube-stage-header'),
                labelKey: const Key('cube-stage-label'),
                trailing: _CubeConnectionStatus(
                  key: const Key('cube-connection-status'),
                  practice: practice,
                  input: input,
                ),
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
      key: const Key('cube-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PracticeSectionHeader(
            'LIVE CUBE',
            key: const Key('cube-stage-header'),
            labelKey: const Key('cube-stage-label'),
            trailing: _CubeConnectionStatus(
              key: const Key('cube-connection-status'),
              practice: practice,
              input: input,
            ),
          ),
          if (!showAccessory)
            Center(child: cube)
          else
            Row(
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
        Cube3DView(
          state: practice.cubeState,
          lastMove: practice.lastAppliedMove,
          moveRevision: practice.cubeMoveRevision,
          dimension: 280,
        ),
      ],
    );
  }
}

class _CubeConnectionStatus extends StatelessWidget {
  const _CubeConnectionStatus({
    required this.practice,
    required this.input,
    super.key,
  });

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
