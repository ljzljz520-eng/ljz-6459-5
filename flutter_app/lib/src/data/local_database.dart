/// Drift 本地缓存: 车间批次记录离线缓存 + 出站重放队列。
///
/// 对应后端 SQLite 元数据库 (批次/异常/放行)。时序数据在 InfluxDB, 不进 Drift。
/// 生成代码: dart run build_runner build (需 Flutter/Dart SDK + drift_dev)。
library;

import 'package:drift/drift.dart';

/// 批次元数据快照 (与 FastAPI BatchOut 对应, payload 为 JSON 全量)。
class BatchRows extends Table {
  TextColumn get batchId => text()();
  TextColumn get furnaceId => text()();
  TextColumn get operatorName => text()();
  TextColumn get procedureId => text()();
  TextColumn get status => text()();
  TextColumn get payloadJson => text()();
  RealColumn get updatedTs => real()();

  @override
  Set<Column> get primaryKey => {batchId};
}

/// 异常记录缓存 (便于离线查看未处置偏差, 如频繁微弧/通道互换)。
class AnomalyRows extends Table {
  TextColumn get anomalyId => text()();
  TextColumn get batchId => text()();
  TextColumn get kind => text()();
  TextColumn get status => text()();
  TextColumn get detail => text()();
  IntColumn get stageSeq => integer().nullable()();
  RealColumn get createdTs => real()();
  TextColumn get disposition => text().nullable()();

  @override
  Set<Column> get primaryKey => {anomalyId};
}

/// 弱网出站请求重放队列。
class OutboxRows extends Table {
  TextColumn get id => text()();
  TextColumn get method => text()();
  TextColumn get path => text()();
  TextColumn get bodyJson => text()();
  RealColumn get createdAt => real()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [BatchRows, AnomalyRows, OutboxRows])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
