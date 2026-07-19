import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class PracticeBrand extends StatelessWidget {
  const PracticeBrand({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[const PracticeBrandMark(), const SizedBox(width: 12)],
        Text(
          'CRUBIK',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(letterSpacing: 2.4),
        ),
      ],
    );
  }
}

class PracticeBrandMark extends StatelessWidget {
  const PracticeBrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: CrubikColors.lime,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(
        Icons.view_in_ar_rounded,
        color: CrubikColors.background,
        size: 23,
      ),
    );
  }
}
