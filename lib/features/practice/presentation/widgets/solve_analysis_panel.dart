import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/practice_controller.dart';
import '../../domain/solve_analysis.dart';
import '../../domain/solve_average.dart';
import '../../domain/solve_method.dart';
import '../../domain/solve_record.dart';
import 'practice_formatters.dart';
import 'practice_panel.dart';

const _recognitionColor = Color(0xFFC0AAEC);
const _executionColor = Color(0xFF62C7D4);
const _tpsColor = Color(0xFF79CFA8);
final _averageRecognitionColor = _averageColor(_recognitionColor);
final _averageExecutionColor = _averageColor(_executionColor);

Color _averageColor(Color color) {
  final hsv = HSVColor.fromColor(color);
  return hsv.withHue((hsv.hue + 10) % 360).withAlpha(0.5).toColor();
}

class SolveAnalysisPanel extends StatefulWidget {
  const SolveAnalysisPanel({
    required this.practice,
    required this.solve,
    this.historical = false,
    this.embedded = false,
    this.onContinue,
    super.key,
  });

  final PracticeController practice;
  final SolveRecord solve;
  final bool historical;
  final bool embedded;
  final VoidCallback? onContinue;

  @override
  State<SolveAnalysisPanel> createState() => _SolveAnalysisPanelState();
}

class _SolveAnalysisPanelState extends State<SolveAnalysisPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  SolveAnalysis? _analysis;
  Map<SolveStageKind, SolveStageTimingAverage> _stageAverages = const {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _loadAnalysis();
    _loadStageAverages();
  }

  @override
  void didUpdateWidget(covariant SolveAnalysisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.solve.id != widget.solve.id) {
      _analysis = null;
      _stageAverages = const {};
      _tabs.index = 0;
      _loadAnalysis();
      _loadStageAverages();
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

  void _loadStageAverages() {
    final solveId = widget.solve.id;
    unawaited(
      widget.practice
          .stageTimingAverages(
            sessionId: widget.solve.sessionId,
            method: widget.solve.method,
          )
          .then((averages) {
            if (mounted && widget.solve.id == solveId) {
              setState(() => _stageAverages = averages);
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
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          _SolveSummary(
            solve: solve,
            analysis: analysis,
            historical: widget.historical,
            onDelete: () => unawaited(_deleteSolve()),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: CrubikColors.border),
        ],
        _AnalysisTabBar(
          controller: _tabs,
          labels: const [
            'OVERVIEW',
            'STEPS',
            'SOLUTION',
            'STATS',
            'TPS',
            'INFO',
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(analysis: analysis, stageAverages: _stageAverages),
              _StepsTab(analysis: analysis),
              _SolutionTab(analysis: analysis),
              _StatsTab(solve: solve, analysis: analysis),
              _TpsTab(analysis: analysis, stageAverages: _stageAverages),
              _InfoTab(solve: solve, analysis: analysis),
            ],
          ),
        ),
        if (widget.onContinue != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('continue-after-solve'),
              onPressed: widget.onContinue,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('DISMISS'),
            ),
          ),
        ],
      ],
    );
    if (widget.embedded) {
      return KeyedSubtree(
        key: const Key('solve-analysis-panel'),
        child: content,
      );
    }
    final horizontalPadding =
        MediaQuery.sizeOf(context).width >= CrubikLayout.desktopBreakpoint
        ? 18.0
        : 12.0;
    return PracticePanel(
      key: const Key('solve-analysis-panel'),
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 8),
      child: content,
    );
  }
}

class _AnalysisTabLabel extends StatelessWidget {
  const _AnalysisTabLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Tab(height: 38, child: Text(label, maxLines: 1, softWrap: false));
}

class _AnalysisTabBar extends StatelessWidget {
  const _AnalysisTabBar({required this.labels, this.controller});

  final TabController? controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    );
    return SizedBox(
      height: 40,
      child: TabBar(
        controller: controller,
        dividerColor: CrubikColors.border,
        labelColor: CrubikColors.text,
        unselectedLabelColor: CrubikColors.muted,
        labelPadding: const EdgeInsets.symmetric(horizontal: 1),
        labelStyle: style,
        unselectedLabelStyle: style,
        tabs: [for (final label in labels) _AnalysisTabLabel(label)],
      ),
    );
  }
}

class AverageAnalysisPanel extends StatefulWidget {
  const AverageAnalysisPanel({
    required this.practice,
    required this.average,
    required this.onOpenSolve,
    super.key,
  });

  final PracticeController practice;
  final SolveAverageRecord average;
  final ValueChanged<String> onOpenSolve;

  @override
  State<AverageAnalysisPanel> createState() => _AverageAnalysisPanelState();
}

class _AverageAnalysisPanelState extends State<AverageAnalysisPanel> {
  late Future<SolveAverageDetails?> _details;

  @override
  void initState() {
    super.initState();
    _details = widget.practice.detailsForAverage(widget.average);
  }

  @override
  void didUpdateWidget(covariant AverageAnalysisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recalculating a window replaces its record even when the anchor and time stay the same.
    if (!identical(oldWidget.average, widget.average)) {
      _details = widget.practice.detailsForAverage(widget.average);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 6,
    child: Column(
      children: [
        const _AnalysisTabBar(
          labels: ['OVERVIEW', 'STEPS', 'STATS', 'TPS', 'SOLVES', 'INFO'],
        ),
        Expanded(
          child: FutureBuilder<SolveAverageDetails?>(
            future: _details,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final details = snapshot.data;
              return TabBarView(
                children: [
                  _AverageOverview(details: details),
                  _AverageSteps(details: details),
                  _AverageStats(details: details, average: widget.average),
                  _AverageTps(details: details),
                  _AverageSolves(
                    window: widget.practice.windowForAverage(widget.average),
                    sessionSolves: widget.practice.solves,
                    onOpenSolve: widget.onOpenSolve,
                  ),
                  _AverageInfo(details: details, average: widget.average),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _AverageSolves extends StatelessWidget {
  const _AverageSolves({
    required this.window,
    required this.sessionSolves,
    required this.onOpenSolve,
  });

  final SolveAverageWindow? window;
  final List<SolveRecord> sessionSolves;
  final ValueChanged<String> onOpenSolve;

  @override
  Widget build(BuildContext context) {
    final window = this.window;
    if (window == null) {
      return const Center(child: Text('SOLVES UNAVAILABLE'));
    }
    final bestIds = window.excludedBest.map((solve) => solve.id).toSet();
    final worstIds = window.excludedWorst.map((solve) => solve.id).toSet();
    return ListView.separated(
      key: const Key('average-member-solves'),
      itemCount: window.solves.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final solve = window.solves[index];
        final isBest = bestIds.contains(solve.id);
        final isWorst = worstIds.contains(solve.id);
        final position =
            sessionSolves.length -
            sessionSolves.indexWhere((item) => item.id == solve.id);
        final status = isBest
            ? 'BEST OUT'
            : isWorst
            ? 'WORST OUT'
            : null;
        final statusColor = isBest
            ? CrubikColors.primaryAccent
            : CrubikColors.danger;
        final time = formatSolveResult(solve);
        return InkWell(
          key: Key('average-member-${solve.id}'),
          onTap: () => onOpenSolve(solve.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
            color: status == null ? null : statusColor.withValues(alpha: 0.12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '#$position · ${formatSolveDateTime(solve.createdAt, includeYear: false)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (status != null) ...[
                  Text(
                    status,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(time),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AverageOverview extends StatelessWidget {
  const _AverageOverview({required this.details});

  final SolveAverageDetails? details;

  @override
  Widget build(BuildContext context) {
    final stages = details?.stages ?? const <SolveAverageStage>[];
    if (stages.isEmpty) {
      return const Center(child: Text('STAGE DATA UNAVAILABLE'));
    }
    final maximum = stages
        .map(
          (stage) =>
              (stage.recognitionTime?.inMicroseconds ?? 0) +
              (stage.executionTime?.inMicroseconds ?? 0),
        )
        .reduce(math.max);
    final axis = _ChartAxis.forMaximum(maximum / 1000000);
    return _StageColumnChart(
      axis: axis,
      suffix: 's',
      legend: const _ChartLegend(
        items: [
          (color: _recognitionColor, label: 'Recognition'),
          (color: _executionColor, label: 'Execution'),
        ],
      ),
      columns: [
        for (final stage in stages)
          _ChartStageColumn(
            shortLabel: stage.kind.shortLabel,
            tooltip:
                '${stage.kind.label}\nRecognition ${_preciseDuration(stage.recognitionTime)}\nExecution ${_preciseDuration(stage.executionTime)}\n${stage.sampleCount} solves',
            barBuilder: (height) => _StackedTimingBar(
              recognitionMicroseconds:
                  stage.recognitionTime?.inMicroseconds ?? 0,
              executionMicroseconds: stage.executionTime?.inMicroseconds ?? 0,
              maximumMicroseconds: axis.maximum * 1000000,
              availableHeight: height,
              width: 18,
              recognitionColor: _recognitionColor,
              executionColor: _executionColor,
              showBorder: true,
            ),
          ),
      ],
    );
  }
}

class _AverageSteps extends StatelessWidget {
  const _AverageSteps({required this.details});

  final SolveAverageDetails? details;

  @override
  Widget build(BuildContext context) {
    final stages = details?.stages ?? const <SolveAverageStage>[];
    if (stages.isEmpty) {
      return const Center(child: Text('STAGE DATA UNAVAILABLE'));
    }
    return _StageMetricsTable(
      rows: [
        for (final stage in stages)
          _StageMetricRow(
            label: stage.kind.label,
            shortLabel: stage.kind.shortLabel,
            recognition: stage.recognitionTime,
            execution: stage.executionTime,
            stepTime: stage.stepTime,
            turns: stage.turns,
            tps: stage.turnsPerSecond,
            regrips: stage.regrips,
          ),
      ],
    );
  }
}

class _AverageStats extends StatelessWidget {
  const _AverageStats({required this.details, required this.average});

  final SolveAverageDetails? details;
  final SolveAverageRecord average;

  @override
  Widget build(BuildContext context) {
    final metrics = details?.metrics;
    return _StatsGrid(
      values: [
        (
          Icons.visibility_outlined,
          'INSPECTION',
          _duration(metrics?.inspectionTime),
        ),
        (
          Icons.timer_outlined,
          'SOLVING TIME',
          switch (average.status) {
            SolveAverageStatus.completed => _duration(average.elapsed),
            SolveAverageStatus.dnf => 'DNF',
            SolveAverageStatus.unavailable => '—',
          },
        ),
        (
          Icons.psychology_outlined,
          'RECOGNITION',
          _duration(metrics?.recognitionTime),
        ),
        (
          Icons.touch_app_outlined,
          'EXECUTION',
          _duration(metrics?.executionTime),
        ),
        (Icons.sync_alt, 'TURNS', _decimal(metrics?.turns)),
        (Icons.speed, 'TPS', _decimal(metrics?.turnsPerSecond)),
        (
          Icons.fast_forward_outlined,
          'STEPS SKIPPED',
          _decimal(metrics?.skippedStages),
        ),
        (
          Icons.rotate_90_degrees_ccw_outlined,
          'REGRIPS',
          _decimal(metrics?.regrips),
        ),
      ],
    );
  }
}

class _AverageTps extends StatelessWidget {
  const _AverageTps({required this.details});

  final SolveAverageDetails? details;

  @override
  Widget build(BuildContext context) {
    final stages = details?.stages ?? const <SolveAverageStage>[];
    if (stages.isEmpty) {
      return const Center(child: Text('STAGE DATA UNAVAILABLE'));
    }
    return _StageTpsChart(
      stages: [
        for (final stage in stages)
          (
            label: stage.kind.label,
            shortLabel: stage.kind.shortLabel,
            value: stage.turnsPerSecond,
            average: null,
          ),
      ],
    );
  }
}

class _AverageInfo extends StatelessWidget {
  const _AverageInfo({required this.details, required this.average});

  final SolveAverageDetails? details;
  final SolveAverageRecord average;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      _AverageInfoRow('RESULT', formatAverageResult(average)),
      _AverageInfoRow('WINDOW', '${average.kind.windowSize} SOLVES'),
      _AverageInfoRow(
        'TRIMMED',
        '${average.kind.trimCount} BEST + ${average.kind.trimCount} WORST',
      ),
      _AverageInfoRow(
        'SAME METHOD',
        details == null ? '—' : '${details!.eligibleSolveCount} SOLVES',
      ),
      _AverageInfoRow('LAST SOLVE', formatSolveDateTime(average.createdAt)),
    ],
  );
}

class _AverageInfoRow extends StatelessWidget {
  const _AverageInfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      ListTile(dense: true, title: Text(label), trailing: Text(value));
}

class _SolveSummary extends StatelessWidget {
  const _SolveSummary({
    required this.solve,
    required this.analysis,
    required this.historical,
    required this.onDelete,
  });

  final SolveRecord solve;
  final SolveAnalysis? analysis;
  final bool historical;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: !historical,
      label: historical
          ? 'Solve from ${formatSolveDateTime(solve.createdAt)}'
          : 'Solve complete. Time ${formatSolveResult(solve, unavailableLabel: 'unavailable')}. '
                '${solve.turnCountFor(analysis)} turns. TPS ${solve.turnsPerSecondFor(analysis)?.toStringAsFixed(1) ?? 'unavailable'}.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 18,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        historical
                            ? formatSolveDateTime(solve.createdAt).toUpperCase()
                            : 'SOLVE COMPLETE',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: CrubikColors.primaryAccent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatSolveResult(
                          solve,
                          unavailableLabel: 'Timing unavailable',
                        ),
                        key: const Key('finish-time'),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              fontSize: 34,
                            ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SummaryMetric(
            icon: Icons.speed,
            label: 'TPS',
            value: solve.turnsPerSecondFor(analysis)?.toStringAsFixed(1) ?? '—',
            valueKey: const Key('finish-tps'),
          ),
          const SizedBox(width: 8),
          _SummaryMetric(
            icon: Icons.sync_alt,
            label: 'TURNS',
            value: solve.turnCountFor(analysis).toString(),
            valueKey: const Key('finish-moves'),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('delete-solve-button'),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Delete solve',
          ),
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
      width: 48,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 11, color: CrubikColors.muted),
                  const SizedBox(width: 3),
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
          ),
          SizedBox(
            height: 44,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  key: valueKey,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
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
      title: const Text('Delete solve?'),
      content: Text(
        'Delete ${formatSolveResult(solve, unavailableLabel: 'a solve with unavailable timing')} from ${formatSolveDateTime(solve.createdAt)}? This cannot be undone.',
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
  const _OverviewTab({required this.analysis, required this.stageAverages});

  final SolveAnalysis? analysis;
  final Map<SolveStageKind, SolveStageTimingAverage> stageAverages;

  @override
  Widget build(BuildContext context) {
    final analysis = this.analysis;
    if (analysis == null || analysis.stages.isEmpty) {
      return _AnalysisUnavailable(analysis: analysis);
    }
    final maximumMicroseconds = analysis.stages
        .map(
          (stage) => [
            stage.stepTime?.inMicroseconds ?? 0,
            stageAverages[stage.kind]?.stepTime?.inMicroseconds ?? 0,
          ].reduce((current, value) => value > current ? value : current),
        )
        .fold<int>(1, (current, value) => value > current ? value : current);
    final axis = _ChartAxis.forMaximum(
      maximumMicroseconds / Duration.microsecondsPerSecond,
    );
    return _StageColumnChart(
      axis: axis,
      axisKey: const Key('overview-axis'),
      suffix: 's',
      legend: _ChartLegend(
        items: [
          (color: _recognitionColor, label: 'Recognition'),
          (color: _executionColor, label: 'Execution'),
          (color: _averageRecognitionColor, label: 'Recognition Ao100'),
          (color: _averageExecutionColor, label: 'Execution Ao100'),
        ],
      ),
      columns: [
        for (final stage in analysis.stages)
          _StageBar(
            stage: stage,
            average: stageAverages[stage.kind],
            maximumMicroseconds: axis.maximum * Duration.microsecondsPerSecond,
          ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.items});

  final List<({Color color, String label})> items;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: 10,
    runSpacing: 3,
    children: [
      for (final item in items)
        _LegendItem(color: item.color, label: item.label),
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

final class _ChartAxis {
  const _ChartAxis({required this.maximum, required this.step});

  factory _ChartAxis.forMaximum(double value) {
    final desiredStep = math.max(1.0, value / 6);
    var magnitude = 1;
    while (desiredStep > magnitude * 10) {
      magnitude *= 10;
    }
    final step = [1, 2, 5, 10]
        .map((factor) => factor * magnitude)
        .firstWhere((candidate) => candidate >= desiredStep);
    return _ChartAxis(
      maximum: step * math.max(3, (value / step).ceil()),
      step: step,
    );
  }

  final int maximum;
  final int step;

  int get tickCount => maximum ~/ step;
}

class _ChartScale extends StatelessWidget {
  const _ChartScale({
    required this.axis,
    required this.suffix,
    required this.bottomPadding,
    super.key,
  });

  final _ChartAxis axis;
  final String suffix;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: CrubikColors.muted,
      fontSize: 9,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SizedBox(
      width: 30,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var value = axis.maximum; value >= 0; value -= axis.step)
              Text('$value$suffix', style: style),
          ],
        ),
      ),
    );
  }
}

class _ChartGridPainter extends CustomPainter {
  const _ChartGridPainter({
    required this.tickCount,
    required this.bottomPadding,
  });

  final int tickCount;
  final double bottomPadding;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CrubikColors.border
      ..strokeWidth = 1;
    final chartHeight = size.height - bottomPadding;
    for (var tick = 0; tick <= tickCount; tick++) {
      final y = chartHeight * tick / tickCount;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartGridPainter oldDelegate) =>
      oldDelegate.tickCount != tickCount ||
      oldDelegate.bottomPadding != bottomPadding;
}

class _StageColumnChart extends StatelessWidget {
  const _StageColumnChart({
    required this.axis,
    required this.suffix,
    required this.legend,
    required this.columns,
    this.axisKey,
  });

  final _ChartAxis axis;
  final String suffix;
  final Widget legend;
  final List<Widget> columns;
  final Key? axisKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
    child: Column(
      children: [
        Align(alignment: Alignment.centerRight, child: legend),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              _ChartScale(
                key: axisKey,
                axis: axis,
                suffix: suffix,
                bottomPadding: 20,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ChartGridPainter(
                          tickCount: axis.tickCount,
                          bottomPadding: 20,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final column in columns) Expanded(child: column),
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

class _ChartStageColumn extends StatelessWidget {
  const _ChartStageColumn({
    required this.shortLabel,
    required this.tooltip,
    required this.barBuilder,
    this.tooltipKey,
  });

  final String shortLabel;
  final String tooltip;
  final Widget Function(double availableHeight) barBuilder;
  final Key? tooltipKey;

  @override
  Widget build(BuildContext context) => Tooltip(
    key: tooltipKey,
    message: tooltip,
    triggerMode: TooltipTriggerMode.tap,
    showDuration: const Duration(seconds: 4),
    child: Semantics(
      button: true,
      label: tooltip.replaceAll('\n', '. '),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.bottomCenter,
                  child: barBuilder(constraints.maxHeight),
                ),
              ),
            ),
            SizedBox(
              height: 20,
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    shortLabel,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: CrubikColors.muted,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StageBar extends StatelessWidget {
  const _StageBar({
    required this.stage,
    required this.average,
    required this.maximumMicroseconds,
  });

  final SolveStageAnalysis stage;
  final SolveStageTimingAverage? average;
  final int maximumMicroseconds;

  @override
  Widget build(BuildContext context) {
    final recognition = stage.recognitionTime?.inMicroseconds ?? 0;
    final execution = stage.executionTime?.inMicroseconds ?? 0;
    final average = this.average;
    final averageRecognition = average?.recognitionTime?.inMicroseconds ?? 0;
    final averageExecution = average?.executionTime?.inMicroseconds ?? 0;
    final tooltip =
        '${stage.kind.label}\n'
        'Step ${_preciseDuration(stage.stepTime)}\n'
        'Recognition ${_preciseDuration(stage.recognitionTime)}\n'
        'Execution ${_preciseDuration(stage.executionTime)}'
        '${average == null ? '' : '\nRecognition Ao100 ${_preciseDuration(average.recognitionTime)}\nExecution Ao100 ${_preciseDuration(average.executionTime)}\n${average.sampleCount} ${average.sampleCount == 1 ? 'solve' : 'solves'}'}';
    return _ChartStageColumn(
      tooltipKey: Key('stage-bar-${stage.kind.serializedValue}'),
      shortLabel: stage.kind.shortLabel,
      tooltip: tooltip,
      barBuilder: (height) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _StackedTimingBar(
            key: Key('stage-current-${stage.kind.serializedValue}'),
            recognitionMicroseconds: recognition,
            executionMicroseconds: execution,
            maximumMicroseconds: maximumMicroseconds,
            availableHeight: height,
            width: 18,
            recognitionColor: _recognitionColor,
            executionColor: _executionColor,
            showBorder: true,
          ),
          if (average != null)
            _StackedTimingBar(
              key: Key('stage-average-${stage.kind.serializedValue}'),
              recognitionMicroseconds: averageRecognition,
              executionMicroseconds: averageExecution,
              maximumMicroseconds: maximumMicroseconds,
              availableHeight: height,
              width: 6,
              recognitionColor: _averageRecognitionColor,
              executionColor: _averageExecutionColor,
              showBorder: false,
            ),
        ],
      ),
    );
  }
}

class _StackedTimingBar extends StatelessWidget {
  const _StackedTimingBar({
    required this.recognitionMicroseconds,
    required this.executionMicroseconds,
    required this.maximumMicroseconds,
    required this.availableHeight,
    required this.width,
    required this.recognitionColor,
    required this.executionColor,
    required this.showBorder,
    super.key,
  });

  final int recognitionMicroseconds;
  final int executionMicroseconds;
  final int maximumMicroseconds;
  final double availableHeight;
  final double width;
  final Color recognitionColor;
  final Color executionColor;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final total = recognitionMicroseconds + executionMicroseconds;
    final height = total == 0
        ? 2.0
        : (availableHeight * total / maximumMicroseconds).clamp(
            2.0,
            availableHeight,
          );
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(showBorder ? 4 : 2),
        ),
        border: showBorder ? Border.all(color: CrubikColors.border) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (executionMicroseconds > 0)
            Expanded(
              flex: executionMicroseconds,
              child: ColoredBox(
                key: const Key('execution-segment'),
                color: executionColor,
              ),
            ),
          if (recognitionMicroseconds > 0)
            Expanded(
              flex: recognitionMicroseconds,
              child: ColoredBox(
                key: const Key('recognition-segment'),
                color: recognitionColor,
              ),
            ),
        ],
      ),
    );
  }
}

class _StepsTab extends StatelessWidget {
  const _StepsTab({required this.analysis});

  final SolveAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final stages = analysis?.stages ?? const <SolveStageAnalysis>[];
    if (stages.isEmpty) return _AnalysisUnavailable(analysis: analysis);
    return _StageMetricsTable(
      includeTotal: true,
      rows: [for (final stage in stages) _StageMetricRow.fromSolve(stage)],
    );
  }
}

class _StageMetricRow {
  const _StageMetricRow({
    required this.label,
    required this.shortLabel,
    required this.recognition,
    required this.execution,
    required this.stepTime,
    required this.turns,
    required this.tps,
    required this.regrips,
    this.totalTime,
    this.skipped = false,
    this.isAverage = true,
  });

  factory _StageMetricRow.fromSolve(SolveStageAnalysis stage) =>
      _StageMetricRow(
        label: stage.kind.label,
        shortLabel: stage.kind.shortLabel,
        recognition: stage.recognitionTime,
        execution: stage.executionTime,
        stepTime: stage.stepTime,
        totalTime: stage.totalTime,
        turns: stage.moves.length.toDouble(),
        tps: stage.turnsPerSecond,
        regrips: stage.regripCount?.toDouble(),
        skipped: stage.skipped,
        isAverage: false,
      );

  final String label;
  final String shortLabel;
  final Duration? recognition;
  final Duration? execution;
  final Duration? stepTime;
  final Duration? totalTime;
  final double turns;
  final double? tps;
  final double? regrips;
  final bool skipped;
  final bool isAverage;
}

class _StageMetricsTable extends StatelessWidget {
  const _StageMetricsTable({required this.rows, this.includeTotal = false});

  final List<_StageMetricRow> rows;
  final bool includeTotal;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 620;
      final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
        color: CrubikColors.muted,
        fontSize: wide ? 10 : 8,
        fontWeight: FontWeight.w700,
      );
      final valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
        fontSize: wide ? 12 : 11,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      final headings = [
        'STEP',
        'RECOG',
        'EXEC',
        'TIME',
        if (includeTotal) 'TOTAL',
        'TURNS',
        'TPS',
        'REGRIP',
      ];
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          Table(
            key: const Key('compact-steps-table'),
            columnWidths: {
              0: FlexColumnWidth(wide ? 2.4 : 1.4),
              for (var index = 1; index < headings.length; index++)
                index: FlexColumnWidth(index >= headings.length - 3 ? 0.8 : 1),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: const TableBorder(
              horizontalInside: BorderSide(color: CrubikColors.border),
              bottom: BorderSide(color: CrubikColors.border),
            ),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: CrubikColors.elevated),
                children: [
                  for (final heading in headings)
                    _StepCell(heading, style: headerStyle),
                ],
              ),
              for (final row in rows)
                TableRow(
                  children: [
                    _StepCell(
                      wide ? row.label.toUpperCase() : row.shortLabel,
                      style: valueStyle?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    _StepCell(
                      row.skipped ? '—' : _shortDuration(row.recognition),
                      style: valueStyle,
                    ),
                    _StepCell(
                      row.skipped ? '—' : _shortDuration(row.execution),
                      style: valueStyle,
                    ),
                    _StepCell(
                      row.skipped ? '—' : _shortDuration(row.stepTime),
                      style: valueStyle,
                    ),
                    if (includeTotal)
                      _StepCell(
                        row.skipped ? '—' : _shortDuration(row.totalTime),
                        style: valueStyle,
                      ),
                    _StepCell(
                      row.skipped
                          ? '—'
                          : row.turns.toStringAsFixed(row.isAverage ? 1 : 0),
                      style: valueStyle,
                    ),
                    _StepCell(
                      row.skipped ? '—' : _decimal(row.tps),
                      style: valueStyle,
                    ),
                    _StepCell(
                      row.skipped
                          ? '—'
                          : row.regrips?.toStringAsFixed(
                                  row.isAverage ? 1 : 0,
                                ) ??
                                '—',
                      style: valueStyle,
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
    },
  );
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
        switch (solve.outcome) {
          SolveOutcome.completed when solve.isTimingReliable =>
            '${formatPracticeDuration(solve.elapsed)}S',
          _ => formatSolveResult(solve),
        },
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
      (Icons.sync_alt, 'TURNS', solve.turnCountFor(analysis).toString()),
      (Icons.speed, 'TPS', _decimal(solve.turnsPerSecondFor(analysis))),
      (
        Icons.fast_forward_outlined,
        'STEPS SKIPPED',
        analysis?.skippedStageCount.toString() ?? '—',
      ),
      (Icons.rotate_90_degrees_ccw_outlined, 'REGRIPS', _regrips(analysis)),
    ];
    return _StatsGrid(values: values);
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.values});

  final List<(IconData, String, String)> values;

  @override
  Widget build(BuildContext context) => GridView.builder(
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

class _TpsTab extends StatelessWidget {
  const _TpsTab({required this.analysis, required this.stageAverages});

  final SolveAnalysis? analysis;
  final Map<SolveStageKind, SolveStageTimingAverage> stageAverages;

  @override
  Widget build(BuildContext context) {
    final analysis = this.analysis;
    if (analysis == null || analysis.stages.isEmpty) {
      return _AnalysisUnavailable(analysis: analysis);
    }
    return _StageTpsChart(
      stages: [
        for (final stage in analysis.stages)
          (
            label: stage.kind.label,
            shortLabel: stage.kind.shortLabel,
            value: stage.turnsPerSecond,
            average: stageAverages[stage.kind]?.turnsPerSecond,
          ),
      ],
      showAverage: true,
    );
  }
}

class _StageTpsChart extends StatelessWidget {
  const _StageTpsChart({required this.stages, this.showAverage = false});

  final List<
    ({String label, String shortLabel, double? value, double? average})
  >
  stages;
  final bool showAverage;

  @override
  Widget build(BuildContext context) {
    final maximum = stages.fold<double>(1, (current, stage) {
      return math.max(current, math.max(stage.value ?? 0, stage.average ?? 0));
    });
    final axis = _ChartAxis.forMaximum(maximum);
    final averageColor = _averageColor(_tpsColor);
    return _StageColumnChart(
      axis: axis,
      axisKey: const Key('tps-axis'),
      suffix: '',
      legend: _ChartLegend(
        items: [
          (color: _tpsColor, label: 'TPS'),
          if (showAverage) (color: averageColor, label: 'TPS Ao100'),
        ],
      ),
      columns: [
        for (final stage in stages)
          _ChartStageColumn(
            tooltipKey: Key('tps-bar-${stage.shortLabel}'),
            shortLabel: stage.shortLabel,
            tooltip:
                '${stage.label}\nTPS ${_decimal(stage.value)}'
                '${stage.average == null ? '' : '\nTPS Ao100 ${_decimal(stage.average)}'}',
            barBuilder: (height) => Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _TpsBar(
                  key: Key('tps-current-${stage.shortLabel}'),
                  value: stage.value ?? 0,
                  maximum: axis.maximum,
                  availableHeight: height,
                  width: 18,
                  color: _tpsColor,
                  showBorder: true,
                ),
                if (stage.average != null)
                  _TpsBar(
                    key: Key('tps-average-${stage.shortLabel}'),
                    value: stage.average!,
                    maximum: axis.maximum,
                    availableHeight: height,
                    width: 6,
                    color: averageColor,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TpsBar extends StatelessWidget {
  const _TpsBar({
    required this.value,
    required this.maximum,
    required this.availableHeight,
    required this.width,
    required this.color,
    this.showBorder = false,
    super.key,
  });

  final double value;
  final int maximum;
  final double availableHeight;
  final double width;
  final Color color;
  final bool showBorder;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: availableHeight * (value / maximum).clamp(0.0, 1.0),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(showBorder ? 4 : 2),
      ),
      border: showBorder ? Border.all(color: CrubikColors.border) : null,
    ),
  );
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.solve, required this.analysis});

  final SolveRecord solve;
  final SolveAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final session = _InfoValue(label: 'SESSION', value: solve.sessionName);
    final method = _InfoValue(label: 'METHOD', value: solve.method.displayName);
    final input = _InfoValue(
      label: 'INPUT',
      value: solve.inputSource.displayLabel,
    );
    final cube = _InfoValue(
      label: 'CUBE',
      value: _protocolName(analysis?.protocolFamily),
    );
    final solved = _InfoValue(
      label: 'SOLVED',
      value: formatSolveDateTime(solve.createdAt),
    );
    final scrambleLabel = Text(
      'SCRAMBLE',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: CrubikColors.muted,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    );
    final copyButton = IconButton(
      key: const Key('copy-completed-scramble'),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: solve.scramble));
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Scramble copied')));
      },
      icon: const Icon(Icons.copy, size: 14),
      tooltip: 'Copy scramble',
    );
    final scrambleText = Text(
      solve.scramble,
      key: const Key('completed-scramble'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: CrubikColors.text,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 300 && constraints.maxWidth >= 420;
        return SingleChildScrollView(
          key: const Key('solve-info-scroll'),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 2 : 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: compact
                  ? [
                      Row(
                        children: [
                          for (final field in [
                            session,
                            method,
                            input,
                            cube,
                          ]) ...[
                            Expanded(child: field),
                            if (field != cube) const SizedBox(width: 8),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(child: solved),
                          scrambleLabel,
                          const SizedBox(width: 4),
                          copyButton,
                        ],
                      ),
                      const SizedBox(height: 3),
                      scrambleText,
                    ]
                  : [
                      Row(
                        children: [
                          Expanded(child: session),
                          const SizedBox(width: 14),
                          Expanded(child: method),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: input),
                          const SizedBox(width: 14),
                          Expanded(child: cube),
                        ],
                      ),
                      const SizedBox(height: 10),
                      solved,
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 7),
                      Row(
                        children: [scrambleLabel, const Spacer(), copyButton],
                      ),
                      scrambleText,
                    ],
            ),
          ),
        );
      },
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
  return '${(value.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3)}s';
}

String _decimal(double? value) => value?.toStringAsFixed(1) ?? '—';

String _regrips(SolveAnalysis? analysis) {
  if (analysis == null || !analysis.isComplete || analysis.stages.isEmpty) {
    return '—';
  }
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
