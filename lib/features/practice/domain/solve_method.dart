import '../../cube/domain/cube_model.dart';

enum SolveStageKind {
  cross('cross', 'Cross', 'CROSS'),
  f2lPair1('f2l_pair_1', 'F2L pair 1', 'F2L 1'),
  f2lPair2('f2l_pair_2', 'F2L pair 2', 'F2L 2'),
  f2lPair3('f2l_pair_3', 'F2L pair 3', 'F2L 3'),
  f2lPair4('f2l_pair_4', 'F2L pair 4', 'F2L 4'),
  firstLayer('first_layer', 'First layer', 'LAYER 1'),
  secondLayer('second_layer', 'Second layer', 'LAYER 2'),
  lastLayerEdgesOriented('last_layer_edges_oriented', 'Edge orientation', 'EO'),
  lastLayerOriented('last_layer_oriented', 'Last-layer orientation', 'OLL'),
  lastLayerCornersPermuted(
    'last_layer_corners_permuted',
    'Corner permutation',
    'CPLL',
  ),
  solved('solved', 'Solved', 'PLL');

  const SolveStageKind(this.serializedValue, this.label, this.shortLabel);

  final String serializedValue;
  final String label;
  final String shortLabel;

  static SolveStageKind fromSerializedValue(String value) => values.firstWhere(
    (stage) => stage.serializedValue == value,
    orElse: () => throw FormatException('Unknown solve stage: $value'),
  );
}

enum SolveMethodPreset {
  cfop('cfop', 'CFOP'),
  twoLookCfop('two_look_cfop', '2-look CFOP'),
  fourLookCfop('four_look_cfop', '4-look CFOP'),
  layerByLayer('layer_by_layer', 'Layer by Layer'),
  custom('custom', 'Custom');

  const SolveMethodPreset(this.serializedValue, this.label);

  final String serializedValue;
  final String label;

  static SolveMethodPreset fromSerializedValue(String value) =>
      values.firstWhere(
        (method) => method.serializedValue == value,
        orElse: () => throw FormatException('Unknown solve method: $value'),
      );
}

final class SolveMethodConfig {
  SolveMethodConfig({required this.preset, List<SolveStageKind>? customStages})
    : customStages = List.unmodifiable(customStages ?? const []) {
    if (preset == SolveMethodPreset.custom && this.customStages.isEmpty) {
      throw ArgumentError.value(
        customStages,
        'customStages',
        'A custom method must contain at least one stage.',
      );
    }
  }

  factory SolveMethodConfig.preset(SolveMethodPreset preset) =>
      preset == SolveMethodPreset.custom
      ? SolveMethodConfig(preset: preset, customStages: _cfopStages)
      : SolveMethodConfig(preset: preset);

  final SolveMethodPreset preset;
  final List<SolveStageKind> customStages;

  List<SolveStageKind> get stages => switch (preset) {
    SolveMethodPreset.cfop => _cfopStages,
    SolveMethodPreset.twoLookCfop => _twoLookCfopStages,
    SolveMethodPreset.fourLookCfop => _fourLookCfopStages,
    SolveMethodPreset.layerByLayer => _layerByLayerStages,
    SolveMethodPreset.custom => customStages,
  };

  String get displayName => preset.label;

  Map<String, Object?> toJson() => {
    'preset': preset.serializedValue,
    'stages': stages.map((stage) => stage.serializedValue).toList(),
  };

  factory SolveMethodConfig.fromJson(Map<String, Object?> json) {
    final preset = SolveMethodPreset.fromSerializedValue(
      json['preset']! as String,
    );
    final stages = [
      for (final value in (json['stages'] as List<Object?>?) ?? const [])
        SolveStageKind.fromSerializedValue(value! as String),
    ];
    return SolveMethodConfig(
      preset: preset,
      customStages: preset == SolveMethodPreset.custom ? stages : null,
    );
  }

  static const _cfopStages = [
    SolveStageKind.cross,
    SolveStageKind.f2lPair1,
    SolveStageKind.f2lPair2,
    SolveStageKind.f2lPair3,
    SolveStageKind.f2lPair4,
    SolveStageKind.lastLayerOriented,
    SolveStageKind.solved,
  ];

  static const _twoLookCfopStages = [
    SolveStageKind.cross,
    SolveStageKind.f2lPair1,
    SolveStageKind.f2lPair2,
    SolveStageKind.f2lPair3,
    SolveStageKind.f2lPair4,
    SolveStageKind.lastLayerEdgesOriented,
    SolveStageKind.lastLayerOriented,
    SolveStageKind.solved,
  ];

  static const _fourLookCfopStages = [
    SolveStageKind.cross,
    SolveStageKind.f2lPair1,
    SolveStageKind.f2lPair2,
    SolveStageKind.f2lPair3,
    SolveStageKind.f2lPair4,
    SolveStageKind.lastLayerEdgesOriented,
    SolveStageKind.lastLayerOriented,
    SolveStageKind.lastLayerCornersPermuted,
    SolveStageKind.solved,
  ];

  static const _layerByLayerStages = [
    SolveStageKind.cross,
    SolveStageKind.firstLayer,
    SolveStageKind.secondLayer,
    SolveStageKind.lastLayerEdgesOriented,
    SolveStageKind.lastLayerOriented,
    SolveStageKind.lastLayerCornersPermuted,
    SolveStageKind.solved,
  ];
}

final class SolveOrientation {
  const SolveOrientation({this.crossFace = CubeFace.up})
    : assert(
        crossFace == CubeFace.up || crossFace == CubeFace.down,
        'Only opposite U/D cross orientations are currently supported.',
      );

  final CubeFace crossFace;
}

abstract interface class StateDescriptor {
  SolveStageKind get kind;

  bool isAchieved(CubeState state, SolveOrientation orientation);
}

StateDescriptor descriptorFor(SolveStageKind kind) => switch (kind) {
  SolveStageKind.cross => const _CrossDescriptor(),
  SolveStageKind.f2lPair1 => const _F2lCountDescriptor(
    SolveStageKind.f2lPair1,
    1,
  ),
  SolveStageKind.f2lPair2 => const _F2lCountDescriptor(
    SolveStageKind.f2lPair2,
    2,
  ),
  SolveStageKind.f2lPair3 => const _F2lCountDescriptor(
    SolveStageKind.f2lPair3,
    3,
  ),
  SolveStageKind.f2lPair4 => const _F2lCountDescriptor(
    SolveStageKind.f2lPair4,
    4,
  ),
  SolveStageKind.firstLayer => const _FirstLayerDescriptor(),
  SolveStageKind.secondLayer => const _SecondLayerDescriptor(),
  SolveStageKind.lastLayerEdgesOriented =>
    const _LastLayerEdgesOrientedDescriptor(),
  SolveStageKind.lastLayerOriented => const _LastLayerOrientedDescriptor(),
  SolveStageKind.lastLayerCornersPermuted =>
    const _LastLayerCornersPermutedDescriptor(),
  SolveStageKind.solved => const _SolvedDescriptor(),
};

const _solvedFacelets =
    'UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB';

const _upCross = [1, 3, 5, 7, 10, 19, 37, 46];
const _downCross = [28, 30, 32, 34, 16, 25, 43, 52];
const _upCorners = [
  [8, 9, 20],
  [6, 18, 38],
  [0, 36, 47],
  [2, 45, 11],
];
const _downCorners = [
  [29, 26, 15],
  [27, 44, 24],
  [33, 53, 42],
  [35, 17, 51],
];
const _middleEdges = [
  [23, 12],
  [21, 41],
  [50, 39],
  [48, 14],
];

bool _positionsSolved(CubeState state, Iterable<int> positions) {
  final facelets = state.facelets;
  return positions.every(
    (position) => facelets[position] == _solvedFacelets[position],
  );
}

List<List<int>> _firstLayerCorners(SolveOrientation orientation) =>
    orientation.crossFace == CubeFace.up ? _upCorners : _downCorners;

CubeFace _lastLayerFace(SolveOrientation orientation) =>
    orientation.crossFace == CubeFace.up ? CubeFace.down : CubeFace.up;

final class _CrossDescriptor implements StateDescriptor {
  const _CrossDescriptor();

  @override
  SolveStageKind get kind => SolveStageKind.cross;

  @override
  bool isAchieved(CubeState state, SolveOrientation orientation) =>
      _positionsSolved(
        state,
        orientation.crossFace == CubeFace.up ? _upCross : _downCross,
      );
}

final class _F2lCountDescriptor implements StateDescriptor {
  const _F2lCountDescriptor(this.kind, this.requiredCount);

  @override
  final SolveStageKind kind;
  final int requiredCount;

  @override
  bool isAchieved(CubeState state, SolveOrientation orientation) {
    if (!const _CrossDescriptor().isAchieved(state, orientation)) return false;
    final corners = _firstLayerCorners(orientation);
    var solvedCount = 0;
    for (var index = 0; index < corners.length; index++) {
      if (_positionsSolved(state, [
        ...corners[index],
        ..._middleEdges[index],
      ])) {
        solvedCount++;
      }
    }
    return solvedCount >= requiredCount;
  }
}

final class _FirstLayerDescriptor implements StateDescriptor {
  const _FirstLayerDescriptor();

  @override
  SolveStageKind get kind => SolveStageKind.firstLayer;

  @override
  bool isAchieved(CubeState state, SolveOrientation orientation) =>
      const _CrossDescriptor().isAchieved(state, orientation) &&
      _firstLayerCorners(
        orientation,
      ).every((corner) => _positionsSolved(state, corner));
}

final class _SecondLayerDescriptor implements StateDescriptor {
  const _SecondLayerDescriptor();

  @override
  SolveStageKind get kind => SolveStageKind.secondLayer;

  @override
  bool isAchieved(CubeState state, SolveOrientation orientation) =>
      const _FirstLayerDescriptor().isAchieved(state, orientation) &&
      _middleEdges.every((edge) => _positionsSolved(state, edge));
}

final class _LastLayerEdgesOrientedDescriptor implements StateDescriptor {
  const _LastLayerEdgesOrientedDescriptor();

  @override
  SolveStageKind get kind => SolveStageKind.lastLayerEdgesOriented;

  @override
  bool isAchieved(CubeState state, SolveOrientation orientation) {
    if (!const _SecondLayerDescriptor().isAchieved(state, orientation)) {
      return false;
    }
    final colors = state.colorsFor(_lastLayerFace(orientation));
    return [1, 3, 5, 7].every((index) => colors[index] == colors[4]);
  }
}

final class _LastLayerOrientedDescriptor implements StateDescriptor {
  const _LastLayerOrientedDescriptor();

  @override
  SolveStageKind get kind => SolveStageKind.lastLayerOriented;

  @override
  bool isAchieved(CubeState state, SolveOrientation orientation) {
    if (!const _SecondLayerDescriptor().isAchieved(state, orientation)) {
      return false;
    }
    final colors = state.colorsFor(_lastLayerFace(orientation));
    return colors.every((color) => color == colors[4]);
  }
}

final class _LastLayerCornersPermutedDescriptor implements StateDescriptor {
  const _LastLayerCornersPermutedDescriptor();

  @override
  SolveStageKind get kind => SolveStageKind.lastLayerCornersPermuted;

  @override
  bool isAchieved(CubeState state, SolveOrientation orientation) {
    if (!const _LastLayerOrientedDescriptor().isAchieved(state, orientation)) {
      return false;
    }
    final positions = orientation.crossFace == CubeFace.up
        ? _downCorners.expand((corner) => corner)
        : _upCorners.expand((corner) => corner);
    return _positionsSolved(state, positions);
  }
}

final class _SolvedDescriptor implements StateDescriptor {
  const _SolvedDescriptor();

  @override
  SolveStageKind get kind => SolveStageKind.solved;

  @override
  bool isAchieved(CubeState state, SolveOrientation orientation) =>
      state.isSolved;
}
