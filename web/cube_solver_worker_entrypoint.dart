import 'dart:js_interop';

import 'package:crubik/features/cube/data/solver/cuber_solver_engine.dart';
import 'package:web/web.dart';

void main() {
  final scope = globalContext as DedicatedWorkerGlobalScope;
  scope.onmessage = ((Event event) {
    final data = (event as MessageEvent).data.dartify();
    try {
      if (data is! Map) {
        throw const FormatException('Invalid cube solver request.');
      }
      final facelets = data['facelets'];
      final maxDepth = data['maxDepth'];
      final timeoutMs = data['timeoutMs'];
      if (facelets is! String || maxDepth is! int || timeoutMs is! int) {
        throw const FormatException('Invalid cube solver request.');
      }
      final moves = solveWithCuber(
        facelets,
        maxDepth: maxDepth,
        timeout: Duration(milliseconds: timeoutMs),
      );
      scope.postMessage(<String, Object>{'moves': moves}.jsify());
    } catch (error) {
      scope.postMessage(<String, Object>{'error': error.toString()}.jsify());
    }
  }).toJS;
}
