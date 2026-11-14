import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../cube/application/cube_connection_controller.dart';
import '../application/practice_controller.dart';
import 'widgets/cube_3d_view.dart';
import 'widgets/manual_move_input.dart';
import 'widgets/practice_brand.dart';
import 'widgets/practice_connection.dart';
import 'widgets/practice_panel.dart';
import 'widgets/scramble_panel.dart';
import 'widgets/session_settings.dart';
import 'widgets/session_summary_panel.dart';
import 'widgets/solve_controls.dart';

/// Arranges practice content and session history for desktop viewports.
class DesktopPracticeLayout extends StatelessWidget {
  const DesktopPracticeLayout({
    required this.practice,
    required this.connection,
    required this.onConnectPressed,
    super.key,
  });

  final PracticeController practice;
  final CubeConnectionController connection;
  final VoidCallback onConnectPressed;

  @override
  Widget build(BuildContext context) {
    final activeAttempt = practice.attemptInProgress;
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
                connection: connection,
                onPressed: onConnectPressed,
              ),
              const SizedBox(width: 8),
              PracticeSessionButton(practice: practice),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: activeAttempt
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final width = math.min(
                        constraints.maxWidth,
                        CrubikLayout.desktopAttemptMaxWidth,
                      );
                      final height = math.min(
                        constraints.maxHeight,
                        CrubikLayout.desktopAttemptMaxHeight,
                      );
                      return Center(
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: _PracticeAttemptStage(
                            practice: practice,
                            connection: connection,
                            axis: Axis.horizontal,
                          ),
                        ),
                      );
                    },
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxHeight < 520;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: math.min(constraints.maxWidth * 0.43, 480),
                            child: Column(
                              children: [
                                Flexible(
                                  child: PracticeScramblePanel(
                                    practice: practice,
                                    density: compact
                                        ? ScramblePanelDensity.compact
                                        : ScramblePanelDensity.full,
                                    bounded: true,
                                  ),
                                ),
                                SizedBox(height: compact ? 8 : 12),
                                SessionSummaryPanel(practice: practice),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: reviewing
                                ? PracticeAccessoryPanel(
                                    practice: practice,
                                    contained: true,
                                  )
                                : _DesktopPracticeHero(
                                    practice: practice,
                                    connection: connection,
                                  ),
                          ),
                        ],
                      );
                    },
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
    required this.connection,
    super.key,
  });

  final PracticeController practice;
  final CubeConnectionController connection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final activeAttempt = practice.attemptInProgress;
        return Padding(
          padding: EdgeInsets.all(landscape ? 8 : 12),
          child: activeAttempt
              ? _PracticeAttemptStage(
                  key: Key(
                    landscape
                        ? 'mobile-focus-landscape-layout'
                        : 'mobile-focus-layout',
                  ),
                  practice: practice,
                  connection: connection,
                  axis: landscape ? Axis.horizontal : Axis.vertical,
                )
              : landscape
              ? _MobilePreparationLandscape(
                  practice: practice,
                  connection: connection,
                )
              : _MobilePreparationPortrait(
                  practice: practice,
                  connection: connection,
                ),
        );
      },
    );
  }
}

class _MobilePreparationPortrait extends StatelessWidget {
  const _MobilePreparationPortrait({
    required this.practice,
    required this.connection,
  });

  final PracticeController practice;
  final CubeConnectionController connection;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final reviewing = practice.pendingSolveReview != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight =
            constraints.maxHeight < CrubikLayout.compactPreparationHeight ||
            textScale >= CrubikLayout.largeTextScale;
        final scrambleHeightFraction = textScale >= 2
            ? 0.26
            : compactHeight
            ? 0.34
            : 0.42;
        final showReadyAction =
            !reviewing &&
            practice.inputMode == PracticeInputMode.demo &&
            practice.phase == PracticePhase.manualReady;
        return Column(
          key: const Key('mobile-preparation-layout'),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * scrambleHeightFraction,
              ),
              child: PracticeScramblePanel(
                practice: practice,
                density: ScramblePanelDensity.compact,
                bounded: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: reviewing
                  ? PracticeMobileReviewPanel(practice: practice)
                  : _CompactCubePanel(
                      practice: practice,
                      connection: connection,
                    ),
            ),
            const SizedBox(height: 8),
            SessionSummaryPanel(practice: practice),
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
    required this.connection,
  });

  final PracticeController practice;
  final CubeConnectionController connection;

  @override
  Widget build(BuildContext context) {
    final reviewing = practice.pendingSolveReview != null;
    final showSessionSummary = MediaQuery.sizeOf(context).height >= 360;
    final showReadyAction =
        !reviewing &&
        practice.inputMode == PracticeInputMode.demo &&
        practice.phase == PracticePhase.manualReady;
    return Row(
      key: const Key('mobile-preparation-landscape-layout'),
      children: [
        Expanded(
          flex: 6,
          child: Column(
            children: [
              Expanded(
                child: PracticeScramblePanel(
                  practice: practice,
                  density: ScramblePanelDensity.dense,
                  fillHeight: true,
                  bounded: true,
                ),
              ),
              if (showSessionSummary) ...[
                const SizedBox(height: 8),
                SessionSummaryPanel(practice: practice),
              ],
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
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: reviewing
              ? PracticeMobileReviewPanel(practice: practice)
              : _CompactCubePanel(practice: practice, connection: connection),
        ),
      ],
    );
  }
}

class _PracticeAttemptStage extends StatelessWidget {
  const _PracticeAttemptStage({
    required this.practice,
    required this.connection,
    required this.axis,
    super.key,
  });

  final PracticeController practice;
  final CubeConnectionController connection;
  final Axis axis;

  static const _minimumHorizontalWidth = 552.0;
  static const _minimumHorizontalHeight = 304.0;
  static const _scaledHorizontalHeight = 400.0;
  static const _minimumControlsWidth = 338.0;
  static const _maximumControlsWidth = 420.0;

  @override
  Widget build(BuildContext context) {
    if (practice.phase == PracticePhase.inspectionDelay) {
      return _ReadinessAttemptStage(
        practice: practice,
        dense: axis == Axis.horizontal,
      );
    }

    final showManualInput =
        practice.inputMode == PracticeInputMode.demo &&
        (practice.phase == PracticePhase.inspection ||
            practice.phase == PracticePhase.solving);
    if (axis == Axis.vertical) {
      return _buildPortrait(showManualInput);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _minimumHorizontalWidth) {
          return SingleChildScrollView(
            key: const Key('attempt-scroll-fallback'),
            child: _buildPortrait(
              showManualInput,
              cubeHeight: (constraints.maxWidth * 0.55)
                  .clamp(180.0, 240.0)
                  .toDouble(),
            ),
          );
        }

        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final minimumHeight = textScale >= CrubikLayout.largeTextScale
            ? _scaledHorizontalHeight
            : _minimumHorizontalHeight;
        if (constraints.maxHeight < minimumHeight) {
          return SingleChildScrollView(
            key: const Key('attempt-scroll-fallback'),
            child: SizedBox(
              width: constraints.maxWidth,
              height: minimumHeight,
              child: _buildHorizontal(showManualInput, constraints.maxWidth),
            ),
          );
        }
        return _buildHorizontal(showManualInput, constraints.maxWidth);
      },
    );
  }

  Widget _buildPortrait(bool showManualInput, {double? cubeHeight}) {
    final cubePanel = _CompactCubePanel(
      practice: practice,
      connection: connection,
    );
    return Column(
      children: [
        PracticeTimerPanel(practice: practice),
        const SizedBox(height: 8),
        if (cubeHeight == null)
          Expanded(child: cubePanel)
        else
          SizedBox(height: cubeHeight, child: cubePanel),
        if (showManualInput) ...[
          const SizedBox(height: 8),
          ManualMoveInputPanel(practice: practice, columns: 4),
        ],
        const SizedBox(height: 8),
        PracticeAttemptActionBar(practice: practice),
      ],
    );
  }

  Widget _buildHorizontal(bool showManualInput, double availableWidth) {
    final controlsWidth = (availableWidth * 0.48)
        .clamp(_minimumControlsWidth, _maximumControlsWidth)
        .toDouble();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _CompactCubePanel(practice: practice, connection: connection),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: controlsWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PracticeTimerPanel(practice: practice, dense: true),
              if (showManualInput) ...[
                const SizedBox(height: 8),
                ManualMoveInputPanel(practice: practice, columns: 6),
              ],
              const SizedBox(height: 8),
              PracticeAttemptActionBar(practice: practice, dense: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadinessAttemptStage extends StatelessWidget {
  const _ReadinessAttemptStage({required this.practice, required this.dense});

  final PracticeController practice;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('readiness-stage'),
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: PracticeTimerPanel(practice: practice, dense: dense),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: PracticeAttemptActionBar(practice: practice, dense: dense),
        ),
      ],
    );
  }
}

class _CompactCubePanel extends StatelessWidget {
  const _CompactCubePanel({required this.practice, required this.connection});

  final PracticeController practice;
  final CubeConnectionController connection;

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
                  connection: connection,
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
  const _DesktopPracticeHero({
    required this.practice,
    required this.connection,
  });

  final PracticeController practice;
  final CubeConnectionController connection;

  @override
  Widget build(BuildContext context) {
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
              connection: connection,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dimension = math.min(
                  280.0,
                  math.min(
                    constraints.maxHeight - 12,
                    constraints.maxWidth * (showAccessory ? 0.45 : 0.8),
                  ),
                );
                final cube = _DesktopCubeStage(
                  practice: practice,
                  dimension: dimension,
                );
                if (!showAccessory) return Center(child: cube);
                if (constraints.maxWidth < 440) {
                  return Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: _DesktopCubeStage(
                            practice: practice,
                            dimension: math.min(dimension, 170),
                          ),
                        ),
                      ),
                      PracticeAccessoryPanel(practice: practice, compact: true),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: cube),
                    Container(
                      width: 1,
                      height: math.min(280, constraints.maxHeight),
                      color: CrubikColors.border,
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: constraints.maxWidth < 620 ? 12 : 24,
                        ),
                        child: PracticeAccessoryPanel(
                          practice: practice,
                          compact: constraints.maxWidth < 620,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopCubeStage extends StatelessWidget {
  const _DesktopCubeStage({required this.practice, required this.dimension});

  final PracticeController practice;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    return Cube3DView(
      state: practice.cubeState,
      lastMove: practice.lastAppliedMove,
      moveRevision: practice.cubeMoveRevision,
      dimension: dimension,
    );
  }
}

class _CubeConnectionStatus extends StatelessWidget {
  const _CubeConnectionStatus({
    required this.practice,
    required this.connection,
    super.key,
  });

  final PracticeController practice;
  final CubeConnectionController connection;

  @override
  Widget build(BuildContext context) {
    final color = connection.isConnected
        ? CrubikColors.primaryAccent
        : practice.smartCubeWorkflowActive
        ? CrubikColors.warning
        : CrubikColors.muted;
    final label = practice.inputMode == PracticeInputMode.demo
        ? 'DEMO'
        : connection.isConnected
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
