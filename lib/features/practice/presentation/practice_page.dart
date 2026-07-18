import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../cube/application/cube_connection_controller.dart';
import '../../cube/domain/smart_cube_device.dart';
import '../../cube/domain/cube_model.dart';
import '../application/practice_controller.dart';
import '../domain/solve_record.dart';
import 'widgets/cube_3d_view.dart';

class PracticePage extends StatefulWidget {
  const PracticePage({
    required this.practiceController,
    required this.connectionController,
    super.key,
  });

  final PracticeController practiceController;
  final CubeConnectionController connectionController;

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.practiceController,
        widget.connectionController,
      ]),
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
                child:
                    isDesktop ? _buildDesktop(context) : _buildMobile(context),
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
              onDestinationSelected:
                  (index) => setState(() => _selectedIndex = index),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child:
                  _selectedIndex == 0
                      ? _DesktopPractice(
                        practice: widget.practiceController,
                        connection: widget.connectionController,
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
            child: _ConnectionButton(
              connection: widget.connectionController,
              onPressed: _showConnectionDialog,
              compact: true,
            ),
          ),
        ],
      ),
      body:
          _selectedIndex == 0
              ? _MobilePractice(
                practice: widget.practiceController,
                connection: widget.connectionController,
              )
              : _SessionsView(
                practice: widget.practiceController,
                mobile: true,
              ),
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
    await showDialog<void>(
      context: context,
      builder:
          (context) =>
              _ConnectionDialog(controller: widget.connectionController),
    );
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
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Tooltip(
              message: 'Crubik works offline',
              child: Icon(Icons.cloud_off_outlined, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopPractice extends StatelessWidget {
  const _DesktopPractice({
    required this.practice,
    required this.connection,
    required this.onConnectPressed,
  });

  final PracticeController practice;
  final CubeConnectionController connection;
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
              const _OfflineBadge(),
              const SizedBox(width: 10),
              _ConnectionButton(
                connection: connection,
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
                              connection: connection,
                              compact: false,
                            ),
                            const SizedBox(height: 16),
                            _ScramblePanel(practice: practice),
                            const SizedBox(height: 16),
                            _MoveInputPanel(practice: practice),
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
  const _MobilePractice({required this.practice, required this.connection});

  final PracticeController practice;
  final CubeConnectionController connection;

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
              connection: connection,
              onManualMoves: () => _showManualMoves(context),
              scrollFallback: true,
            ),
          );
        }

        final landscape = constraints.maxWidth > constraints.maxHeight;
        return Padding(
          padding: EdgeInsets.all(landscape ? 8 : 12),
          child:
              landscape
                  ? _MobilePracticeLandscape(
                    practice: practice,
                    connection: connection,
                    onManualMoves: () => _showManualMoves(context),
                  )
                  : _MobilePracticePortrait(
                    practice: practice,
                    connection: connection,
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
    required this.connection,
    required this.onManualMoves,
    this.scrollFallback = false,
  });

  final PracticeController practice;
  final CubeConnectionController connection;
  final VoidCallback onManualMoves;
  final bool scrollFallback;

  @override
  Widget build(BuildContext context) {
    final cube = _CompactCubePanel(practice: practice, connection: connection);
    return Column(
      mainAxisSize: scrollFallback ? MainAxisSize.min : MainAxisSize.max,
      children: [
        _CompactScramblePanel(practice: practice, onManualMoves: onManualMoves),
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
    required this.connection,
    required this.onManualMoves,
  });

  final PracticeController practice;
  final CubeConnectionController connection;
  final VoidCallback onManualMoves;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _CompactCubePanel(practice: practice, connection: connection),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Column(
            children: [
              Expanded(
                child: _CompactScramblePanel(
                  practice: practice,
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
  const _CompactCubePanel({required this.practice, required this.connection});

  final PracticeController practice;
  final CubeConnectionController connection;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maximumDimension = constraints.maxWidth;
          final availableDimension = constraints.maxHeight - 48;
          final dimension =
              availableDimension.clamp(96.0, maximumDimension).toDouble();
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
                      color:
                          connection.isConnected
                              ? CrubikColors.lime
                              : CrubikColors.muted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    connection.isConnected ? 'LINKED' : 'MANUAL',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color:
                          connection.isConnected
                              ? CrubikColors.lime
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
    required this.onManualMoves,
    this.landscape = false,
  });

  final PracticeController practice;
  final VoidCallback onManualMoves;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final canReset = practice.timerPhase != SolveTimerPhase.running;
    return _Panel(
      padding: EdgeInsets.all(landscape ? 9 : 12),
      child: Column(
        mainAxisAlignment:
            landscape
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
                  onPressed: canReset ? practice.newScramble : null,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.shuffle_rounded, size: 17),
                  label: const Text('New'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                key: const Key('reset-scramble'),
                onPressed: canReset ? practice.resetCubeToScramble : null,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.replay_rounded, size: 18),
                tooltip: 'Reset visual cube to scramble',
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
          ),
        ],
      ),
    );
  }

  Widget _scrambleText(BuildContext context) {
    return SelectableText(
      practice.scramble.toString(),
      key: const Key('scramble-text'),
      maxLines: landscape ? 2 : 3,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontFamily: 'monospace', height: 1.25),
    );
  }
}

class _CompactTimerPanel extends StatelessWidget {
  const _CompactTimerPanel({required this.practice, this.landscape = false});

  final PracticeController practice;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final running = practice.timerPhase == SolveTimerPhase.running;
    final phaseLabel = switch (practice.timerPhase) {
      SolveTimerPhase.ready => 'READY',
      SolveTimerPhase.running => 'SOLVING',
      SolveTimerPhase.stopped => 'LAST SOLVE',
    };
    final time = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        _formatDuration(practice.elapsed),
        key: const Key('timer-display'),
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          fontSize: landscape ? 42 : 50,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: running ? CrubikColors.lime : CrubikColors.text,
        ),
      ),
    );
    final button = FilledButton.icon(
      key: const Key('timer-toggle'),
      onPressed: practice.toggleTimer,
      style: FilledButton.styleFrom(
        backgroundColor: running ? CrubikColors.danger : CrubikColors.lime,
        foregroundColor: CrubikColors.background,
        padding: EdgeInsets.symmetric(vertical: landscape ? 10 : 12),
      ),
      icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
      label: Text(running ? 'STOP & SAVE' : 'START SOLVE'),
    );

    return _Panel(
      padding: EdgeInsets.all(landscape ? 9 : 12),
      child:
          landscape
              ? Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          phaseLabel,
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(
                            color:
                                running
                                    ? CrubikColors.lime
                                    : CrubikColors.muted,
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
                      color: running ? CrubikColors.lime : CrubikColors.muted,
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'CRUBIK',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(letterSpacing: 2.4),
            ),
            if (!compact)
              Text(
                'OFFLINE CUBE LAB',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CrubikColors.muted,
                  letterSpacing: 1.8,
                ),
              ),
          ],
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

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: CrubikColors.elevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: CrubikColors.border),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: CrubikColors.cyan),
          SizedBox(width: 7),
          Text(
            'OFFLINE READY',
            style: TextStyle(
              color: CrubikColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionButton extends StatelessWidget {
  const _ConnectionButton({
    required this.connection,
    required this.onPressed,
    this.compact = false,
  });

  final CubeConnectionController connection;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isConnected = connection.isConnected;
    final label =
        isConnected
            ? (compact ? 'LIVE' : connection.connectedCube!.name)
            : (compact ? 'CONNECT' : 'Connect cube');
    return OutlinedButton.icon(
      key: const Key('connect-cube-button'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: isConnected ? CrubikColors.lime : CrubikColors.text,
        side: BorderSide(
          color: isConnected ? CrubikColors.lime : CrubikColors.border,
        ),
        backgroundColor:
            isConnected ? const Color(0x12B7F34A) : CrubikColors.surface,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: 11,
        ),
      ),
      icon: Icon(
        isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
        size: 18,
      ),
      label: Text(label),
    );
  }
}

class _CubeAndTimerHero extends StatelessWidget {
  const _CubeAndTimerHero({
    required this.practice,
    required this.connection,
    required this.compact,
  });

  final PracticeController practice;
  final CubeConnectionController connection;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cube = _CubeStage(
      practice: practice,
      connection: connection,
      compact: compact,
    );
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
    required this.connection,
    required this.compact,
  });

  final PracticeController practice;
  final CubeConnectionController connection;
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
                color:
                    connection.isConnected
                        ? CrubikColors.lime
                        : CrubikColors.muted,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              connection.isConnected ? 'LINKED' : 'MANUAL',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color:
                    connection.isConnected
                        ? CrubikColors.lime
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
    final running = practice.timerPhase == SolveTimerPhase.running;
    final phaseLabel = switch (practice.timerPhase) {
      SolveTimerPhase.ready => 'READY',
      SolveTimerPhase.running => 'SOLVING',
      SolveTimerPhase.stopped => 'LAST SOLVE',
    };
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            phaseLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: running ? CrubikColors.lime : CrubikColors.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatDuration(practice.elapsed),
              key: const Key('timer-display'),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontSize: compact ? 62 : 78,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: running ? CrubikColors.lime : CrubikColors.text,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('timer-toggle'),
              onPressed: practice.toggleTimer,
              style: FilledButton.styleFrom(
                backgroundColor:
                    running ? CrubikColors.danger : CrubikColors.lime,
                foregroundColor: CrubikColors.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(
                running ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(running ? 'STOP & SAVE' : 'START SOLVE'),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'Spacebar also starts and stops',
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
  const _ScramblePanel({required this.practice});

  final PracticeController practice;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const _SectionLabel('PRACTICE SCRAMBLE'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x1458D8DA),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'OFFLINE · 20 MOVES',
                  style: TextStyle(
                    color: CrubikColors.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SelectableText(
            practice.scramble.toString(),
            key: const Key('scramble-text'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontFamily: 'monospace',
              height: 1.45,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('new-scramble'),
                  onPressed:
                      practice.timerPhase == SolveTimerPhase.running
                          ? null
                          : practice.newScramble,
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('New scramble'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                onPressed:
                    practice.timerPhase == SolveTimerPhase.running
                        ? null
                        : practice.resetCubeToScramble,
                icon: const Icon(Icons.replay_rounded),
                tooltip: 'Reset visual cube to scramble',
              ),
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
              final columns =
                  constraints.maxWidth > 580
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
                        onPressed:
                            () => practice.applyMove(CubeMove.parse(notation)),
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
    final list =
        solves.isEmpty
            ? const _EmptySolves()
            : ListView.separated(
              key: const Key('recent-solves-list'),
              padding: EdgeInsets.zero,
              itemCount: solves.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder:
                  (context, index) => _SolveRow(
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
          const SizedBox(height: 3),
          Text(
            'No account or internet needed',
            style: Theme.of(context).textTheme.bodySmall,
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
                    onPressed:
                        practice.hasSolves ? () => _copyExport(context) : null,
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
                onPressed:
                    practice.hasSolves ? () => _copyExport(context) : null,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copy export'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Local solve history and essential statistics.',
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

class _ConnectionDialog extends StatelessWidget {
  const _ConnectionDialog({required this.controller});

  final CubeConnectionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final scanning = controller.status == CubeConnectionStatus.scanning;
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          backgroundColor: CrubikColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: CrubikColors.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0x16B7F34A),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.bluetooth_searching,
                          color: CrubikColors.lime,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connect a smart cube',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'MVP protocols: GAN Gen2–4, MoYu AI 2023, and MoYu32',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (controller.isConnected) ...[
                    _ConnectedCubeCard(controller: controller),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                scanning
                                    ? controller.stopScan
                                    : controller.startScan,
                            icon: Icon(
                              scanning ? Icons.stop : Icons.bluetooth_searching,
                            ),
                            label: Text(scanning ? 'Stop scan' : 'Scan nearby'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await controller.connectDemo();
                            if (context.mounted) Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.science_outlined),
                          label: const Text('Demo'),
                        ),
                      ],
                    ),
                    if (scanning) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        controller.errorMessage!,
                        style: const TextStyle(color: CrubikColors.danger),
                      ),
                      if (controller.hasDiagnostics) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('copy-bluetooth-diagnostics-button'),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: controller.diagnosticReport),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Redacted Bluetooth diagnostics copied',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          label: const Text('Copy diagnostics'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    Flexible(
                      child:
                          controller.discoveredDevices.isEmpty
                              ? _EmptyDeviceSearch(scanning: scanning)
                              : _DiscoveredDeviceList(controller: controller),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Supported cube turns update the live model and timer locally. Demo mode stays available for practice without hardware.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CrubikColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConnectedCubeCard extends StatelessWidget {
  const _ConnectedCubeCard({required this.controller});

  final CubeConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final device = controller.connectedCube!;
    final batteryLevel = controller.batteryLevel;
    final connectionStatus =
        device.isDemo
            ? 'Demo movement source'
            : batteryLevel == null
            ? 'BLE link active'
            : 'BLE link active · $batteryLevel% battery';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x12B7F34A),
        border: Border.all(color: const Color(0x66B7F34A)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected, color: CrubikColors.lime),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  connectionStatus,
                  semanticsLabel:
                      batteryLevel == null
                          ? connectionStatus
                          : 'BLE link active, battery $batteryLevel percent',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: controller.disconnect,
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}

class _EmptyDeviceSearch extends StatelessWidget {
  const _EmptyDeviceSearch({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: CrubikColors.elevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(scanning ? Icons.radar : Icons.bluetooth_disabled, size: 30),
          const SizedBox(height: 10),
          Text(
            scanning
                ? 'Looking for nearby Bluetooth devices…'
                : 'No Bluetooth devices found yet',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: CrubikColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            'Wake your cube with a turn and keep nearby devices in range.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DiscoveredDeviceList extends StatelessWidget {
  const _DiscoveredDeviceList({required this.controller});

  final CubeConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final cubes = controller.discoveredCubes;
    final otherDevices = controller.otherDiscoveredDevices;
    final connectionBusy =
        controller.status == CubeConnectionStatus.connecting;

    return ListView(
      key: const Key('discovered-device-list'),
      shrinkWrap: true,
      children: [
        _DeviceGroupHeader(title: 'Cubes', count: cubes.length),
        const SizedBox(height: 8),
        if (cubes.isEmpty)
          const _NoIdentifiedCubes()
        else
          for (var index = 0; index < cubes.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _DeviceResult(
              device: cubes[index],
              connecting: controller.connectingDeviceId == cubes[index].id,
              connectionBusy: connectionBusy,
              onConnect:
                  cubes[index].canConnect
                      ? () async {
                        await controller.connect(cubes[index]);
                        if (context.mounted && controller.isConnected) {
                          Navigator.of(context).pop();
                        }
                      }
                      : null,
            ),
          ],
        if (otherDevices.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DeviceGroupHeader(
            title: 'Other available devices',
            count: otherDevices.length,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < otherDevices.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _DeviceResult(
              device: otherDevices[index],
              connecting: false,
              connectionBusy: connectionBusy,
              onConnect: null,
            ),
          ],
        ],
      ],
    );
  }
}

class _DeviceGroupHeader extends StatelessWidget {
  const _DeviceGroupHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Text(
          '$count',
          semanticsLabel: '$count devices',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: CrubikColors.muted),
        ),
      ],
    );
  }
}

class _NoIdentifiedCubes extends StatelessWidget {
  const _NoIdentifiedCubes();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CrubikColors.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CrubikColors.border),
      ),
      child: Text(
        'No identified cubes found yet.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _DeviceResult extends StatelessWidget {
  const _DeviceResult({
    required this.device,
    required this.connecting,
    required this.connectionBusy,
    required this.onConnect,
  });

  final CubeDeviceCandidate device;
  final bool connecting;
  final bool connectionBusy;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final isOtherDevice = !device.isIdentifiedCube;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CrubikColors.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CrubikColors.border),
      ),
      child: Row(
        children: [
          Icon(isOtherDevice ? Icons.bluetooth : Icons.view_in_ar_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: CrubikColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isOtherDevice)
                  Text(
                    '${device.rssi ?? '—'} dBm · Not identified as a smart cube',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else if (device.isSupported)
                  Text(
                    '${device.vendor.name.toUpperCase()} · ${device.rssi ?? '—'} dBm',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else ...[
                  Text(
                    '${device.vendor.name.toUpperCase()} · Detected, not supported yet',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CrubikColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.supportMessage ??
                        'This smart-cube protocol is not supported yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (device.canConnect)
            FilledButton(
              key: Key('connect-device-${device.id}'),
              onPressed: connectionBusy ? null : onConnect,
              child: Text(connecting ? 'Connecting…' : 'Connect'),
            )
          else if (device.isIdentifiedCube)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                Icons.info_outline,
                semanticLabel: 'Protocol not supported',
              ),
            ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});

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
