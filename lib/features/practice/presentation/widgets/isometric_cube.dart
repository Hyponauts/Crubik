import 'package:flutter/material.dart';

import '../../../cube/domain/cube_model.dart';

class IsometricCube extends StatelessWidget {
  const IsometricCube({required this.state, super.key, this.dimension = 280});

  final CubeState state;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: dimension,
      child: CustomPaint(painter: _IsometricCubePainter(state)),
    );
  }
}

class _IsometricCubePainter extends CustomPainter {
  _IsometricCubePainter(this.state);

  final CubeState state;

  @override
  void paint(Canvas canvas, Size size) {
    final tile = (size.shortestSide / 5.9).clamp(24.0, 54.0);
    final frontTopLeft = Offset(
      size.width / 2 - tile * 1.5,
      size.height * 0.33,
    );
    final horizontal = Offset(tile, 0);
    final vertical = Offset(0, tile);
    final leftDepth = Offset(-tile * 0.62, -tile * 0.56);
    final rightDepth = Offset(tile * 0.62, -tile * 0.56);

    _paintFace(
      canvas,
      state.colorsFor(CubeFace.up),
      origin: frontTopLeft,
      columnVector: horizontal,
      rowVector: leftDepth,
      indexFor: (row, column) => (2 - row) * 3 + column,
      shade: 1.08,
    );
    _paintFace(
      canvas,
      state.colorsFor(CubeFace.right),
      origin: frontTopLeft + horizontal * 3,
      columnVector: rightDepth,
      rowVector: vertical,
      indexFor: (row, column) => row * 3 + column,
      shade: 0.78,
    );
    _paintFace(
      canvas,
      state.colorsFor(CubeFace.front),
      origin: frontTopLeft,
      columnVector: horizontal,
      rowVector: vertical,
      indexFor: (row, column) => row * 3 + column,
      shade: 0.94,
    );
  }

  void _paintFace(
    Canvas canvas,
    List<StickerColor> colors, {
    required Offset origin,
    required Offset columnVector,
    required Offset rowVector,
    required int Function(int row, int column) indexFor,
    required double shade,
  }) {
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 3; column++) {
        final start =
            origin +
            columnVector * column.toDouble() +
            rowVector * row.toDouble();
        final path =
            Path()
              ..moveTo(start.dx, start.dy)
              ..lineTo(start.dx + columnVector.dx, start.dy + columnVector.dy)
              ..lineTo(
                start.dx + columnVector.dx + rowVector.dx,
                start.dy + columnVector.dy + rowVector.dy,
              )
              ..lineTo(start.dx + rowVector.dx, start.dy + rowVector.dy)
              ..close();

        final color = _stickerColor(colors[indexFor(row, column)], shade);
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF0A0C0E)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
  }

  Color _stickerColor(StickerColor color, double shade) {
    final base = switch (color) {
      StickerColor.white => const Color(0xFFF2F3E9),
      StickerColor.red => const Color(0xFFFF4D5F),
      StickerColor.green => const Color(0xFF52D273),
      StickerColor.yellow => const Color(0xFFFFD83D),
      StickerColor.orange => const Color(0xFFFF8A3D),
      StickerColor.blue => const Color(0xFF4C88FF),
    };
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness * shade).clamp(0.0, 1.0)).toColor();
  }

  @override
  bool shouldRepaint(_IsometricCubePainter oldDelegate) => true;
}
