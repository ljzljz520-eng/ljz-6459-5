/// Drift 实现的 BatchCache (core 包接口)。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ion_nitriding_core/ion_nitriding_core.dart' as core;

import 'local_database.dart';

class DriftBatchCache implements core.BatchCache {
  DriftBatchCache(this._db);

  final LocalDatabase _db;

  @override
  Future<void> upsertBatch(core.BatchRecord batch) {
    return _db.into(_db.batchRows).insertOnConflictUpdate(
          BatchRowsCompanion.insert(
            batchId: batch.batchId,
            furnaceId: batch.furnaceId,
            operatorName: batch.operator,
            procedureId: batch.procedureId,
            status: batch.status.wire,
            payloadJson: jsonEncode(batch.toJson()),
            updatedTs: batch.updatedTs,
          ),
        );
  }

  @override
  Future<core.BatchRecord?> getBatch(String batchId) async {
    final row = await (_db.select(_db.batchRows)
          ..where((b) => b.batchId.equals(batchId)))
        .getSingleOrNull();
    if (row == null) return null;
    return core.BatchRecord.fromJson(
      jsonDecode(row.payloadJson) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<core.BatchRecord>> listBatches() async {
    final rows = await (_db.select(_db.batchRows)
          ..orderBy([(b) => OrderingTerm.desc(b.updatedTs)]))
        .get();
    return rows
        .map((r) => core.BatchRecord.fromJson(
            jsonDecode(r.payloadJson) as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> enqueueOutbox(core.OutboxRequest req) {
    return _db.into(_db.outboxRows).insertOnConflictUpdate(
          OutboxRowsCompanion.insert(
            id: req.id,
            method: req.method,
            path: req.path,
            bodyJson: jsonEncode(req.body),
            createdAt: DateTime.now().millisecondsSinceEpoch / 1000.0,
          ),
        );
  }

  @override
  Future<List<core.OutboxRequest>> outbox() async {
    final rows = await (_db.select(_db.outboxRows)
          ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
        .get();
    return rows
        .map((r) => core.OutboxRequest(
              id: r.id,
              method: r.method,
              path: r.path,
              body: jsonDecode(r.bodyJson) as Map<String, dynamic>,
            ))
        .toList();
  }

  @override
  Future<void> removeOutbox(String id) =>
      (_db.delete(_db.outboxRows)..where((o) => o.id.equals(id))).go();
}
