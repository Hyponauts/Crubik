import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../cube/domain/cube_model.dart';
import '../../application/practice_controller.dart';
import 'practice_panel.dart';

Future<void> showManualMovesDialog(
  BuildContext context, {
  required PracticeController practice,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ManualMoveInputPanel(practice: practice),
      ),
    ),
  );
}

class ManualMoveInputPanel extends StatelessWidget {
  const ManualMoveInputPanel({required this.practice, super.key});

  final PracticeController practice;

  static const _moves = [
    'U',
    "U'",
    'R',
    "R'",
    'F',
    "F'",
    'D',
    "D'",
    'L',
    "L'",
    'B',
    "B'",
  ];

  @override
  Widget build(BuildContext context) {
    return PracticePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PracticeSectionLabel('MANUAL MOVE INPUT'),
          const SizedBox(height: 7),
          Text(
            'Use these controls to preview live cube movement without hardware.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CrubikColors.muted),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 580
                  ? 12
                  : constraints.maxWidth < 300
                  ? 3
                  : 6;
              const spacing = 8.0;
              final buttonWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final notation in _moves)
                    SizedBox(
                      width: buttonWidth,
                      child: OutlinedButton(
                        key: Key('cube-move-$notation'),
                        onPressed: () =>
                            practice.applyMove(CubeMove.parse(notation)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: CrubikColors.text,
                          side: const BorderSide(color: CrubikColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          notation,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
