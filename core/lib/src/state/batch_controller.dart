/// 操作员批次工作流控制器 (纯 Dart, ChangeNotifier 可在 Flutter 端 mixin)。
///
/// 流程: 登记材质/前处理/装夹位置/见证样 -> 装炉确认 -> 气路/绝缘确认
/// -> 执行批准程序 -> 按阶段查看曲线与打弧 -> (实验室回填, 工程师放行)。
library;

import '../data/api_client.dart';
import '../data/batch_repository.dart';
import '../domain/models.dart';
import '../domain/rules.dart';

class BatchController {
  BatchController({required this.api, required this.cache});

  final ApiClient api;
  final BatchCache cache;
  final rules = const LoadingCheck();

  /// 登记批次: 本地预检见证样计划, 调后端创建, 成功后缓存。
  Future<BatchRecord> registerBatch({
    required String furnaceId,
    required String operator,
    required String procedureId,
    required List<Part> parts,
    required List<WitnessSample> witnessSamples,
  }) async {
    final body = {
      'furnace_id': furnaceId,
      'operator': operator,
      'procedure_id': procedureId,
      'parts': parts.map((p) => p.toJson()).toList(),
      'witness_samples': witnessSamples.map((w) => w.toJson()).toList(),
    };
    final json = await api.createBatch(body);
    final batch = BatchRecord(
      batchId: json['batch_id'] as String,
      furnaceId: furnaceId,
      operator: operator,
      procedureId: procedureId,
      status: BatchStatus.draft,
      parts: parts,
      witnessSamples: witnessSamples,
      updatedTs: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    await cache.upsertBatch(batch);
    return batch;
  }

  /// 装炉确认。漏装/未登记在客户端先拦一道 (后端仍为权威判定)。
  Future<BatchRecord> confirmLoading(
    String batchId,
    List<LoadedWitness> loaded,
  ) async {
    final local = await cache.getBatch(batchId);
    if (local != null) {
      final v = rules.verify(
        local.witnessSamples.map((w) => w.sampleNo).toList(),
        loaded.map((w) => w.sampleNo).toList(),
      );
      if (v.missing.isNotEmpty || v.unknown.isNotEmpty) {
        throw LoadingMismatch(missing: v.missing, unknown: v.unknown);
      }
    }
    final json = await api.confirmLoading(batchId, {
      'loaded_witness': loaded.map((w) => w.toJson()).toList(),
    });
    final updated = BatchRecord.fromJson({
      ...json,
      'updated_ts': DateTime.now().millisecondsSinceEpoch / 1000.0,
    });
    await cache.upsertBatch(updated);
    return updated;
  }

  Future<BatchRecord> confirmChecklist(
    String batchId,
    Checklist checklist,
  ) async {
    if (!checklist.readyToStart) {
      throw StateError('气路/绝缘未确认或缺少通道映射');
    }
    final json = await api.confirmChecklist(batchId, checklist.toJson());
    final updated = BatchRecord.fromJson({
      ...json,
      'updated_ts': DateTime.now().millisecondsSinceEpoch / 1000.0,
    });
    await cache.upsertBatch(updated);
    return updated;
  }

  Future<BatchRecord> start(String batchId) =>
      _transition(batchId, api.start(batchId));

  Future<BatchRecord> complete(String batchId) =>
      _transition(batchId, api.complete(batchId));

  Future<BatchRecord> _transition(
    String batchId,
    Future<Map<String, dynamic>> fut,
  ) async {
    final json = await fut;
    final updated = BatchRecord.fromJson({
      ...json,
      'updated_ts': DateTime.now().millisecondsSinceEpoch / 1000.0,
    });
    await cache.upsertBatch(updated);
    return updated;
  }
}

class LoadingMismatch implements Exception {
  const LoadingMismatch({required this.missing, required this.unknown});

  final List<String> missing;
  final List<String> unknown;

  @override
  String toString() => '见证样漏装=$missing 未登记=$unknown';
}
