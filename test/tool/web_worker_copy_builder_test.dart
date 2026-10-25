import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/web_worker_copy_builder.dart';

void main() {
  test(
    'materializes both compiled web workers at their runtime URLs',
    () async {
      final result = await testBuilder(
        webWorkerCopyBuilder(BuilderOptions(const {})),
        const {
          'crubik|web/drift_worker_entrypoint.dart.js': 'drift worker',
          'crubik|web/cube_solver_worker_entrypoint.dart.js': 'solver worker',
        },
        generateFor: const {
          'crubik|web/drift_worker_entrypoint.dart.js',
          'crubik|web/cube_solver_worker_entrypoint.dart.js',
        },
        outputs: const {
          'crubik|web/drift_worker.dart.js': 'drift worker',
          'crubik|web/cube_solver_worker.dart.js': 'solver worker',
        },
        rootPackage: 'crubik',
      );

      expect(result.succeeded, isTrue);
    },
  );
}
