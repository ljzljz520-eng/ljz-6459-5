/// 离线优先仓库: 车间记录先写本地缓存(Flutter 端为 Drift), 再同步 FastAPI。
///
/// 时序数据(炉体曲线/打弧/辉光)由炉控直接进 InfluxDB, 平板经 API 查询;
/// 批次元数据(登记/清单/实验室结果/异常/放行)走缓存, 弱网可稍后重放。
library;

import '../domain/models.dart';

/// 本地缓存接口。生产实现见 flutter_app (Drift); 测试用内存实现。
abstract class BatchCache {
  Future<void> upsertBatch(BatchRecord batch);
  Future<BatchRecord?> getBatch(String batchId);
  Future<List<BatchRecord>> listBatches();

  /// 待重放的出站请求 (弱网时暂存)。
  Future<void> enqueueOutbox(OutboxRequest req);
  Future<List<OutboxRequest>> outbox();
  Future<void> removeOutbox(String id);
}

class BatchRecord {
  const BatchRecord({
    required this.batchId,
    required this.furnaceId,
    required this.operator,
    required this.procedureId,
    required this.status,
    required this.parts,
    required this.witnessSamples,
    this.loadedWitness = const [],
    this.checklist = const Checklist(),
    required this.updatedTs,
  });

  final String batchId;
  final String furnaceId;
  final String operator;
  final String procedureId;
  final BatchStatus status;
  final List<Part> parts;
  final List<WitnessSample> witnessSamples;
  final List<LoadedWitness> loadedWitness;
  final Checklist checklist;
  final double updatedTs;

  bool get loadingConfirmed => loadedWitness.isNotEmpty;
  bool get readyToStart => loadingConfirmed && checklist.readyToStart;

  BatchRecord copyWith({
    BatchStatus? status,
    List<LoadedWitness>? loadedWitness,
    Checklist? checklist,
    double? updatedTs,
  }) =>
      BatchRecord(
        batchId: batchId,
        furnaceId: furnaceId,
        operator: operator,
        procedureId: procedureId,
        status: status ?? this.status,
        parts: parts,
        witnessSamples: witnessSamples,
        loadedWitness: loadedWitness ?? this.loadedWitness,
        checklist: checklist ?? this.checklist,
        updatedTs: updatedTs ?? this.updatedTs,
      );

  Map<String, dynamic> toJson() => {
        'batch_id': batchId,
        'furnace_id': furnaceId,
        'operator': operator,
        'procedure_id': procedureId,
        'status': status.wire,
        'parts': parts.map((p) => p.toJson()).toList(),
        'witness_samples': witnessSamples.map((w) => w.toJson()).toList(),
        'loaded_witness': loadedWitness.map((w) => w.toJson()).toList(),
        'checklist': checklist.toJson(),
      };

  factory BatchRecord.fromJson(Map<String, dynamic> j) => BatchRecord(
        batchId: j['batch_id'] as String,
        furnaceId: j['furnace_id'] as String,
        operator: j['operator'] as String,
        procedureId: j['procedure_id'] as String,
        status: BatchStatusWire.fromWire(j['status'] as String),
        parts: (j['parts'] as List)
            .map((e) => Part.fromJson(e as Map<String, dynamic>))
            .toList(),
        witnessSamples: (j['witness_samples'] as List)
            .map((e) => WitnessSample.fromJson(e as Map<String, dynamic>))
            .toList(),
        loadedWitness: ((j['loaded_witness'] ?? []) as List)
            .map((e) => LoadedWitness(
                  sampleNo: e['sample_no'] as String,
                  fixturePosition: e['fixture_position'] as String,
                ))
            .toList(),
        checklist: Checklist.fromJson(
            (j['checklist'] ?? const <String, dynamic>{})
                as Map<String, dynamic>),
        updatedTs: (j['updated_ts'] as num?)?.toDouble() ?? 0,
      );
}

class OutboxRequest {
  const OutboxRequest({
    required this.id,
    required this.method,
    required this.path,
    required this.body,
  });

  final String id;
  final String method;
  final String path;
  final Map<String, dynamic> body;
}

class InMemoryBatchCache implements BatchCache {
  final Map<String, BatchRecord> _batches = {};
  final List<OutboxRequest> _outbox = [];

  @override
  Future<void> upsertBatch(BatchRecord batch) async {
    _batches[batch.batchId] = batch;
  }

  @override
  Future<BatchRecord?> getBatch(String batchId) async => _batches[batchId];

  @override
  Future<List<BatchRecord>> listBatches() async =>
      _batches.values.toList()..sort((a, b) => b.updatedTs.compareTo(a.updatedTs));

  @override
  Future<void> enqueueOutbox(OutboxRequest req) async {
    _outbox.removeWhere((r) => r.id == req.id);
    _outbox.add(req);
  }

  @override
  Future<List<OutboxRequest>> outbox() async => List.unmodifiable(_outbox);

  @override
  Future<void> removeOutbox(String id) async =>
      _outbox.removeWhere((r) => r.id == id);
}
