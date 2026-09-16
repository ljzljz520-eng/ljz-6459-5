/// 阶段聚合: 把炉体时序/打弧/辉光元数据按阶段归并, 供平板按阶段展示
/// 真空、气体比例、偏压电流、工件温度波动与打弧事件。
library;

import 'dart:math' as math;

import 'models.dart';

class StageSummary {
  const StageSummary({
    required this.stageSeq,
    this.kind,
    this.name,
    this.avgPressurePa,
    this.avgGasRatio = const {},
    this.avgBiasVoltageV,
    this.avgBiasCurrentA,
    this.avgWorkpieceTempC,
    this.microArcCount = 0,
    this.hardArcCount = 0,
    this.glowImageUris = const [],
  });

  final int stageSeq;
  final String? kind;
  final String? name;
  final double? avgPressurePa;
  final Map<String, double> avgGasRatio;
  final double? avgBiasVoltageV;
  final double? avgBiasCurrentA;
  final double? avgWorkpieceTempC;
  final int microArcCount;
  final int hardArcCount;
  final List<String> glowImageUris;
}

double? _meanOf(Iterable<double?> values) {
    final v = values.whereType<double>().toList();
    if (v.isEmpty) return null;
    return v.reduce((a, b) => a + b) / v.length;
}

/// 阶段内波动指标: 均值与极差 (平板曲线/异常波动提示用)。
class StageWaveform {
  const StageWaveform({
    required this.points,
    required this.voltageMin,
    required this.voltageMax,
    required this.currentMin,
    required this.currentMax,
  });

  final List<TelemetryPoint> points;
  final double? voltageMin;
  final double? voltageMax;
  final double? currentMin;
  final double? currentMax;

  /// 电流波动幅度 (极差 A)。
  double? get currentSwing {
    if (currentMin == null || currentMax == null) return null;
    return currentMax! - currentMin!;
  }

  /// 电压波动幅度 (极差 V)。
  double? get voltageSwing {
    if (voltageMin == null || voltageMax == null) return null;
    return voltageMax! - voltageMin!;
  }
}

class StageAggregation {
  const StageAggregation();

  /// [channelMapping] 物理通道 -> 气体种类, 如 {'MFC1':'N2'}。
  StageSummary summarize({
    required int stageSeq,
    required List<TelemetryPoint> telemetry,
    required List<ArcEvent> arcs,
    required List<GlowImage> glows,
    required Map<String, String> channelMapping,
    String? kind,
    String? name,
  }) {
    final pts = telemetry.where((p) => p.stageSeq == stageSeq).toList();
    final stageArcs = arcs.where((a) => a.stageSeq == stageSeq).toList();
    final stageGlows = glows.where((g) => g.stageSeq == stageSeq).toList();

    final avgPressure = _meanOf(pts.map((p) => p.pressurePa));
    final avgBiasV = _meanOf(pts.map((p) => p.biasVoltageV));
    final avgBiasA = _meanOf(pts.map((p) => p.biasCurrentA));
    final avgWork = _meanOf(pts.map((p) => p.workpieceTempC));

    // 按物理通道把流量换算到气体种类后求比例。
    final gasTotals = <String, double>{};
    for (final p in pts) {
      p.flowsSccm.forEach((ch, v) {
        final gas = channelMapping[ch] ?? ch;
        gasTotals[gas] = (gasTotals[gas] ?? 0) + v;
      });
    }
    final total = gasTotals.values.fold<double>(0, (a, b) => a + b);
    final gasRatio = total > 0
        ? {for (final e in gasTotals.entries) e.key: e.value / total}
        : <String, double>{};

    return StageSummary(
      stageSeq: stageSeq,
      kind: kind,
      name: name,
      avgPressurePa: avgPressure,
      avgGasRatio: gasRatio,
      avgBiasVoltageV: avgBiasV,
      avgBiasCurrentA: avgBiasA,
      avgWorkpieceTempC: avgWork,
      microArcCount: stageArcs.where((a) => a.kind == ArcKind.micro).length,
      hardArcCount: stageArcs.where((a) => a.kind == ArcKind.hard).length,
      glowImageUris: stageGlows.map((g) => g.imageUri).toList(),
    );
  }

  /// 提取阶段内按时间排序的电压/电流波形与极差, 供平板曲线展示。
  StageWaveform waveform(int stageSeq, List<TelemetryPoint> telemetry) {
    final pts = telemetry
        .where((p) => p.stageSeq == stageSeq)
        .toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));
    double? minOf(double? Function(TelemetryPoint) f) {
      final v = pts.map(f).whereType<double>();
      return v.isEmpty ? null : v.reduce(math.min);
    }

    double? maxOf(double? Function(TelemetryPoint) f) {
      final v = pts.map(f).whereType<double>();
      return v.isEmpty ? null : v.reduce(math.max);
    }

    return StageWaveform(
      points: pts,
      voltageMin: minOf((p) => p.biasVoltageV),
      voltageMax: maxOf((p) => p.biasVoltageV),
      currentMin: minOf((p) => p.biasCurrentA),
      currentMax: maxOf((p) => p.biasCurrentA),
    );
  }
}
