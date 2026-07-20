import 'package:flutter/material.dart';

import '../../../cube/domain/cube_model.dart';
import '../../application/practice_controller.dart';
import 'practice_panel.dart';

class ManualMoveInputPanel extends StatelessWidget {
  const ManualMoveInputPanel({
    required this.practice,
    required this.columns,
    super.key,
  });

  final PracticeController practice;
  final int columns;

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
      key: const Key('manual-move-input'),
      padding: const EdgeInsets.all(9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PracticeSectionLabel('MANUAL MOVE INPUT'),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              mainAxisExtent: 48,
            ),
            itemCount: _moves.length,
            itemBuilder: (context, index) {
              final notation = _moves[index];
              return OutlinedButton(
                key: Key('cube-move-$notation'),
                onPressed: () => practice.applyMove(CubeMove.parse(notation)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    notation,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
