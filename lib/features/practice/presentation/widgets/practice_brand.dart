import 'package:flutter/material.dart';

class PracticeBrand extends StatelessWidget {
  const PracticeBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'CRUBIK',
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(letterSpacing: 2.4),
    );
  }
}

class PracticeBrandMark extends StatelessWidget {
  const PracticeBrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Image.asset(
        'web/icons/Icon-192.png',
        width: 38,
        height: 38,
        semanticLabel: 'Crubik app icon',
      ),
    );
  }
}
