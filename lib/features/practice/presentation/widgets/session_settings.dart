import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/practice_controller.dart';
import '../../domain/solve_method.dart';

class PracticeSessionButton extends StatelessWidget {
  const PracticeSessionButton({
    required this.practice,
    this.compact = false,
    super.key,
  });

  final PracticeController practice;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('session-settings-button'),
      onPressed: practice.canConfigureSession
          ? () => showPracticeSessionDialog(context, practice: practice)
          : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: CrubikColors.text,
        side: const BorderSide(color: CrubikColors.border),
        backgroundColor: CrubikColors.surface,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: 11,
        ),
      ),
      icon: const Icon(Icons.settings_outlined, size: 18),
      label: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 104 : 180),
        child: Text(
          practice.selectedSession.name.toUpperCase(),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

Future<void> showPracticeSessionDialog(
  BuildContext context, {
  required PracticeController practice,
}) => showDialog<void>(
  context: context,
  builder: (context) => _PracticeSessionDialog(practice: practice),
);

class _PracticeSessionDialog extends StatefulWidget {
  const _PracticeSessionDialog({required this.practice});

  final PracticeController practice;

  @override
  State<_PracticeSessionDialog> createState() => _PracticeSessionDialogState();
}

class _PracticeSessionDialogState extends State<_PracticeSessionDialog> {
  late final TextEditingController _nameController;
  String? _editingSessionId;

  PracticeController get practice => widget.practice;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    practice.addListener(_handlePracticeChanged);
    _syncName();
  }

  @override
  void dispose() {
    practice.removeListener(_handlePracticeChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _handlePracticeChanged() {
    if (!mounted) return;
    _syncName();
    setState(() {});
  }

  void _syncName() {
    final session = practice.selectedSession;
    if (_editingSessionId == session.id) return;
    _editingSessionId = session.id;
    _nameController.text = session.name;
  }

  @override
  Widget build(BuildContext context) {
    final session = practice.selectedSession;
    final method = session.method;
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      backgroundColor: CrubikColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: CrubikColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, color: CrubikColors.primaryAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'SESSION SETTINGS',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close session settings',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _FieldLabel('SESSION'),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const Key('session-selector'),
                      isExpanded: true,
                      initialValue: session.id,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final item in practice.sessions)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) practice.selectSession(id);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    key: const Key('create-session-button'),
                    onPressed: _createSession,
                    icon: const Icon(Icons.add),
                    tooltip: 'Create session',
                  ),
                  const SizedBox(width: 4),
                  IconButton.outlined(
                    key: const Key('delete-session-button'),
                    onPressed: practice.sessions.length > 1
                        ? _deleteSession
                        : null,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete session',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _FieldLabel('NAME'),
              const SizedBox(height: 7),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (name) =>
                    practice.updateSelectedSession(name: name),
                onTapOutside: (_) =>
                    practice.updateSelectedSession(name: _nameController.text),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('SOLVE METHOD'),
              const SizedBox(height: 7),
              DropdownButtonFormField<SolveMethodPreset>(
                key: const Key('solve-method-selector'),
                isExpanded: true,
                initialValue: method.preset,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final preset in SolveMethodPreset.values)
                    DropdownMenuItem(value: preset, child: Text(preset.label)),
                ],
                onChanged: (preset) {
                  if (preset == null) return;
                  practice.updateSelectedSession(
                    method: SolveMethodConfig.preset(preset),
                  );
                },
              ),
              if (method.preset == SolveMethodPreset.custom) ...[
                const SizedBox(height: 14),
                Flexible(
                  child: _CustomStagesEditor(
                    stages: method.stages,
                    onChanged: (stages) => practice.updateSelectedSession(
                      method: SolveMethodConfig(
                        preset: SolveMethodPreset.custom,
                        customStages: stages,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createSession() async {
    final controller = TextEditingController(text: 'New session');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('CREATE SESSION'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'NAME'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    practice.createSession(name: name);
  }

  Future<void> _deleteSession() async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DELETE SESSION?'),
        content: Text(
          'This removes “${practice.selectedSession.name}” and all of its solves.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: CrubikColors.danger),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (delete == true) practice.deleteSelectedSession();
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: CrubikColors.muted,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    ),
  );
}

class _CustomStagesEditor extends StatelessWidget {
  const _CustomStagesEditor({required this.stages, required this.onChanged});

  final List<SolveStageKind> stages;
  final ValueChanged<List<SolveStageKind>> onChanged;

  @override
  Widget build(BuildContext context) {
    final available = SolveStageKind.values
        .where((stage) => !stages.contains(stage))
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _FieldLabel('STAGES')),
            PopupMenuButton<SolveStageKind>(
              enabled: available.isNotEmpty,
              tooltip: 'Add stage',
              onSelected: (stage) => onChanged([...stages, stage]),
              itemBuilder: (context) => [
                for (final stage in available)
                  PopupMenuItem(value: stage, child: Text(stage.label)),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text('ADD STAGE'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Flexible(
          child: ReorderableListView.builder(
            shrinkWrap: true,
            itemCount: stages.length,
            onReorderItem: (oldIndex, newIndex) {
              final reordered = List<SolveStageKind>.of(stages);
              final stage = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, stage);
              onChanged(reordered);
            },
            itemBuilder: (context, index) {
              final stage = stages[index];
              return ListTile(
                key: ValueKey(stage),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.drag_handle, size: 18),
                title: Text(stage.label),
                trailing: IconButton(
                  onPressed: stages.length > 1
                      ? () => onChanged(
                          stages.where((item) => item != stage).toList(),
                        )
                      : null,
                  icon: const Icon(Icons.close, size: 17),
                  tooltip: 'Remove ${stage.label}',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
