import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../application/practice_controller.dart';
import '../application/practice_input_controller.dart';
import 'practice_layout.dart';
import 'sessions_view.dart';
import 'widgets/practice_brand.dart';
import 'widgets/practice_connection.dart';
import 'widgets/practice_panel.dart';

/// Coordinates practice/session navigation, input selection, and page chrome.
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
            final timerShortcutEnabled =
                _selectedIndex == 0 &&
                !widget.inputController.isUnselected &&
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
            Expanded(
              child: _selectedIndex == 0
                  ? widget.inputController.isUnselected
                        ? _InputModeChooser(
                            desktop: true,
                            input: widget.inputController,
                            onConnectPressed: _showConnectionDialog,
                            onDemoPressed: widget.inputController.useDemoCube,
                          )
                        : DesktopPracticeLayout(
                            practice: widget.practiceController,
                            input: widget.inputController,
                            onConnectPressed: _showConnectionDialog,
                          )
                  : SessionsView(practice: widget.practiceController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final focusMode =
        _selectedIndex == 0 &&
        !widget.inputController.isUnselected &&
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
                : focusMode
                ? SafeArea(
                    child: MobilePracticeLayout(
                      practice: widget.practiceController,
                      input: widget.inputController,
                    ),
                  )
                : MobilePracticeLayout(
                    practice: widget.practiceController,
                    input: widget.inputController,
                  )
          : SessionsView(practice: widget.practiceController, mobile: true),
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
    final maximumContentWidth = compactLandscape ? 760.0 : 560.0;
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
    final startContent = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maximumContentWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (input.isAutomaticReconnectActive) ...[
            _AutomaticReconnectCard(input: input),
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
                input: input,
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
  const _AutomaticReconnectCard({required this.input});

  final PracticeInputController input;

  @override
  Widget build(BuildContext context) {
    final searching = input.isAutomaticReconnectSearching;
    final cubeName = input.automaticReconnectDeviceName;
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
          color: const Color(0x12B7F34A),
          border: Border.all(color: const Color(0x55B7F34A)),
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
                onPressed: input.stopAutomaticReconnect,
                child: const Text('Stop'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
