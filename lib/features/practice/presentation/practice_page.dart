import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../cube/domain/cube_model.dart';
import '../application/practice_controller.dart';
import '../application/practice_input_controller.dart';
import '../domain/solve_record.dart';
import 'widgets/cube_3d_view.dart';
import 'widgets/practice_connection.dart';

class PracticePage extends StatefulWidget {
  const PracticePage({
    required this.practiceController,
    required this.inputController,
    super.key,
  });

  final PracticeController practiceController;
  final PracticeInputController inputController;

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.inputController,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 900;
            return CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.space):
                    widget.practiceController.toggleTimer,
              },
              child: Focus(
                autofocus: true,
                child: isDesktop
                    ? _buildDesktop(context)
                    : _buildMobile(context),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      key: const Key('practice-desktop-layout'),
      body: SafeArea(
        child: Row(
          children: [
            _DesktopNavigation(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _selectedIndex == 0
                  ? widget.inputController.isUnselected
                        ? _InputModeChooser(
                            desktop: true,
                            input: widget.inputController,
                            onConnectPressed: _showConnectionDialog,
                            onDemoPressed: widget.inputController.useDemoCube,
                          )
                        : _DesktopPractice(
                            practice: widget.practiceController,
                            input: widget.inputController,
                            onConnectPressed: _showConnectionDialog,
                          )
                  : _SessionsView(practice: widget.practiceController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      key: const Key('practice-mobile-layout'),
      appBar: AppBar(
        titleSpacing: 16,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: _Brand(compact: true),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PracticeConnectionButton(
              input: widget.inputController,
              onPressed: _showConnectionDialog,
              compact: true,
            ),
          ),
        ],
      ),
      body: _selectedIndex == 0
          ? widget.inputController.isUnselected
                ? _InputModeChooser(
                    input: widget.inputController,
                    onConnectPressed: _showConnectionDialog,
                    onDemoPressed: widget.inputController.useDemoCube,
                  )
                : _MobilePractice(
                    practice: widget.practiceController,
                    input: widget.inputController,
                  )
          : _SessionsView(practice: widget.practiceController, mobile: true),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.timer_outlined),
            activeIcon: Icon(Icons.timer),
            label: 'Practice',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            activeIcon: Icon(Icons.insights),
            label: 'Session',
          ),
        ],
      ),
    );
  }

  Future<void> _showConnectionDialog() async {
    await showPracticeConnectionDialog(context, input: widget.inputController);
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: _BrandMark(),
          ),
          Expanded(
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.65,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.timer_outlined),
                  selectedIcon: Icon(Icons.timer),
                  label: Text('Practice'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: Text('Session'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InputModeChooser extends StatelessWidget {
  const _InputModeChooser({
    required this.input,
    required this.onConnectPressed,
    required this.onDemoPressed,
    this.desktop = false,
  });

  final PracticeInputController input;
  final VoidCallback onConnectPressed;
  final VoidCallback onDemoPressed;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compactLandscape = !desktop && size.width > size.height;
    final icon = Container(
      width: compactLandscape ? 52 : 64,
      height: compactLandscape ? 52 : 64,
      decoration: BoxDecoration(
        color: const Color(0x16B7F34A),
        borderRadius: BorderRadius.circular(compactLandscape ? 16 : 20),
      ),
      child: Icon(
        Icons.view_in_ar_rounded,
        color: CrubikColors.lime,
        size: compactLandscape ? 28 : 34,
      ),
    );
    final buttons = compactLandscape
        ? Row(
            children: [
              Expanded(child: _connectChoiceButton()),
              const SizedBox(width: 10),
              Expanded(child: _demoChoiceButton()),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: double.infinity, child: _connectChoiceButton()),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: _demoChoiceButton()),
            ],
          );
    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: compactLandscape
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          'How do you want to practice?',
          textAlign: compactLandscape ? TextAlign.left : TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        SizedBox(height: compactLandscape ? 4 : 8),
        Text(
          'Connect a supported smart cube to track turns automatically, or use the demo cube with the timer and virtual move controls.',
          textAlign: compactLandscape ? TextAlign.left : TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: CrubikColors.muted),
        ),
        SizedBox(height: compactLandscape ? 12 : 22),
        buttons,
      ],
    );
    final chooser = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compactLandscape ? 760 : 560),
      child: _Panel(
        key: const Key('input-mode-chooser'),
        padding: EdgeInsets.all(compactLandscape ? 18 : 24),
        child: compactLandscape
            ? Row(
                children: [
                  icon,
                  const SizedBox(width: 18),
                  Expanded(child: details),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [icon, const SizedBox(height: 18), details],
              ),
      ),
    );

    if (!desktop) {
      return SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: chooser,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: _Brand()),
              PracticeConnectionButton(
                input: input,
                onPressed: onConnectPressed,
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: chooser,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectChoiceButton() => FilledButton.icon(
    key: const Key('connect-smart-cube-choice'),
    onPressed: onConnectPressed,
    icon: const Icon(Icons.bluetooth_searching),
    label: const Text('Connect smart cube'),
  );

  Widget _demoChoiceButton() => OutlinedButton.icon(
    key: const Key('use-demo-cube-choice'),
    onPressed: onDemoPressed,
    icon: const Icon(Icons.science_outlined),
    label: const Text('Use demo cube'),
  );
}

class _DesktopPractice extends StatelessWidget {
  const _DesktopPractice({
    required this.practice,
    required this.input,
    required this.onConnectPressed,
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
              const Expanded(child: _Brand()),
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
                            _CubeAndTimerHero(
                              practice: practice,
                              input: input,
                              compact: false,
                            ),
                            const SizedBox(height: 16),
                            _ScramblePanel(
                              practice: practice,
                              demoMode: input.isDemo,
                            ),
                            if (input.isDemo) ...[
                              const SizedBox(height: 16),
                              _MoveInputPanel(practice: practice),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: 330,
                  child: _SessionSidebar(practice: practice),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePractice extends StatelessWidget {
  const _MobilePractice({required this.practice, required this.input});

  final PracticeController practice;
  final PracticeInputController input;

  void _showManualMoves(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _ManualMovesDialog(practice: practice),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useAccessibilityFallback = textScale > 1.3;
        if (useAccessibilityFallback) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: _MobilePracticePortrait(
              practice: practice,
              input: input,
              onManualMoves: () => _showManualMoves(context),
              scrollFallback: true,
            ),
          );
        }

        final landscape = constraints.maxWidth > constraints.maxHeight;
        return Padding(
          padding: EdgeInsets.all(landscape ? 8 : 12),
          child: landscape
              ? _MobilePracticeLandscape(
                  practice: practice,
                  input: input,
                  onManualMoves: () => _showManualMoves(context),
                )
              : _MobilePracticePortrait(
                  practice: practice,
                  input: input,
                  onManualMoves: () => _showManualMoves(context),
                ),
        );
      },
    );
  }
}

class _MobilePracticePortrait extends StatelessWidget {
  const _MobilePracticePortrait({
    required this.practice,
    required this.input,
    required this.onManualMoves,
    this.scrollFallback = false,
  });

  final PracticeController practice;
  final PracticeInputController input;
  final VoidCallback onManualMoves;
  final bool scrollFallback;

  @override
  Widget build(BuildContext context) {
    final cube = _CompactCubePanel(practice: practice, input: input);
    return Column(
      mainAxisSize: scrollFallback ? MainAxisSize.min : MainAxisSize.max,
      children: [
        _CompactScramblePanel(
          practice: practice,
          demoMode: input.isDemo,
          onManualMoves: onManualMoves,
        ),
        const SizedBox(height: 8),
        if (scrollFallback)
          SizedBox(height: 240, child: cube)
        else
          Expanded(child: cube),
        const SizedBox(height: 8),
        _CompactTimerPanel(practice: practice),
      ],
    );
  }
}

class _MobilePracticeLandscape extends StatelessWidget {
  const _MobilePracticeLandscape({
    required this.practice,
    required this.input,
    required this.onManualMoves,
  });

  final PracticeController practice;
  final PracticeInputController input;
  final VoidCallback onManualMoves;

  @override
  Widget build(BuildContext context) {
    return Row(
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
              Expanded(
                child: _CompactScramblePanel(
                  practice: practice,
                  demoMode: input.isDemo,
                  onManualMoves: onManualMoves,
                  landscape: true,
                ),
              ),
              const SizedBox(height: 8),
              _CompactTimerPanel(practice: practice, landscape: true),
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
    return _Panel(
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
                  const _SectionLabel('LIVE CUBE'),
                  const Spacer(),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: input.isPhysicalCubeConnected
                          ? CrubikColors.lime
                          : practice.smartCubeWorkflowActive
                          ? CrubikColors.warning
                          : CrubikColors.muted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    input.isDemo
                        ? 'DEMO'
                        : input.isPhysicalCubeConnected
                        ? 'LINKED'
                        : practice.smartCubeWorkflowActive
                        ? 'RECONNECT'
                        : 'NOT CONNECTED',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: input.isPhysicalCubeConnected
                          ? CrubikColors.lime
                          : practice.smartCubeWorkflowActive
                          ? CrubikColors.warning
                          : CrubikColors.muted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
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

class _CompactScramblePanel extends StatelessWidget {
  const _CompactScramblePanel({
    required this.practice,
    required this.demoMode,
    required this.onManualMoves,
    this.landscape = false,
  });

  final PracticeController practice;
  final bool demoMode;
  final VoidCallback onManualMoves;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final canChangeScramble =
        practice.phase != PracticePhase.inspectionDelay &&
        practice.phase != PracticePhase.inspection &&
        practice.phase != PracticePhase.solving;
    return _Panel(
      padding: EdgeInsets.all(landscape ? 9 : 12),
      child: Column(
        mainAxisAlignment: landscape
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('PRACTICE SCRAMBLE'),
          SizedBox(height: landscape ? 3 : 7),
          if (landscape)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _scrambleText(context),
              ),
            )
          else
            _scrambleText(context),
          SizedBox(height: landscape ? 3 : 7),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('new-scramble'),
                  onPressed: canChangeScramble ? practice.newScramble : null,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.shuffle_rounded, size: 17),
                  label: const Text('New'),
                ),
              ),
              if (demoMode) ...[
                const SizedBox(width: 6),
                IconButton.outlined(
                  key: const Key('reset-scramble'),
                  onPressed: canChangeScramble
                      ? practice.resetCubeToScramble
                      : null,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  tooltip: 'Reset virtual cube to scramble',
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  key: const Key('manual-moves-button'),
                  onPressed: onManualMoves,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.touch_app_outlined, size: 17),
                  label: const Text('Moves'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _scrambleText(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ScrambleProgressText(
          practice: practice,
          compact: true,
          dense: landscape,
        ),
        if (practice.smartCubeWorkflowActive) ...[
          SizedBox(height: landscape ? 1 : 5),
          _ScrambleGuidance(
            practice: practice,
            compact: true,
            dense: landscape,
          ),
        ],
      ],
    );
  }
}

class _CompactTimerPanel extends StatelessWidget {
  const _CompactTimerPanel({required this.practice, this.landscape = false});

  final PracticeController practice;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final phaseLabel = _phaseLabel(practice);
    final phaseColor = _phaseColor(practice);
    final aborting = _connectedAttemptActive(practice);
    final time = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        _formatDuration(_displayedTime(practice)),
        key: const Key('timer-display'),
        semanticsLabel:
            '$phaseLabel ${_formatDuration(_displayedTime(practice))}',
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          fontSize: landscape ? 42 : 50,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: phaseColor,
        ),
      ),
    );
    final button = FilledButton.icon(
      key: const Key('timer-toggle'),
      onPressed: practice.primaryActionEnabled ? practice.toggleTimer : null,
      style: FilledButton.styleFrom(
        backgroundColor: aborting ? CrubikColors.danger : CrubikColors.lime,
        foregroundColor: CrubikColors.background,
        padding: EdgeInsets.symmetric(vertical: landscape ? 10 : 12),
      ),
      icon: Icon(_primaryActionIcon(practice)),
      label: Text(_primaryActionLabel(practice)),
    );

    return _Panel(
      padding: EdgeInsets.all(landscape ? 9 : 12),
      child: landscape
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        phaseLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: phaseColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      time,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: button),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  phaseLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: phaseColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                time,
                SizedBox(width: double.infinity, child: button),
              ],
            ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[const _BrandMark(), const SizedBox(width: 12)],
        Text(
          'CRUBIK',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(letterSpacing: 2.4),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: CrubikColors.lime,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(
        Icons.view_in_ar_rounded,
        color: CrubikColors.background,
        size: 23,
      ),
    );
  }
}

class _CubeAndTimerHero extends StatelessWidget {
  const _CubeAndTimerHero({
    required this.practice,
    required this.input,
    required this.compact,
  });

  final PracticeController practice;
  final PracticeInputController input;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cube = _CubeStage(practice: practice, input: input, compact: compact);
    final timer = _TimerPanel(practice: practice, compact: compact);

    if (compact) {
      return _Panel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        child: Column(children: [cube, const Divider(height: 18), timer]),
      );
    }

    return _Panel(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(child: cube),
          Container(width: 1, height: 250, color: CrubikColors.border),
          Expanded(child: timer),
        ],
      ),
    );
  }
}

class _CubeStage extends StatelessWidget {
  const _CubeStage({
    required this.practice,
    required this.input,
    required this.compact,
  });

  final PracticeController practice;
  final PracticeInputController input;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const _SectionLabel('LIVE CUBE'),
            const Spacer(),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: input.isPhysicalCubeConnected
                    ? CrubikColors.lime
                    : practice.smartCubeWorkflowActive
                    ? CrubikColors.warning
                    : CrubikColors.muted,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              input.isDemo
                  ? 'DEMO'
                  : input.isPhysicalCubeConnected
                  ? 'LINKED'
                  : practice.smartCubeWorkflowActive
                  ? 'RECONNECT'
                  : 'NOT CONNECTED',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: input.isPhysicalCubeConnected
                    ? CrubikColors.lime
                    : practice.smartCubeWorkflowActive
                    ? CrubikColors.warning
                    : CrubikColors.muted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        Cube3DView(
          state: practice.cubeState,
          lastMove: practice.lastAppliedMove,
          moveRevision: practice.cubeMoveRevision,
          dimension: compact ? 225 : 280,
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

class _TimerPanel extends StatelessWidget {
  const _TimerPanel({required this.practice, required this.compact});

  final PracticeController practice;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final phaseLabel = _phaseLabel(practice);
    final phaseColor = _phaseColor(practice);
    final aborting = _connectedAttemptActive(practice);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            phaseLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: phaseColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatDuration(_displayedTime(practice)),
              key: const Key('timer-display'),
              semanticsLabel:
                  '$phaseLabel ${_formatDuration(_displayedTime(practice))}',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontSize: compact ? 62 : 78,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: phaseColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('timer-toggle'),
              onPressed: practice.primaryActionEnabled
                  ? practice.toggleTimer
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: aborting
                    ? CrubikColors.danger
                    : CrubikColors.lime,
                foregroundColor: CrubikColors.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(_primaryActionIcon(practice)),
              label: Text(_primaryActionLabel(practice)),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _shortcutHint(practice),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CrubikColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ScramblePanel extends StatelessWidget {
  const _ScramblePanel({required this.practice, required this.demoMode});

  final PracticeController practice;
  final bool demoMode;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('PRACTICE SCRAMBLE'),
          const SizedBox(height: 14),
          _ScrambleProgressText(practice: practice),
          if (practice.smartCubeWorkflowActive) ...[
            const SizedBox(height: 14),
            _ScrambleGuidance(practice: practice),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('new-scramble'),
                  onPressed:
                      practice.phase == PracticePhase.inspectionDelay ||
                          practice.phase == PracticePhase.inspection ||
                          practice.phase == PracticePhase.solving
                      ? null
                      : practice.newScramble,
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('New scramble'),
                ),
              ),
              if (demoMode) ...[
                const SizedBox(width: 10),
                IconButton.outlined(
                  key: const Key('reset-scramble'),
                  onPressed:
                      practice.phase == PracticePhase.inspectionDelay ||
                          practice.phase == PracticePhase.inspection ||
                          practice.phase == PracticePhase.solving
                      ? null
                      : practice.resetCubeToScramble,
                  icon: const Icon(Icons.replay_rounded),
                  tooltip: 'Reset virtual cube to scramble',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MoveInputPanel extends StatelessWidget {
  const _MoveInputPanel({required this.practice});

  final PracticeController practice;

  static const _moves = [
    'U',
    "U'",
    'R',
    "R'",
    'F',
    "F'",
    'D',
    "D'",
    'L',
    "L'",
    'B',
    "B'",
  ];

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('MANUAL MOVE INPUT'),
          const SizedBox(height: 7),
          Text(
            'Use these controls to preview live cube movement without hardware.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CrubikColors.muted),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 580
                  ? 12
                  : constraints.maxWidth < 300
                  ? 3
                  : 6;
              final spacing = 8.0;
              final buttonWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final notation in _moves)
                    SizedBox(
                      width: buttonWidth,
                      child: OutlinedButton(
                        key: Key('cube-move-$notation'),
                        onPressed: () =>
                            practice.applyMove(CubeMove.parse(notation)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: CrubikColors.text,
                          side: const BorderSide(color: CrubikColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          notation,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ManualMovesDialog extends StatelessWidget {
  const _ManualMovesDialog({required this.practice});

  final PracticeController practice;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _MoveInputPanel(practice: practice),
      ),
    );
  }
}

class _SessionSidebar extends StatelessWidget {
  const _SessionSidebar({required this.practice});

  final PracticeController practice;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('SESSION SNAPSHOT'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatValue(
                      label: 'BEST',
                      value: _formatOptionalDuration(practice.bestTime),
                      accent: CrubikColors.lime,
                    ),
                  ),
                  Expanded(
                    child: _StatValue(
                      label: 'MEAN',
                      value: _formatOptionalDuration(practice.sessionAverage),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _StatValue(
                      label: 'AO5',
                      value: _formatOptionalDuration(practice.averageOfFive),
                    ),
                  ),
                  Expanded(
                    child: _StatValue(
                      label: 'SOLVES',
                      value: practice.solves.length.toString(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: _RecentSolves(practice: practice, scrollable: true)),
      ],
    );
  }
}

class _MobileStats extends StatelessWidget {
  const _MobileStats({required this.practice});

  final PracticeController practice;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Expanded(
            child: _StatValue(
              label: 'BEST',
              value: _formatOptionalDuration(practice.bestTime),
              accent: CrubikColors.lime,
            ),
          ),
          Expanded(
            child: _StatValue(
              label: 'MEAN',
              value: _formatOptionalDuration(practice.sessionAverage),
            ),
          ),
          Expanded(
            child: _StatValue(
              label: 'AO5',
              value: _formatOptionalDuration(practice.averageOfFive),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatValue extends StatelessWidget {
  const _StatValue({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: CrubikColors.muted,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: accent ?? CrubikColors.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentSolves extends StatelessWidget {
  const _RecentSolves({required this.practice, this.scrollable = false});

  final PracticeController practice;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final solves = practice.solves;
    final list = solves.isEmpty
        ? const _EmptySolves()
        : ListView.separated(
            key: const Key('recent-solves-list'),
            padding: EdgeInsets.zero,
            itemCount: solves.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _SolveRow(
              position: practice.solves.length - index,
              solve: solves[index],
              onDelete: () => practice.deleteSolve(solves[index].id),
            ),
          );
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionLabel('RECENT SOLVES'),
              const Spacer(),
              Text(
                '${practice.solves.length} total',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (scrollable)
            Expanded(child: list)
          else if (solves.isEmpty)
            list
          else
            for (var index = 0; index < solves.length; index++) ...[
              _SolveRow(
                position: practice.solves.length - index,
                solve: solves[index],
                onDelete: () => practice.deleteSolve(solves[index].id),
              ),
              if (index != solves.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _EmptySolves extends StatelessWidget {
  const _EmptySolves();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26),
      decoration: BoxDecoration(
        color: CrubikColors.elevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.timer_outlined, size: 28),
          const SizedBox(height: 8),
          Text(
            'Your first solve starts here',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: CrubikColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SolveRow extends StatelessWidget {
  const _SolveRow({
    required this.position,
    required this.solve,
    required this.onDelete,
  });

  final int position;
  final SolveRecord solve;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#$position',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: CrubikColors.muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDuration(solve.elapsed),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  solve.moveCount == 0
                      ? solve.inputSource.replaceAll('_', ' ')
                      : '${solve.moveCount} moves · ${solve.turnsPerSecond?.toStringAsFixed(1)} TPS',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 17),
            tooltip: 'Delete solve',
          ),
        ],
      ),
    );
  }
}

class _SessionsView extends StatelessWidget {
  const _SessionsView({required this.practice, this.mobile = false});

  final PracticeController practice;
  final bool mobile;

  Future<void> _copyExport(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: practice.exportJson()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solve history copied as Crubik JSON')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mobile) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Session',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('export-solves-button'),
                    onPressed: practice.hasSolves
                        ? () => _copyExport(context)
                        : null,
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: const Text('Export'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _MobileStats(practice: practice),
              const SizedBox(height: 10),
              Expanded(
                child: _RecentSolves(practice: practice, scrollable: true),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Session',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              OutlinedButton.icon(
                key: const Key('export-solves-button'),
                onPressed: practice.hasSolves
                    ? () => _copyExport(context)
                    : null,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copy export'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Solve history and essential statistics.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _MobileStats(practice: practice),
          const SizedBox(height: 16),
          _RecentSolves(practice: practice),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: CrubikColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CrubikColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: CrubikColors.muted,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.35,
      ),
    );
  }
}

class _ScrambleProgressText extends StatelessWidget {
  const _ScrambleProgressText({
    required this.practice,
    this.compact = false,
    this.dense = false,
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
        : completed
        ? CrubikColors.lime
        : partiallyCompleted
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                move.notation,
                style: TextStyle(
                  color: color,
                  fontFamily: 'monospace',
                  fontSize: dense
                      ? 11
                      : compact
                      ? 13
                      : 18,
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
              if (partiallyCompleted) ...[
                SizedBox(width: dense ? 1 : 3),
                Text(
                  '$partialTurns/${move.turns}',
                  key: const Key('partial-scramble-progress'),
                  style: TextStyle(
                    color: CrubikColors.lime,
                    fontFamily: 'monospace',
                    fontSize: dense
                        ? 7
                        : compact
                        ? 9
                        : 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrambleGuidance extends StatelessWidget {
  const _ScrambleGuidance({
    required this.practice,
    this.compact = false,
    this.dense = false,
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
      PracticePhase.stopped => 'Solve complete · choose a new scramble',
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

String _phaseLabel(PracticeController practice) => switch (practice.phase) {
  PracticePhase.manualReady => 'READY',
  PracticePhase.awaitingCubeState => 'WAITING FOR CUBE',
  PracticePhase.needsSolvedCube => 'SOLVE CUBE FIRST',
  PracticePhase.scrambling => 'SCRAMBLING',
  PracticePhase.inspectionDelay => 'GET READY',
  PracticePhase.inspection => 'INSPECTION',
  PracticePhase.solving => 'SOLVING',
  PracticePhase.stopped =>
    practice.smartCubeWorkflowActive ? 'SOLVE COMPLETE' : 'LAST SOLVE',
};

Color _phaseColor(PracticeController practice) => switch (practice.phase) {
  PracticePhase.needsSolvedCube => CrubikColors.warning,
  PracticePhase.scrambling ||
  PracticePhase.inspectionDelay ||
  PracticePhase.inspection => CrubikColors.cyan,
  PracticePhase.solving => CrubikColors.lime,
  PracticePhase.manualReady ||
  PracticePhase.awaitingCubeState ||
  PracticePhase.stopped => CrubikColors.muted,
};

Duration _displayedTime(PracticeController practice) =>
    switch (practice.phase) {
      PracticePhase.inspectionDelay => practice.preInspectionRemaining,
      PracticePhase.inspection => practice.inspectionRemaining,
      _ => practice.elapsed,
    };

bool _connectedAttemptActive(PracticeController practice) =>
    practice.smartCubeWorkflowActive &&
    (practice.phase == PracticePhase.inspection ||
        practice.phase == PracticePhase.solving);

String _primaryActionLabel(PracticeController practice) {
  if (practice.smartCubeWorkflowActive) {
    return switch (practice.phase) {
      PracticePhase.awaitingCubeState => 'WAITING FOR CUBE',
      PracticePhase.needsSolvedCube => 'SOLVE CUBE FIRST',
      PracticePhase.scrambling => 'FOLLOW SCRAMBLE',
      PracticePhase.inspectionDelay => 'GET READY',
      PracticePhase.inspection || PracticePhase.solving => 'ABORT',
      PracticePhase.stopped => 'SOLVE COMPLETE',
      PracticePhase.manualReady => 'START SOLVE',
    };
  }
  return practice.phase == PracticePhase.solving
      ? 'STOP & SAVE'
      : 'START SOLVE';
}

IconData _primaryActionIcon(PracticeController practice) {
  if (_connectedAttemptActive(practice)) return Icons.close_rounded;
  if (!practice.smartCubeWorkflowActive &&
      practice.phase == PracticePhase.solving) {
    return Icons.stop_rounded;
  }
  if (practice.smartCubeWorkflowActive) return Icons.sync_rounded;
  return Icons.play_arrow_rounded;
}

String _shortcutHint(PracticeController practice) {
  if (!practice.smartCubeWorkflowActive) {
    return 'Spacebar also starts and stops';
  }
  if (_connectedAttemptActive(practice)) {
    return 'Spacebar aborts this attempt';
  }
  return 'Timing starts automatically from the physical cube';
}

String _formatDuration(Duration duration) {
  final totalHundredths = duration.inMilliseconds ~/ 10;
  final hundredths = totalHundredths % 100;
  final totalSeconds = totalHundredths ~/ 100;
  final seconds = totalSeconds % 60;
  final minutes = totalSeconds ~/ 60;
  if (minutes > 0) {
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';
  }
  return '$seconds.${hundredths.toString().padLeft(2, '0')}';
}

String _formatOptionalDuration(Duration? duration) =>
    duration == null ? '—' : _formatDuration(duration);
