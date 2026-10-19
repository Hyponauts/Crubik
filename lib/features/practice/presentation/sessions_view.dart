import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../application/practice_controller.dart';
import '../domain/solve_record.dart';
import 'widgets/practice_panel.dart';
import 'widgets/practice_formatters.dart';

class SessionSidebar extends StatelessWidget {
  const SessionSidebar({required this.practice, super.key});

  final PracticeController practice;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PracticePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PracticeSectionLabel('SESSION SNAPSHOT'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatValue(
                      label: 'BEST',
                      value: formatOptionalPracticeDuration(practice.bestTime),
                      accent: CrubikColors.primaryAccent,
                    ),
                  ),
                  Expanded(
                    child: _StatValue(
                      label: 'MEAN',
                      value: formatOptionalPracticeDuration(
                        practice.sessionAverage,
                      ),
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
                      value: formatOptionalPracticeDuration(
                        practice.averageOfFive,
                      ),
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

class SessionsView extends StatelessWidget {
  const SessionsView({required this.practice, this.mobile = false, super.key});

  final PracticeController practice;
  final bool mobile;

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
                  _SolveExportButton(
                    key: const Key('export-solves-button'),
                    practice: practice,
                    label: 'Export',
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
              _SolveExportButton(
                key: const Key('export-solves-button'),
                practice: practice,
                label: 'Copy export',
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

class _MobileStats extends StatelessWidget {
  const _MobileStats({required this.practice});

  final PracticeController practice;

  @override
  Widget build(BuildContext context) {
    return PracticePanel(
      child: Row(
        children: [
          Expanded(
            child: _StatValue(
              label: 'BEST',
              value: formatOptionalPracticeDuration(practice.bestTime),
              accent: CrubikColors.primaryAccent,
            ),
          ),
          Expanded(
            child: _StatValue(
              label: 'MEAN',
              value: formatOptionalPracticeDuration(practice.sessionAverage),
            ),
          ),
          Expanded(
            child: _StatValue(
              label: 'AO5',
              value: formatOptionalPracticeDuration(practice.averageOfFive),
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
    return PracticePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PracticeSectionLabel('RECENT SOLVES'),
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
