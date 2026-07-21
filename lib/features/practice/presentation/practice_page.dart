import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../cube/application/cube_connection_controller.dart';
import '../application/practice_controller.dart';
import '../application/practice_input_coordinator.dart';
import 'practice_layout.dart';
import 'sessions_view.dart';
import 'widgets/practice_brand.dart';
import 'widgets/practice_connection.dart';
import 'widgets/practice_panel.dart';

/// Coordinates practice/session navigation, input selection, and page chrome.
class PracticePage extends StatefulWidget {
  const PracticePage({
    required this.practiceController,
    required this.inputCoordinator,
    required this.connectionController,
    super.key,
  });

  final PracticeController practiceController;
  final PracticeInputCoordinator inputCoordinator;
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
            final isDesktop =
                constraints.maxWidth >= CrubikLayout.desktopBreakpoint;
            final timerShortcutEnabled =
                _selectedIndex == 0 &&
                widget.practiceController.inputMode !=
                    PracticeInputMode.unselected &&
                widget.practiceController.pendingSolveReview == null;
            return CallbackShortcuts(
              bindings: timerShortcutEnabled
                  ? {
                      const SingleActivator(LogicalKeyboardKey.space):
                          widget.practiceController.toggleTimer,
                    }
                  : const {},
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
            Expanded(child: _desktopContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final focusMode =
        _selectedIndex == 0 &&
        widget.practiceController.inputMode != PracticeInputMode.unselected &&
        widget.practiceController.pendingSolveReview == null &&
        widget.practiceController.attemptInProgress;
    return Scaffold(
      key: const Key('practice-mobile-layout'),
      appBar: focusMode
          ? null
          : AppBar(
              titleSpacing: 16,
              title: const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: PracticeBrand(compact: true),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: PracticeConnectionButton(
                    practice: widget.practiceController,
                    connection: widget.connectionController,
                    onPressed: _showConnectionDialog,
                    compact: true,
                  ),
                ),
              ],
            ),
      body: _mobileContent(focusMode: focusMode),
      bottomNavigationBar: focusMode
          ? null
          : BottomNavigationBar(
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

  Widget _desktopContent() {
    if (_selectedIndex != 0) {
      return SessionsView(practice: widget.practiceController);
    }
    if (widget.practiceController.inputMode == PracticeInputMode.unselected) {
      return _InputModeChooser(
        desktop: true,
        practice: widget.practiceController,
        connection: widget.connectionController,
        onConnectPressed: _showConnectionDialog,
        onDemoPressed: widget.inputCoordinator.useDemoCube,
      );
    }
    return DesktopPracticeLayout(
      practice: widget.practiceController,
      connection: widget.connectionController,
      onConnectPressed: _showConnectionDialog,
    );
  }

  Widget _mobileContent({required bool focusMode}) {
    if (_selectedIndex != 0) {
      return SessionsView(practice: widget.practiceController, mobile: true);
    }
    if (widget.practiceController.inputMode == PracticeInputMode.unselected) {
      return _InputModeChooser(
        practice: widget.practiceController,
        connection: widget.connectionController,
        onConnectPressed: _showConnectionDialog,
        onDemoPressed: widget.inputCoordinator.useDemoCube,
      );
    }
    final practice = MobilePracticeLayout(
      practice: widget.practiceController,
      connection: widget.connectionController,
    );
    return focusMode ? SafeArea(child: practice) : practice;
  }

  Future<void> _showConnectionDialog() async {
    await showPracticeConnectionDialog(
      context,
      practice: widget.practiceController,
      connection: widget.connectionController,
      onUseDemoCube: widget.inputCoordinator.useDemoCube,
      onExitDemo: widget.inputCoordinator.exitDemo,
      onConnect: widget.inputCoordinator.connect,
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
            child: PracticeBrandMark(),
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
    required this.practice,
    required this.connection,
    required this.onConnectPressed,
    required this.onDemoPressed,
    this.desktop = false,
  });

  final PracticeController practice;
  final CubeConnectionController connection;
  final VoidCallback onConnectPressed;
  final VoidCallback onDemoPressed;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compactLandscape = !desktop && size.width > size.height;
    final maximumContentWidth = compactLandscape ? 760.0 : 560.0;
    final icon = Container(
      width: compactLandscape ? 52 : 64,
      height: compactLandscape ? 52 : 64,
      decoration: BoxDecoration(
        color: CrubikColors.limeTintSoft,
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
    final startContent = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maximumContentWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (connection.automaticReconnectPhase !=
              AutomaticReconnectPhase.inactive) ...[
            _AutomaticReconnectCard(connection: connection),
            const SizedBox(height: 12),
          ],
          PracticePanel(
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
        ],
      ),
    );

    if (!desktop) {
      return SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: startContent,
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
              const Expanded(child: PracticeBrand()),
              PracticeConnectionButton(
                practice: practice,
                connection: connection,
                onPressed: onConnectPressed,
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: startContent,
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

class _AutomaticReconnectCard extends StatelessWidget {
  const _AutomaticReconnectCard({required this.connection});

  final CubeConnectionController connection;

  @override
  Widget build(BuildContext context) {
    final searching =
        connection.automaticReconnectPhase == AutomaticReconnectPhase.searching;
    final cubeName = connection.automaticReconnectDeviceName;
    final action = searching ? 'Looking for' : 'Connecting to';
    final title = '$action ${cubeName ?? 'your recent cube'}';
    final description = searching
        ? 'Automatic reconnect is running in the background.'
        : 'Restoring its live state…';

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('automatic-reconnect-status'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        decoration: BoxDecoration(
          color: CrubikColors.limeTintSubtle,
          border: Border.all(color: CrubikColors.limeBorderSoft),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 38,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox.square(
                    dimension: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: CrubikColors.lime,
                    ),
                  ),
                  Icon(
                    searching
                        ? Icons.bluetooth_searching
                        : Icons.bluetooth_connected,
                    color: CrubikColors.lime,
                    size: 18,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: CrubikColors.muted),
                  ),
                ],
              ),
            ),
            if (searching) ...[
              const SizedBox(width: 6),
              TextButton(
                key: const Key('stop-automatic-reconnect'),
                onPressed: connection.stopAutomaticReconnect,
                child: const Text('Stop'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
