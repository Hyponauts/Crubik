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
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: CrubikColors.border),
          SizedBox(
            height: 40,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
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
  });

  final SolveRecord solve;
  final bool historical;
  final VoidCallback? onContinue;

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
          if (onContinue != null) ...[
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('continue-after-solve'),
              onPressed: onContinue,
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'Continue to the next scramble',
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
      width: 48,
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
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final stage in analysis.stages)
            Expanded(
              child: _StageBar(stage: stage, maximumMicroseconds: maximum),
            ),
        ],
      ),
    );
  }
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
    return Padding(
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
                          child: Container(color: CrubikColors.secondaryAccent),
                        ),
                      if (recognition > 0)
                        Expanded(
                          flex: recognition,
                          child: Container(color: CrubikColors.primaryAccent),
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: stages.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final stage = stages[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stage.kind.label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CrubikColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'RECOG ${_duration(stage.recognitionTime)}  ·  EXEC ${_duration(stage.executionTime)}  ·  STEP ${_duration(stage.stepTime)}  ·  TOTAL ${_duration(stage.totalTime)}  ·  ${stage.moves.length} TURNS  ·  ${_decimal(stage.turnsPerSecond)} TPS',
                maxLines: 2,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 22,
            runSpacing: 7,
            children: [
              _InfoValue(label: 'SESSION', value: solve.sessionName),
              _InfoValue(label: 'METHOD', value: solve.method.displayName),
              _InfoValue(label: 'INPUT', value: solve.inputSource.displayLabel),
              _InfoValue(
                label: 'CUBE',
                value: _protocolName(analysis?.protocolFamily),
              ),
              _InfoValue(label: 'SOLVED', value: _formatDate(solve.createdAt)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'SCRAMBLE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CrubikColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
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
      Text(value.toUpperCase(), style: Theme.of(context).textTheme.bodySmall),
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
