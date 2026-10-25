abstract interface class CuberSolverBackend {
  Future<List<String>> solve(
    String facelets, {
    required int maxDepth,
    required Duration timeout,
  });

  void restart();

  void dispose();
}
