// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crubik_database.dart';

// ignore_for_file: type=lint
class $SolveEntriesTable extends SolveEntries
    with TableInfo<$SolveEntriesTable, SolveEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SolveEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scrambleMeta = const VerificationMeta(
    'scramble',
  );
  @override
  late final GeneratedColumn<String> scramble = GeneratedColumn<String>(
    'scramble',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _elapsedMsMeta = const VerificationMeta(
    'elapsedMs',
  );
  @override
  late final GeneratedColumn<int> elapsedMs = GeneratedColumn<int>(
    'elapsed_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _moveCountMeta = const VerificationMeta(
    'moveCount',
  );
  @override
  late final GeneratedColumn<int> moveCount = GeneratedColumn<int>(
    'move_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputSourceMeta = const VerificationMeta(
    'inputSource',
  );
  @override
  late final GeneratedColumn<String> inputSource = GeneratedColumn<String>(
    'input_source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    scramble,
    elapsedMs,
    moveCount,
    createdAt,
    inputSource,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'solve_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SolveEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('scramble')) {
      context.handle(
        _scrambleMeta,
        scramble.isAcceptableOrUnknown(data['scramble']!, _scrambleMeta),
      );
    } else if (isInserting) {
      context.missing(_scrambleMeta);
    }
    if (data.containsKey('elapsed_ms')) {
      context.handle(
        _elapsedMsMeta,
        elapsedMs.isAcceptableOrUnknown(data['elapsed_ms']!, _elapsedMsMeta),
      );
    } else if (isInserting) {
      context.missing(_elapsedMsMeta);
    }
    if (data.containsKey('move_count')) {
      context.handle(
        _moveCountMeta,
        moveCount.isAcceptableOrUnknown(data['move_count']!, _moveCountMeta),
      );
    } else if (isInserting) {
      context.missing(_moveCountMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('input_source')) {
      context.handle(
        _inputSourceMeta,
        inputSource.isAcceptableOrUnknown(
          data['input_source']!,
          _inputSourceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_inputSourceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SolveEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SolveEntry(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      scramble:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}scramble'],
          )!,
      elapsedMs:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}elapsed_ms'],
          )!,
      moveCount:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}move_count'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      inputSource:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}input_source'],
          )!,
    );
  }

  @override
  $SolveEntriesTable createAlias(String alias) {
    return $SolveEntriesTable(attachedDatabase, alias);
  }
}

class SolveEntry extends DataClass implements Insertable<SolveEntry> {
  final String id;
  final String scramble;
  final int elapsedMs;
  final int moveCount;
  final DateTime createdAt;
  final String inputSource;
  const SolveEntry({
    required this.id,
    required this.scramble,
    required this.elapsedMs,
    required this.moveCount,
    required this.createdAt,
    required this.inputSource,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['scramble'] = Variable<String>(scramble);
    map['elapsed_ms'] = Variable<int>(elapsedMs);
    map['move_count'] = Variable<int>(moveCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['input_source'] = Variable<String>(inputSource);
    return map;
  }

  SolveEntriesCompanion toCompanion(bool nullToAbsent) {
    return SolveEntriesCompanion(
      id: Value(id),
      scramble: Value(scramble),
      elapsedMs: Value(elapsedMs),
      moveCount: Value(moveCount),
      createdAt: Value(createdAt),
      inputSource: Value(inputSource),
    );
  }

  factory SolveEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SolveEntry(
      id: serializer.fromJson<String>(json['id']),
      scramble: serializer.fromJson<String>(json['scramble']),
      elapsedMs: serializer.fromJson<int>(json['elapsedMs']),
      moveCount: serializer.fromJson<int>(json['moveCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      inputSource: serializer.fromJson<String>(json['inputSource']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'scramble': serializer.toJson<String>(scramble),
      'elapsedMs': serializer.toJson<int>(elapsedMs),
      'moveCount': serializer.toJson<int>(moveCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'inputSource': serializer.toJson<String>(inputSource),
    };
  }

  SolveEntry copyWith({
    String? id,
    String? scramble,
    int? elapsedMs,
    int? moveCount,
    DateTime? createdAt,
    String? inputSource,
  }) => SolveEntry(
    id: id ?? this.id,
    scramble: scramble ?? this.scramble,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    moveCount: moveCount ?? this.moveCount,
    createdAt: createdAt ?? this.createdAt,
    inputSource: inputSource ?? this.inputSource,
  );
  SolveEntry copyWithCompanion(SolveEntriesCompanion data) {
    return SolveEntry(
      id: data.id.present ? data.id.value : this.id,
      scramble: data.scramble.present ? data.scramble.value : this.scramble,
      elapsedMs: data.elapsedMs.present ? data.elapsedMs.value : this.elapsedMs,
      moveCount: data.moveCount.present ? data.moveCount.value : this.moveCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      inputSource:
          data.inputSource.present ? data.inputSource.value : this.inputSource,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SolveEntry(')
          ..write('id: $id, ')
          ..write('scramble: $scramble, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('moveCount: $moveCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('inputSource: $inputSource')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, scramble, elapsedMs, moveCount, createdAt, inputSource);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SolveEntry &&
          other.id == this.id &&
          other.scramble == this.scramble &&
          other.elapsedMs == this.elapsedMs &&
          other.moveCount == this.moveCount &&
          other.createdAt == this.createdAt &&
          other.inputSource == this.inputSource);
}

class SolveEntriesCompanion extends UpdateCompanion<SolveEntry> {
  final Value<String> id;
  final Value<String> scramble;
  final Value<int> elapsedMs;
  final Value<int> moveCount;
  final Value<DateTime> createdAt;
  final Value<String> inputSource;
  final Value<int> rowid;
  const SolveEntriesCompanion({
    this.id = const Value.absent(),
    this.scramble = const Value.absent(),
    this.elapsedMs = const Value.absent(),
    this.moveCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.inputSource = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SolveEntriesCompanion.insert({
    required String id,
    required String scramble,
    required int elapsedMs,
    required int moveCount,
    required DateTime createdAt,
    required String inputSource,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       scramble = Value(scramble),
       elapsedMs = Value(elapsedMs),
       moveCount = Value(moveCount),
       createdAt = Value(createdAt),
       inputSource = Value(inputSource);
  static Insertable<SolveEntry> custom({
    Expression<String>? id,
    Expression<String>? scramble,
    Expression<int>? elapsedMs,
    Expression<int>? moveCount,
    Expression<DateTime>? createdAt,
    Expression<String>? inputSource,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (scramble != null) 'scramble': scramble,
      if (elapsedMs != null) 'elapsed_ms': elapsedMs,
      if (moveCount != null) 'move_count': moveCount,
      if (createdAt != null) 'created_at': createdAt,
      if (inputSource != null) 'input_source': inputSource,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SolveEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? scramble,
    Value<int>? elapsedMs,
    Value<int>? moveCount,
    Value<DateTime>? createdAt,
    Value<String>? inputSource,
    Value<int>? rowid,
  }) {
    return SolveEntriesCompanion(
      id: id ?? this.id,
      scramble: scramble ?? this.scramble,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      moveCount: moveCount ?? this.moveCount,
      createdAt: createdAt ?? this.createdAt,
      inputSource: inputSource ?? this.inputSource,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (scramble.present) {
      map['scramble'] = Variable<String>(scramble.value);
    }
    if (elapsedMs.present) {
      map['elapsed_ms'] = Variable<int>(elapsedMs.value);
    }
    if (moveCount.present) {
      map['move_count'] = Variable<int>(moveCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (inputSource.present) {
      map['input_source'] = Variable<String>(inputSource.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SolveEntriesCompanion(')
          ..write('id: $id, ')
          ..write('scramble: $scramble, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('moveCount: $moveCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('inputSource: $inputSource, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CrubikDatabase extends GeneratedDatabase {
  _$CrubikDatabase(QueryExecutor e) : super(e);
  $CrubikDatabaseManager get managers => $CrubikDatabaseManager(this);
  late final $SolveEntriesTable solveEntries = $SolveEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [solveEntries];
}

typedef $$SolveEntriesTableCreateCompanionBuilder =
    SolveEntriesCompanion Function({
      required String id,
      required String scramble,
      required int elapsedMs,
      required int moveCount,
      required DateTime createdAt,
      required String inputSource,
      Value<int> rowid,
    });
typedef $$SolveEntriesTableUpdateCompanionBuilder =
    SolveEntriesCompanion Function({
      Value<String> id,
      Value<String> scramble,
      Value<int> elapsedMs,
      Value<int> moveCount,
      Value<DateTime> createdAt,
      Value<String> inputSource,
      Value<int> rowid,
    });

class $$SolveEntriesTableFilterComposer
    extends Composer<_$CrubikDatabase, $SolveEntriesTable> {
  $$SolveEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scramble => $composableBuilder(
    column: $table.scramble,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elapsedMs => $composableBuilder(
    column: $table.elapsedMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get moveCount => $composableBuilder(
    column: $table.moveCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputSource => $composableBuilder(
    column: $table.inputSource,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SolveEntriesTableOrderingComposer
    extends Composer<_$CrubikDatabase, $SolveEntriesTable> {
  $$SolveEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scramble => $composableBuilder(
    column: $table.scramble,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elapsedMs => $composableBuilder(
    column: $table.elapsedMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get moveCount => $composableBuilder(
    column: $table.moveCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputSource => $composableBuilder(
    column: $table.inputSource,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SolveEntriesTableAnnotationComposer
    extends Composer<_$CrubikDatabase, $SolveEntriesTable> {
  $$SolveEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scramble =>
      $composableBuilder(column: $table.scramble, builder: (column) => column);

  GeneratedColumn<int> get elapsedMs =>
      $composableBuilder(column: $table.elapsedMs, builder: (column) => column);

  GeneratedColumn<int> get moveCount =>
      $composableBuilder(column: $table.moveCount, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get inputSource => $composableBuilder(
    column: $table.inputSource,
    builder: (column) => column,
  );
}

class $$SolveEntriesTableTableManager
    extends
        RootTableManager<
          _$CrubikDatabase,
          $SolveEntriesTable,
          SolveEntry,
          $$SolveEntriesTableFilterComposer,
          $$SolveEntriesTableOrderingComposer,
          $$SolveEntriesTableAnnotationComposer,
          $$SolveEntriesTableCreateCompanionBuilder,
          $$SolveEntriesTableUpdateCompanionBuilder,
          (
            SolveEntry,
            BaseReferences<_$CrubikDatabase, $SolveEntriesTable, SolveEntry>,
          ),
          SolveEntry,
          PrefetchHooks Function()
        > {
  $$SolveEntriesTableTableManager(_$CrubikDatabase db, $SolveEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$SolveEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$SolveEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$SolveEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> scramble = const Value.absent(),
                Value<int> elapsedMs = const Value.absent(),
                Value<int> moveCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> inputSource = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SolveEntriesCompanion(
                id: id,
                scramble: scramble,
                elapsedMs: elapsedMs,
                moveCount: moveCount,
                createdAt: createdAt,
                inputSource: inputSource,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String scramble,
                required int elapsedMs,
                required int moveCount,
                required DateTime createdAt,
                required String inputSource,
                Value<int> rowid = const Value.absent(),
              }) => SolveEntriesCompanion.insert(
                id: id,
                scramble: scramble,
                elapsedMs: elapsedMs,
                moveCount: moveCount,
                createdAt: createdAt,
                inputSource: inputSource,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SolveEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$CrubikDatabase,
      $SolveEntriesTable,
      SolveEntry,
      $$SolveEntriesTableFilterComposer,
      $$SolveEntriesTableOrderingComposer,
      $$SolveEntriesTableAnnotationComposer,
      $$SolveEntriesTableCreateCompanionBuilder,
      $$SolveEntriesTableUpdateCompanionBuilder,
      (
        SolveEntry,
        BaseReferences<_$CrubikDatabase, $SolveEntriesTable, SolveEntry>,
      ),
      SolveEntry,
      PrefetchHooks Function()
    >;

class $CrubikDatabaseManager {
  final _$CrubikDatabase _db;
  $CrubikDatabaseManager(this._db);
  $$SolveEntriesTableTableManager get solveEntries =>
      $$SolveEntriesTableTableManager(_db, _db.solveEntries);
}
