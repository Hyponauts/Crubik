import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../application/practice_controller.dart';
import '../domain/solve_record.dart';
import 'widgets/practice_panel.dart';
import 'widgets/practice_formatters.dart';
import 'widgets/session_summary_panel.dart';
import 'widgets/solve_analysis_panel.dart';

class SessionSidebar extends StatelessWidget {
  const SessionSidebar({required this.practice, super.key});

  final PracticeController practice;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SessionSummaryPanel(practice: practice),
        const SizedBox(height: 16),
        Expanded(
          child: _RecentSolves(
            practice: practice,
            scrollable: true,
            selectedSolveId: null,
            onSelected: (_) {},
          ),
        ),
      ],
    );
  }
}

class SessionsView extends StatefulWidget {
  const SessionsView({required this.practice, this.mobile = false, super.key});

  final PracticeController practice;
  final bool mobile;

  @override
  State<SessionsView> createState() => _SessionsViewState();
}

class _SessionsViewState extends State<SessionsView> {
  String? _selectedSolveId;

  PracticeController get practice => widget.practice;

  @override
  Widget build(BuildContext context) {
    if (!practice.solves.any((solve) => solve.id == _selectedSolveId)) {
      _selectedSolveId = null;
    }
    if (widget.mobile) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Row(
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
                    label: 'Export',
                  ),
                ],
              ),
              Text(
                practice.selectedSession.name.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CrubikColors.muted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _RecentSolves(
                  practice: practice,
                  scrollable: true,
                  selectedSolveId: _selectedSolveId,
                  onSelected: (id) => setState(() => _selectedSolveId = id),
                ),
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
                  'ANALYZE',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              _SolveExportButton(
                key: const Key('export-solves-button'),
                practice: practice,
                label: 'Copy export',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            practice.selectedSession.name.toUpperCase(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _RecentSolves(
            practice: practice,
            selectedSolveId: _selectedSolveId,
            onSelected: (id) => setState(() => _selectedSolveId = id),
          ),
        ],
      ),
    );
  }
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
      final export = await widget.practice.exportJson();
      await Clipboard.setData(ClipboardData(text: export));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solve history copied as Crubik JSON')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not export solve history. Your local history was not changed.',
          ),
        ),
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
            : const Icon(Icons.copy_all_outlined, size: 18),
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
  });

  final PracticeController practice;
  final String? selectedSolveId;
  final ValueChanged<String?> onSelected;
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
            itemBuilder: (context, index) => _SolveItem(
              practice: practice,
              position: solves.length - index,
              solve: solves[index],
              expanded: solves[index].id == selectedSolveId,
              onSelected: onSelected,
            ),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SolveRow(
          position: position,
          solve: solve,
          expanded: expanded,
          onTap: () => onSelected(expanded ? null : solve.id),
          onDelete: () {
            if (expanded) onSelected(null);
            practice.deleteSolve(solve.id);
          },
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          SizedBox(
            key: const Key('historical-solve-analysis'),
            height: 430,
            child: SolveAnalysisPanel(
              practice: practice,
              solve: solve,
              historical: true,
            ),
          ),
          const SizedBox(height: 8),
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
    required this.expanded,
    required this.onTap,
    required this.onDelete,
  });

  final int position;
  final SolveRecord solve;
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
                    solve.isTimingReliable
                        ? formatPracticeDuration(solve.elapsed)
                        : 'Timing unavailable',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    !solve.isTimingReliable
                        ? '${solve.moveCount} moves · ${solve.inputSource.displayLabel}'
                        : solve.moveCount == 0
                        ? solve.inputSource.displayLabel
                        : '${solve.moveCount} moves · ${solve.turnsPerSecond?.toStringAsFixed(1)} TPS',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: CrubikColors.muted,
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.close, size: 17),
              tooltip: 'Delete solve',
            ),
          ],
        ),
      ),
    );
  }
}
