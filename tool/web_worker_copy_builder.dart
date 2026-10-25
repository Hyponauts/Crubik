import 'package:build/build.dart';

Builder webWorkerCopyBuilder(BuilderOptions _) => const _WebWorkerCopyBuilder();

final class _WebWorkerCopyBuilder implements Builder {
  const _WebWorkerCopyBuilder();

  static const _outputs = {
    'web/drift_worker_entrypoint.dart.js': ['web/drift_worker.dart.js'],
    'web/cube_solver_worker_entrypoint.dart.js': [
      'web/cube_solver_worker.dart.js',
    ],
  };

  @override
  Map<String, List<String>> get buildExtensions => _outputs;

  @override
  Future<void> build(BuildStep buildStep) async {
    final outputPath = _outputs[buildStep.inputId.path]!.single;
    await buildStep.writeAsBytes(
      AssetId(buildStep.inputId.package, outputPath),
      await buildStep.readAsBytes(buildStep.inputId),
    );
  }
}
