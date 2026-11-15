import 'solve_method.dart';

const defaultPracticeSessionId = 'speedsolving';

final class PracticeSession {
  PracticeSession({required this.id, required this.name, required this.method})
    : assert(id.isNotEmpty),
      assert(name.trim().isNotEmpty);

  factory PracticeSession.defaultSession() => PracticeSession(
    id: defaultPracticeSessionId,
    name: 'SpeedSolving',
    method: SolveMethodConfig.preset(SolveMethodPreset.cfop),
  );

  final String id;
  final String name;
  final SolveMethodConfig method;

  PracticeSession copyWith({String? name, SolveMethodConfig? method}) =>
      PracticeSession(
        id: id,
        name: name ?? this.name,
        method: method ?? this.method,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'method': method.toJson(),
  };

  factory PracticeSession.fromJson(Map<String, Object?> json) =>
      PracticeSession(
        id: json['id']! as String,
        name: json['name']! as String,
        method: SolveMethodConfig.fromJson(
          json['method']! as Map<String, Object?>,
        ),
      );
}

abstract interface class PracticeSessionStore {
  Future<({List<PracticeSession> sessions, String selectedId})?> load();

  Future<void> save(List<PracticeSession> sessions, String selectedId);
}

final class MemoryPracticeSessionStore implements PracticeSessionStore {
  List<PracticeSession>? _sessions;
  String? _selectedId;

  @override
  Future<({List<PracticeSession> sessions, String selectedId})?> load() async {
    final sessions = _sessions;
    final selectedId = _selectedId;
    if (sessions == null || selectedId == null) return null;
    return (
      sessions: List<PracticeSession>.unmodifiable(sessions),
      selectedId: selectedId,
    );
  }

  @override
  Future<void> save(List<PracticeSession> sessions, String selectedId) async {
    _sessions = List.of(sessions);
    _selectedId = selectedId;
  }
}
