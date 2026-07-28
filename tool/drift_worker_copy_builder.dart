import 'package:build/build.dart';

Builder driftWorkerCopyBuilder(BuilderOptions _) =>
    const _DriftWorkerCopyBuilder();

final class _DriftWorkerCopyBuilder implements Builder {
  const _DriftWorkerCopyBuilder();

  static const _inputPath = 'web/drift_worker_entrypoint.dart.js';
  static const _outputPath = 'web/drift_worker.dart.js';

  @override
  Map<String, List<String>> get buildExtensions => const {
    _inputPath: [_outputPath],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final output = AssetId(buildStep.inputId.package, _outputPath);
    await buildStep.writeAsBytes(
      output,
      await buildStep.readAsBytes(buildStep.inputId),
    );
  }
}
