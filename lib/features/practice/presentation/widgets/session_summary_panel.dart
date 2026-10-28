import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/practice_controller.dart';
import 'practice_formatters.dart';
import 'practice_panel.dart';

class SessionSummaryPanel extends StatelessWidget {
  const SessionSummaryPanel({required this.practice, super.key});

  final PracticeController practice;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: CrubikColors.muted,
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    );
    return PracticePanel(
      key: const Key('session-summary-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FlexColumnWidth(0.8),
          1: FlexColumnWidth(),
          2: FlexColumnWidth(),
          3: FlexColumnWidth(),
          4: FlexColumnWidth(),
        },
        children: [
          TableRow(
            children: [
              const SizedBox.shrink(),
              _Cell('SINGLE', style: labelStyle),
              _Cell('AO5', style: labelStyle),
              _Cell('AO12', style: labelStyle),
              _Cell('AO100', style: labelStyle),
            ],
          ),
          TableRow(
            children: [
              _Cell('LAST', style: labelStyle, alignment: Alignment.centerLeft),
              _TimeCell(practice.lastTime),
              _TimeCell(practice.averageOfFive),
              _TimeCell(practice.averageOfTwelve),
              _TimeCell(practice.averageOfOneHundred),
            ],
          ),
          TableRow(
            children: [
              _Cell('BEST', style: labelStyle, alignment: Alignment.centerLeft),
              _TimeCell(practice.bestTime, accent: true),
              _TimeCell(practice.bestAverageOfFive, accent: true),
              _TimeCell(practice.bestAverageOfTwelve, accent: true),
              _TimeCell(practice.bestAverageOfOneHundred, accent: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell(this.value, {this.accent = false});

  final Duration? value;
  final bool accent;

  @override
  Widget build(BuildContext context) => _Cell(
    formatOptionalPracticeDuration(value),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: accent ? CrubikColors.primaryAccent : CrubikColors.text,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontSize: 11,
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell(
    this.value, {
    required this.style,
    this.alignment = Alignment.center,
  });

  final String value;
  final TextStyle? style;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
    child: SizedBox(
      height: 15,
      child: Align(
        alignment: alignment,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, maxLines: 1, style: style),
        ),
      ),
    ),
  );
}
