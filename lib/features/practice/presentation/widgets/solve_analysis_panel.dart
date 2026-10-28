import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/practice_controller.dart';
import '../../domain/solve_analysis.dart';
import '../../domain/solve_record.dart';
import 'practice_formatters.dart';
import 'practice_panel.dart';

class SolveAnalysisPanel extends StatefulWidget {
  const SolveAnalysisPanel({
    required this.practice,
    required this.solve,
    this.historical = false,
    this.onContinue,
    super.key,
  });

  final PracticeController practice;
  final SolveRecord solve;
  final bool historical;
  final VoidCallback? onContinue;

  @override
  State<SolveAnalysisPanel> createState() => _SolveAnalysisPanelState();
}

class _SolveAnalysisPanelState extends State<SolveAnalysisPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  SolveAnalysis? _analysis;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _loadAnalysis();
  }

  @override
  void didUpdateWidget(covariant SolveAnalysisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.solve.id != widget.solve.id) {
      _analysis = null;
      _tabs.index = 0;
      _loadAnalysis();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _loadAnalysis() {
    final solveId = widget.solve.id;
    _analysis = widget.practice.analysisForCached(solveId);
    unawaited(
      widget.practice.analysisFor(widget.solve).then((analysis) {
        if (mounted && widget.solve.id == solveId) {
          setState(() => _analysis = analysis);
        }
      }),
    );
  }

  Future<void> _deleteSolve() async {
    final shouldDelete = await confirmSolveDeletion(context, widget.solve);
    if (!mounted || !shouldDelete) return;
    widget.practice.deleteSolve(widget.solve.id);
  }

  @override
  Widget build(BuildContext context) {
    final solve = widget.solve;
    final analysis = widget.practice.analysisForCached(solve.id) ?? _analysis;
    return PracticePanel(
      key: const Key('solve-analysis-panel'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SolveSummary(
            solve: solve,
            historical: widget.historical,
            onContinue: widget.onContinue,
            onDelete: () => unawaited(_deleteSolve()),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: CrubikColors.border),
          SizedBox(
            height: 40,
            child: TabBar(
              controller: _tabs,
              dividerColor: CrubikColors.border,
              labelColor: CrubikColors.text,
              unselectedLabelColor: CrubikColors.muted,
              labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
              tabs: const [
                _AnalysisTabLabel('OVERVIEW'),
                _AnalysisTabLabel('STEPS'),
                _AnalysisTabLabel('SOLUTION'),
                _AnalysisTabLabel('STATS'),
                _AnalysisTabLabel('TPS'),
                _AnalysisTabLabel('INFO'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(analysis: analysis),
                _StepsTab(analysis: analysis),
                _SolutionTab(analysis: analysis),
                _StatsTab(solve: solve, analysis: analysis),
                _TpsTab(analysis: analysis),
                _InfoTab(solve: solve, analysis: analysis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisTabLabel extends StatelessWidget {
  const _AnalysisTabLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Tab(
    height: 38,
    child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
  );
}

class _SolveSummary extends StatelessWidget {
  const _SolveSummary({
    required this.solve,
    required this.historical,
    required this.onContinue,
    required this.onDelete,
  });

  final SolveRecord solve;
  final bool historical;
  final VoidCallback? onContinue;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: !historical,
      label: historical
          ? 'Solve from ${_formatDate(solve.createdAt)}'
          : 'Solve complete. Time ${solve.isTimingReliable ? formatPracticeDuration(solve.elapsed) : 'unavailable'}. '
                '${solve.moveCount} moves. TPS ${solve.turnsPerSecond?.toStringAsFixed(1) ?? 'unavailable'}.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    historical
                        ? _formatDate(solve.createdAt).toUpperCase()
                        : 'SOLVE COMPLETE',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: CrubikColors.primaryAccent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    solve.isTimingReliable
                        ? formatPracticeDuration(solve.elapsed)
                        : 'Timing unavailable',
                    key: const Key('finish-time'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: 34,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SummaryMetric(
            icon: Icons.speed,
            label: 'TPS',
            value: solve.turnsPerSecond?.toStringAsFixed(1) ?? '—',
            valueKey: const Key('finish-tps'),
          ),
          const SizedBox(width: 14),
          _SummaryMetric(
            icon: Icons.sync_alt,
            label: 'TURNS',
            value: solve.moveCount.toString(),
            valueKey: const Key('finish-moves'),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: const Key('delete-solve-button'),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Delete solve',
          ),
          if (onContinue != null) ...[
            const SizedBox(width: 2),
            FilledButton(
              key: const Key('continue-after-solve'),
              onPressed: onContinue,
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('OK'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: CrubikColors.muted),
                const SizedBox(width: 4),
                Text(
                  label,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: CrubikColors.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              key: valueKey,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmSolveDeletion(
  BuildContext context,
  SolveRecord solve,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('DELETE SOLVE?'),
      content: Text(
        'DELETE ${formatPracticeDuration(solve.elapsed)} FROM ${_formatDate(solve.createdAt).toUpperCase()}? THIS CANNOT BE UNDONE.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          key: const Key('confirm-delete-solve'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('DELETE'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.analysis});

  final SolveAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final analysis = this.analysis;
    if (analysis == null || analysis.stages.isEmpty) {
      return _AnalysisUnavailable(analysis: analysis);
    }
    final maximum = analysis.stages
        .map((stage) => stage.stepTime?.inMicroseconds ?? 0)
        .fold<int>(1, (current, value) => value > current ? value : current);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
      child: Column(
        children: [
          const Align(alignment: Alignment.centerRight, child: _ChartLegend()),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChartScale(maximumMicroseconds: maximum),
                const SizedBox(width: 5),
                Expanded(
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(painter: _OverviewGridPainter()),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final stage in analysis.stages)
                            Expanded(
                              child: _StageBar(
                                stage: stage,
                                maximumMicroseconds: maximum,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: const [
      _LegendItem(color: CrubikColors.primaryAccent, label: 'RECOG'),
      SizedBox(width: 10),
      _LegendItem(color: CrubikColors.secondaryAccent, label: 'EXEC'),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 3),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: CrubikColors.muted,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _ChartScale extends StatelessWidget {
  const _ChartScale({required this.maximumMicroseconds});

  final int maximumMicroseconds;

  @override
  Widget build(BuildContext context) {
    final maximumSeconds = maximumMicroseconds / Duration.microsecondsPerSecond;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: CrubikColors.muted,
      fontSize: 8,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SizedBox(
      width: 30,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(maximumSeconds.toStringAsFixed(1), style: style),
            Text((maximumSeconds / 2).toStringAsFixed(1), style: style),
            Text('0', style: style),
          ],
        ),
      ),
    );
  }
}

class _OverviewGridPainter extends CustomPainter {
  const _OverviewGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CrubikColors.border
      ..strokeWidth = 1;
    final chartHeight = size.height - 20;
    for (final fraction in const [0.0, 0.5, 1.0]) {
      final y = chartHeight * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverviewGridPainter oldDelegate) => false;
}

class _StageBar extends StatelessWidget {
  const _StageBar({required this.stage, required this.maximumMicroseconds});

  final SolveStageAnalysis stage;
  final int maximumMicroseconds;

  @override
  Widget build(BuildContext context) {
    final recognition = stage.recognitionTime?.inMicroseconds ?? 0;
    final execution = stage.executionTime?.inMicroseconds ?? 0;
    final availableHeight = (recognition + execution) / maximumMicroseconds;
    final tooltip =
        '${stage.kind.label.toUpperCase()}\n'
        'STEP ${_preciseDuration(stage.stepTime)}\n'
        'RECOG ${_preciseDuration(stage.recognitionTime)}\n'
        'EXEC ${_preciseDuration(stage.executionTime)}';
    return Tooltip(
      key: Key('stage-bar-${stage.kind.serializedValue}'),
      message: tooltip,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Semantics(
        button: true,
        label: tooltip.replaceAll('\n', '. '),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: availableHeight.clamp(0.02, 1),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 34),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: CrubikColors.border),
                      ),
                      child: Column(
                        children: [
                          if (execution > 0)
                            Expanded(
                              flex: execution,
                              child: Container(
                                color: CrubikColors.secondaryAccent,
                              ),
                            ),
                          if (recognition > 0)
                            Expanded(
                              flex: recognition,
                              child: Container(
                                color: CrubikColors.primaryAccent,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  stage.kind.shortLabel,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: CrubikColors.muted,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepsTab extends StatelessWidget {
  const _StepsTab({required this.analysis});

  final SolveAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final analysis = this.analysis;
    if (analysis == null || analysis.stages.isEmpty) {
      return _AnalysisUnavailable(analysis: analysis);
    }
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 620
          ? _CompactSteps(stages: analysis.stages)
          : _WideSteps(stages: analysis.stages),
    );
  }
}

class _CompactSteps extends StatelessWidget {
  const _CompactSteps({required this.stages});

  final List<SolveStageAnalysis> stages;

  @override
  Widget build(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: CrubikColors.muted,
      fontSize: 8,
      fontWeight: FontWeight.w700,
    );
    final valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 9,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    const columnWidths = <int, TableColumnWidth>{
      0: FlexColumnWidth(1.4),
      1: FlexColumnWidth(),
      2: FlexColumnWidth(),
      3: FlexColumnWidth(),
      4: FlexColumnWidth(),
      5: FlexColumnWidth(0.7),
      6: FlexColumnWidth(0.8),
    };
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        Table(
          key: const Key('compact-steps-table'),
          columnWidths: columnWidths,
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(
            horizontalInside: BorderSide(color: CrubikColors.border),
            bottom: BorderSide(color: CrubikColors.border),
          ),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: CrubikColors.elevated),
              children: [
                for (final label in const [
                  'STEP',
                  'RECOG',
                  'EXEC',
                  'TIME',
                  'TOTAL',
                  'TURN',
                  'TPS',
                ])
                  _StepCell(label, style: headerStyle),
              ],
            ),
            for (final stage in stages)
              TableRow(
                children: [
                  _StepCell(
                    stage.kind.shortLabel,
                    style: valueStyle?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  _StepCell(
                    stage.skipped ? '—' : _shortDuration(stage.recognitionTime),
                    style: valueStyle,
                  ),
                  _StepCell(
                    stage.skipped ? '—' : _shortDuration(stage.executionTime),
                    style: valueStyle,
                  ),
                  _StepCell(
                    stage.skipped ? '—' : _shortDuration(stage.stepTime),
                    style: valueStyle,
                  ),
                  _StepCell(
                    stage.skipped ? '—' : _shortDuration(stage.totalTime),
                    style: valueStyle,
                  ),
                  _StepCell(
                    stage.skipped ? '—' : stage.moves.length.toString(),
                    style: valueStyle,
                  ),
                  _StepCell(
                    stage.skipped ? '—' : _decimal(stage.turnsPerSecond),
                    style: valueStyle,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _StepCell extends StatelessWidget {
  const _StepCell(this.value, {required this.style});

  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value, maxLines: 1, style: style),
    ),
  );
}

class _WideSteps extends StatelessWidget {
  const _WideSteps({required this.stages});

  final List<SolveStageAnalysis> stages;

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(
      color: CrubikColors.muted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('STEP', style: headerStyle)),
              Expanded(child: Text('RECOG', style: headerStyle)),
              Expanded(child: Text('EXEC', style: headerStyle)),
              Expanded(child: Text('STEP TIME', style: headerStyle)),
              Expanded(child: Text('TOTAL', style: headerStyle)),
              Expanded(child: Text('TURNS', style: headerStyle)),
              Expanded(child: Text('TPS', style: headerStyle)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: stages.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final stage = stages[index];
              final values = [
                stage.kind.label.toUpperCase(),
                _duration(stage.recognitionTime),
                _duration(stage.executionTime),
                _duration(stage.stepTime),
                _duration(stage.totalTime),
                stage.moves.length.toString(),
                _decimal(stage.turnsPerSecond),
              ];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text(values.first, maxLines: 1)),
                    for (final value in values.skip(1))
                      Expanded(
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SolutionTab extends StatelessWidget {
  const _SolutionTab({required this.analysis});

  final SolveAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final analysis = this.analysis;
    if (analysis == null || analysis.stages.isEmpty) {
      return _AnalysisUnavailable(analysis: analysis);
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: analysis.stages.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final stage = analysis.stages[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: Text(
                  stage.kind.shortLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: CrubikColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  stage.skipped
                      ? 'SKIPPED'
                      : stage.moves.map((move) => move.notation).join(' '),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.solve, required this.analysis});

  final SolveRecord solve;
  final SolveAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final values = [
      (
        Icons.visibility_outlined,
        'INSPECTION',
        _duration(solve.inspectionElapsed),
      ),
      (
        Icons.timer_outlined,
        'SOLVING TIME',
        solve.isTimingReliable ? _duration(solve.elapsed) : '—',
      ),
      (
        Icons.psychology_outlined,
        'RECOGNITION',
        _duration(analysis?.totalRecognitionTime),
      ),
      (
        Icons.touch_app_outlined,
        'EXECUTION',
        _duration(analysis?.totalExecutionTime),
      ),
      (Icons.sync_alt, 'TURNS', solve.moveCount.toString()),
      (Icons.speed, 'TPS', _decimal(solve.turnsPerSecond)),
      (
        Icons.fast_forward_outlined,
        'STEPS SKIPPED',
        analysis?.skippedStageCount.toString() ?? '—',
      ),
      (Icons.rotate_90_degrees_ccw_outlined, 'REGRIPS', _regrips(analysis)),
    ];
    return GridView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.8,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: values.length,
      itemBuilder: (context, index) {
        final value = values[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: CrubikColors.elevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: CrubikColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value.$3,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(value.$1, size: 12, color: CrubikColors.muted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value.$2,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: CrubikColors.muted,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TpsTab extends StatelessWidget {
  const _TpsTab({required this.analysis});

  final SolveAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final analysis = this.analysis;
    if (analysis == null || analysis.stages.isEmpty) {
      return _AnalysisUnavailable(analysis: analysis);
    }
    final values = analysis.stages
        .map((stage) => stage.turnsPerSecond ?? 0)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 4),
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              key: const Key('tps-chart'),
              painter: _TpsChartPainter(values),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final stage in analysis.stages)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      stage.kind.shortLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: CrubikColors.muted,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TpsChartPainter extends CustomPainter {
  const _TpsChartPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = CrubikColors.border
      ..strokeWidth = 1;
    for (var index = 0; index < 4; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final maximum = values.fold<double>(1, (a, b) => b > a ? b : a);
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * index / (values.length - 1);
      final y = size.height - (values[index] / maximum * size.height * 0.9);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = CrubikColors.primaryAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TpsChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.solve, required this.analysis});

  final SolveRecord solve;
  final SolveAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _InfoValue(label: 'SESSION', value: solve.sessionName),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _InfoValue(
                  label: 'METHOD',
                  value: solve.method.displayName,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _InfoValue(
                  label: 'INPUT',
                  value: solve.inputSource.displayLabel,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _InfoValue(
                  label: 'CUBE',
                  value: _protocolName(analysis?.protocolFamily),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoValue(label: 'SOLVED', value: _formatDate(solve.createdAt)),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(
                'SCRAMBLE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CrubikColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                key: const Key('copy-completed-scramble'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: solve.scramble));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Scramble copied')),
                  );
                },
                icon: const Icon(Icons.copy, size: 14),
                tooltip: 'Copy scramble',
              ),
            ],
          ),
          Text(
            solve.scramble,
            key: const Key('completed-scramble'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: CrubikColors.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoValue extends StatelessWidget {
  const _InfoValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: CrubikColors.muted,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 1),
      Text(
        value.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _AnalysisUnavailable extends StatelessWidget {
  const _AnalysisUnavailable({required this.analysis});

  final SolveAnalysis? analysis;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        (analysis?.failureReason ??
                'Detailed analysis requires a complete smart-cube recording.')
            .toUpperCase(),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  );
}

String _duration(Duration? value) {
  if (value == null) return '—';
  return '${(value.inMicroseconds / 1000000).toStringAsFixed(2)}S';
}

String _shortDuration(Duration? value) {
  if (value == null) return '—';
  return (value.inMicroseconds / Duration.microsecondsPerSecond)
      .toStringAsFixed(2);
}

String _preciseDuration(Duration? value) {
  if (value == null) return '—';
  return '${(value.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3)}S';
}

String _decimal(double? value) => value?.toStringAsFixed(1) ?? '—';

String _regrips(SolveAnalysis? analysis) {
  if (analysis == null) return '—';
  final values = analysis.stages.map((stage) => stage.regripCount);
  if (values.any((value) => value == null)) return '—';
  return values.fold<int>(0, (sum, value) => sum + value!).toString();
}

String _protocolName(String? value) => switch (value) {
  'gan' => 'GAN',
  'moyu_ai_2023' => 'MoYu AI 2023',
  'moyu32' => 'MoYu 32',
  'moyu_mhc' => 'MoYu MHC',
  'unknown' || null => 'Not recorded',
  final String value => value.replaceAll('_', ' '),
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day.$month.${local.year} · $hour:$minute';
}
