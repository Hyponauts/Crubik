import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../application/practice_controller.dart';
import '../domain/solve_analysis.dart';
import '../domain/solve_average.dart';
import '../domain/solve_record.dart';
import 'solve_export_file_stub.dart'
    if (dart.library.io) 'solve_export_file_io.dart'
    as export_file;
import 'widgets/practice_panel.dart';
import 'widgets/practice_formatters.dart';
import 'widgets/solve_analysis_panel.dart';

class SessionsView extends StatefulWidget {
  const SessionsView({required this.practice, this.mobile = false, super.key});

  final PracticeController practice;
  final bool mobile;

  @override
  State<SessionsView> createState() => _SessionsViewState();
}

class _SessionsViewState extends State<SessionsView>
    with SingleTickerProviderStateMixin {
  String? _selectedSolveId;
  final Map<SolveAverageKind, String> _selectedAverageIds = {};
  SolveAverageKind? _selectedKind;
  String? _focusedSolveId;
  final GlobalKey _firstSolveKey = GlobalKey();
  final GlobalKey _focusedSolveKey = GlobalKey();
  final ScrollController _solvesScrollController = ScrollController();
  late final TabController _historyTabs;

  PracticeController get practice => widget.practice;

  @override
  void initState() {
    super.initState();
    _historyTabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _historyTabs.dispose();
    _solvesScrollController.dispose();
    super.dispose();
  }

  void _openSolveFromAverage(String solveId) {
    final index = practice.solves.indexWhere((solve) => solve.id == solveId);
    if (index < 0) return;
    _historyTabs.animateTo(0);
    setState(() {
      _selectedKind = null;
      _selectedSolveId = solveId;
      _focusedSolveId = solveId;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSolve(index));
  }

  void _focusSolve(int index, {bool canResetScroll = true}) {
    if (!mounted || !_solvesScrollController.hasClients) return;
    final firstRow = _firstSolveKey.currentContext?.findRenderObject();
    if (index > 0 && firstRow == null && canResetScroll) {
      _solvesScrollController.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusSolve(index, canResetScroll: false),
      );
      return;
    }
    final rowHeight = firstRow is RenderBox ? firstRow.size.height + 1 : 71.0;
    _solvesScrollController.jumpTo(
      (index * rowHeight).clamp(
        0.0,
        _solvesScrollController.position.maxScrollExtent,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _focusedSolveKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.05,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedSolveId != null &&
        !practice.solves.any((solve) => solve.id == _selectedSolveId)) {
      _selectedSolveId = null;
    }
    for (final kind in SolveAverageKind.values) {
      final selectedId = _selectedAverageIds[kind];
      if (selectedId != null &&
          !practice
              .averagesFor(kind)
              .any((average) => average.id == selectedId)) {
        _selectedAverageIds.remove(kind);
      }
    }
    return SafeArea(
      child: Padding(
        padding: widget.mobile
            ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
            : const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              children: [
                _AnalyzeHeader(
                  practice: practice,
                  exportLabel: widget.mobile
                      ? 'EXPORT SESSION'
                      : 'COPY SESSION JSON',
                ),
                SizedBox(height: widget.mobile ? 10 : 16),
                TabBar(
                  key: const Key('analyze-history-tabs'),
                  controller: _historyTabs,
                  isScrollable: false,
                  onTap: (index) => setState(() {
                    _selectedKind = index == 0
                        ? null
                        : SolveAverageKind.values[index - 1];
                    _selectedSolveId = null;
                    _focusedSolveId = null;
                  }),
                  tabs: const [
                    Tab(text: 'SINGLE'),
                    Tab(text: 'AO5'),
                    Tab(text: 'AO12'),
                    Tab(text: 'AO100'),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: IndexedStack(
                    index: _selectedKind == null ? 0 : _selectedKind!.index + 1,
                    children: [
                      _RecentSolves(
                        practice: practice,
                        scrollable: true,
                        selectedSolveId: _selectedSolveId,
                        onSelected: (id) => setState(() {
                          _selectedSolveId = id;
                          _focusedSolveId = null;
                        }),
                        scrollController: _solvesScrollController,
                        firstKey: _firstSolveKey,
                        focusSolveId: _focusedSolveId,
                        focusKey: _focusedSolveKey,
                      ),
                      for (final kind in SolveAverageKind.values)
                        _RecentAverages(
                          practice: practice,
                          kind: kind,
                          selectedAverageId: _selectedAverageIds[kind],
                          onSelected: (id) => setState(() {
                            if (id == null) {
                              _selectedAverageIds.remove(kind);
                            } else {
                              _selectedAverageIds[kind] = id;
                            }
                          }),
                          onOpenSolve: _openSolveFromAverage,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentAverages extends StatelessWidget {
  const _RecentAverages({
    required this.practice,
    required this.kind,
    required this.selectedAverageId,
    required this.onSelected,
    required this.onOpenSolve,
  });

  final PracticeController practice;
  final SolveAverageKind kind;
  final String? selectedAverageId;
  final ValueChanged<String?> onSelected;
  final ValueChanged<String> onOpenSolve;

  @override
  Widget build(BuildContext context) {
    final averages = practice.averagesFor(kind);
    return PracticePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PracticeSectionLabel(kind.label),
              const Spacer(),
              Text(
                '${averages.length} TOTAL',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: averages.isEmpty
                ? Center(
                    child: Text(
                      'Complete ${kind.windowSize} solves to see the first ${kind.label}.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    key: Key('average-history-${kind.name}'),
                    itemCount: averages.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final average = averages[index];
                      final expanded = selectedAverageId == average.id;
                      return Column(
                        children: [
                          InkWell(
                            key: Key('average-row-${average.id}'),
                            onTap: () =>
                                onSelected(expanded ? null : average.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    expanded
                                        ? Icons.keyboard_arrow_down
                                        : Icons.keyboard_arrow_right,
                                    size: 18,
                                    color: CrubikColors.muted,
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 42,
                                    child: Text('#${averages.length - index}'),
                                  ),
                                  Expanded(
                                    child: Text(
                                      formatSolveDateTime(average.createdAt),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    formatAverageResult(average),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (expanded)
                            SizedBox(
                              height: 360,
                              child: AverageAnalysisPanel(
                                key: Key('average-detail-${average.id}'),
                                practice: practice,
                                average: average,
                                onOpenSolve: onOpenSolve,
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

class _AnalyzeHeader extends StatelessWidget {
  const _AnalyzeHeader({required this.practice, required this.exportLabel});

  final PracticeController practice;
  final String exportLabel;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Text(
          'ANALYZE',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
      _SolveExportButton(
        key: const Key('export-solves-button'),
        practice: practice,
        label: exportLabel,
      ),
    ],
  );
}

class _SolveExportButton extends StatefulWidget {
  const _SolveExportButton({
    required this.practice,
    required this.label,
    super.key,
  });

  final PracticeController practice;
  final String label;

  @override
  State<_SolveExportButton> createState() => _SolveExportButtonState();
}

class _SolveExportButtonState extends State<_SolveExportButton> {
  bool _isExporting = false;

  Future<void> _copyExport() async {
    if (_isExporting || !widget.practice.hasSolves) return;
    setState(() => _isExporting = true);
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final saved = await export_file.saveSolveExportFile(widget.practice);
        if (!mounted || !saved) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session history saved as Crubik JSON')),
        );
        return;
      }

      final export = await widget.practice.exportJson();
      await Clipboard.setData(ClipboardData(text: export));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session history copied as Crubik JSON')),
      );
    } catch (error) {
      if (!mounted) return;
      final reason = switch (error) {
        PlatformException(code: 'export_picker_failed') =>
          'Could not open the Android file picker.',
        PlatformException(code: 'export_destination_failed') =>
          'Could not write to that location. Try saving to Downloads.',
        PlatformException(code: 'export_prepare_failed') =>
          'Could not prepare the export file. Check available storage.',
        _ => 'Could not export the session.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$reason Your local history was not changed.')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: _isExporting,
      label: _isExporting ? 'Exporting solve history' : null,
      child: OutlinedButton.icon(
        onPressed: widget.practice.hasSolves && !_isExporting
            ? _copyExport
            : null,
        icon: _isExporting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                    ? Icons.file_download_outlined
                    : Icons.copy_all_outlined,
                size: 18,
              ),
        label: Text(_isExporting ? 'Exporting…' : widget.label),
      ),
    );
  }
}

class _RecentSolves extends StatelessWidget {
  const _RecentSolves({
    required this.practice,
    required this.selectedSolveId,
    required this.onSelected,
    this.scrollable = false,
    this.scrollController,
    this.firstKey,
    this.focusSolveId,
    this.focusKey,
  });

  final PracticeController practice;
  final String? selectedSolveId;
  final ValueChanged<String?> onSelected;
  final bool scrollable;
  final ScrollController? scrollController;
  final GlobalKey? firstKey;
  final String? focusSolveId;
  final GlobalKey? focusKey;

  @override
  Widget build(BuildContext context) {
    final solves = practice.solves;
    final list = solves.isEmpty
        ? const _EmptySolves()
        : ListView.separated(
            key: const Key('recent-solves-list'),
            controller: scrollController,
            padding: EdgeInsets.zero,
            itemCount: solves.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final solve = solves[index];
              final item = _SolveItem(
                practice: practice,
                position: solves.length - index,
                solve: solve,
                expanded: solve.id == selectedSolveId,
                onSelected: onSelected,
              );
              if (index == 0 && firstKey != null && solve.id != focusSolveId) {
                return KeyedSubtree(key: firstKey, child: item);
              }
              return solve.id == focusSolveId && focusKey != null
                  ? KeyedSubtree(key: focusKey, child: item)
                  : item;
            },
          );
    return PracticePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PracticeSectionLabel('SOLVES'),
              const Spacer(),
              Text(
                '${practice.solves.length} TOTAL',
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
              _SolveItem(
                practice: practice,
                position: solves.length - index,
                solve: solves[index],
                expanded: solves[index].id == selectedSolveId,
                onSelected: onSelected,
              ),
              if (index != solves.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _SolveItem extends StatelessWidget {
  const _SolveItem({
    required this.practice,
    required this.position,
    required this.solve,
    required this.expanded,
    required this.onSelected,
  });

  final PracticeController practice;
  final int position;
  final SolveRecord solve;
  final bool expanded;
  final ValueChanged<String?> onSelected;

  Future<void> _deleteSolve(BuildContext context) async {
    final shouldDelete = await confirmSolveDeletion(context, solve);
    if (!context.mounted || !shouldDelete) return;
    if (expanded) onSelected(null);
    practice.deleteSolve(solve.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SolveRow(
          position: position,
          solve: solve,
          analysis: practice.analysisForCached(solve.id),
          expanded: expanded,
          onTap: () => onSelected(expanded ? null : solve.id),
          onDelete: () => unawaited(_deleteSolve(context)),
        ),
        if (expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: SizedBox(
              key: const Key('historical-solve-analysis'),
              height: 360,
              child: SolveAnalysisPanel(
                practice: practice,
                solve: solve,
                historical: true,
                embedded: true,
              ),
            ),
          ),
        ],
      ],
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
    required this.analysis,
    required this.expanded,
    required this.onTap,
    required this.onDelete,
  });

  final int position;
  final SolveRecord solve;
  final SolveAnalysis? analysis;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('solve-row-${solve.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
              key: Key('solve-expand-${solve.id}'),
              size: 18,
              color: CrubikColors.muted,
            ),
            const SizedBox(width: 4),
            SizedBox(
              key: Key('solve-position-${solve.id}'),
              width: 36,
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
                    formatSolveDateTime(solve.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: CrubikColors.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatSolveResult(
                      solve,
                      unavailableLabel: 'Timing unavailable',
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _SolveMetric(
              label: 'TURNS',
              value: solve.turnCountFor(analysis).toString(),
            ),
            const SizedBox(width: 10),
            _SolveMetric(
              label: 'TPS',
              value:
                  solve.turnsPerSecondFor(analysis)?.toStringAsFixed(1) ?? '—',
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Delete solve',
            ),
          ],
        ),
      ),
    );
  }
}

class _SolveMetric extends StatelessWidget {
  const _SolveMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 38,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: CrubikColors.muted,
            fontSize: 8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
