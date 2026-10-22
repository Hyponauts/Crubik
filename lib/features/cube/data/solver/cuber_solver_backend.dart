import 'cuber_solver_backend_contract.dart';
import 'cuber_solver_backend_native.dart'
    if (dart.library.js_interop) 'cuber_solver_backend_web.dart'
    as platform;

export 'cuber_solver_backend_contract.dart';

CuberSolverBackend createCuberSolverBackend() =>
    platform.createCuberSolverBackend();
