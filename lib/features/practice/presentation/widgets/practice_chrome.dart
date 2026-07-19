import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class PracticePanel extends StatelessWidget {
  const PracticePanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: CrubikColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CrubikColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class PracticeSectionLabel extends StatelessWidget {
  const PracticeSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: CrubikColors.muted,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.35,
      ),
    );
  }
}

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
