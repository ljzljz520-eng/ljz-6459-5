/// 离子氮化批次领域模型 (与后端 FastAPI 枚举/DTO 对齐)。
///
/// 纯 Dart: 不依赖 Flutter / Drift, 可单元测试。
library;

enum BatchStatus {
  draft,
  checked,
  running,
  completed,
  labPartial,
  labComplete,
  released,
  rejected,
  hold,
}

extension BatchStatusWire on BatchStatus {
  /// 线上 JSON 使用大写下划线 (与 Pydantic 枚举一致)。
  String get wire => switch (this) {
        BatchStatus.draft => 'DRAFT',
        BatchStatus.checked => 'CHECKED',
        BatchStatus.running => 'RUNNING',
        BatchStatus.completed => 'COMPLETED',
        BatchStatus.labPartial => 'LAB_PARTIAL',
        BatchStatus.labComplete => 'LAB_COMPLETE',
        BatchStatus.released => 'RELEASED',
        BatchStatus.rejected => 'REJECTED',
        BatchStatus.hold => 'HOLD',
      };

  static BatchStatus fromWire(String value) =>
      BatchStatus.values.firstWhere((s) => s.wire == value);
}

enum StageKind {
  pumpDown,
  heatUp,
  glowClean,
  nitriding,
  diffusion,
  cooling,
}

extension StageKindWire on StageKind {
  String get wire => switch (this) {
        StageKind.pumpDown => 'PUMP_DOWN',
        StageKind.heatUp => 'HEAT_UP',
        StageKind.glowClean => 'GLOW_CLEAN',
        StageKind.nitriding => 'NITRIDING',
        StageKind.diffusion => 'DIFFUSION',
        StageKind.cooling => 'COOLING',
      };

  static StageKind fromWire(String value) =>
      StageKind.values.firstWhere((s) => s.wire == value);
}

enum ArcKind { micro, hard }

extension ArcKindWire on ArcKind {
  String get wire => this == ArcKind.micro ? 'MICRO_ARC' : 'HARD_ARC';

  static ArcKind fromWire(String value) =>
      value == 'HARD_ARC' ? ArcKind.hard : ArcKind.micro;
}

enum AnomalyKind {
  gasChannelSwap,
  glowOverexposed,
  tcPlasmaInterference,
  frequentMicroArcs,
  witnessMissing,
}

extension AnomalyKindWire on AnomalyKind {
  String get wire => switch (this) {
        AnomalyKind.gasChannelSwap => 'GAS_CHANNEL_SWAP',
        AnomalyKind.glowOverexposed => 'GLOW_OVEREXPOSED',
        AnomalyKind.tcPlasmaInterference => 'TC_PLASMA_INTERFERENCE',
        AnomalyKind.frequentMicroArcs => 'FREQUENT_MICRO_ARCS',
        AnomalyKind.witnessMissing => 'WITNESS_MISSING',
      };

  static AnomalyKind fromWire(String value) =>
      AnomalyKind.values.firstWhere((k) => k.wire == value);

  /// 中文短名, 平板列表展示。
  String get label => switch (this) {
        AnomalyKind.gasChannelSwap => '气体通道互换',
        AnomalyKind.glowOverexposed => '辉光过曝',
        AnomalyKind.tcPlasmaInterference => '热电偶受等离子体干扰',
        AnomalyKind.frequentMicroArcs => '频繁微弧',
        AnomalyKind.witnessMissing => '见证样漏装',
      };
}

enum AnomalyStatus { open, acknowledged, dispositioned }

extension AnomalyStatusWire on AnomalyStatus {
  String get wire => switch (this) {
        AnomalyStatus.open => 'OPEN',
        AnomalyStatus.acknowledged => 'ACKNOWLEDGED',
        AnomalyStatus.dispositioned => 'DISPOSITIONED',
      };

  static AnomalyStatus fromWire(String value) =>
      AnomalyStatus.values.firstWhere((s) => s.wire == value);
}

/// 工件登记。
class Part {
  const Part({
    required this.partNo,
    required this.material,
    required this.pretreatment,
    required this.fixturePosition,
  });

  final String partNo;
  final String material;
  final String pretreatment;
  final String fixturePosition;

  Map<String, dynamic> toJson() => {
        'part_no': partNo,
        'material': material,
        'pretreatment': pretreatment,
        'fixture_position': fixturePosition,
      };

  factory Part.fromJson(Map<String, dynamic> j) => Part(
        partNo: j['part_no'] as String,
        material: j['material'] as String,
        pretreatment: j['pretreatment'] as String,
        fixturePosition: j['fixture_position'] as String,
      );
}

/// 计划见证样。
class WitnessSample {
  const WitnessSample({
    required this.sampleNo,
    required this.material,
    required this.fixturePosition,
  });

  final String sampleNo;
  final String material;
  final String fixturePosition;

  Map<String, dynamic> toJson() => {
        'sample_no': sampleNo,
        'material': material,
        'fixture_position': fixturePosition,
      };

  factory WitnessSample.fromJson(Map<String, dynamic> j) => WitnessSample(
        sampleNo: j['sample_no'] as String,
        material: j['material'] as String,
        fixturePosition: j['fixture_position'] as String,
      );
}

/// 装炉确认时实际装上的见证样。
class LoadedWitness {
  const LoadedWitness({required this.sampleNo, required this.fixturePosition});

  final String sampleNo;
  final String fixturePosition;

  Map<String, dynamic> toJson() =>
      {'sample_no': sampleNo, 'fixture_position': fixturePosition};
}

/// 开炉前检查清单: 气路、绝缘、物理气体通道映射。
class Checklist {
  const Checklist({
    this.gasLineConfirmed = false,
    this.insulationConfirmed = false,
    this.gasChannelMapping = const {},
  });

  final bool gasLineConfirmed;
  final bool insulationConfirmed;
  final Map<String, String> gasChannelMapping;

  /// 三项全部满足才允许执行批准程序。
  bool get readyToStart =>
      gasLineConfirmed &&
      insulationConfirmed &&
      gasChannelMapping.isNotEmpty;

  Checklist copyWith({
    bool? gasLineConfirmed,
    bool? insulationConfirmed,
    Map<String, String>? gasChannelMapping,
  }) =>
      Checklist(
        gasLineConfirmed: gasLineConfirmed ?? this.gasLineConfirmed,
        insulationConfirmed: insulationConfirmed ?? this.insulationConfirmed,
        gasChannelMapping: gasChannelMapping ?? this.gasChannelMapping,
      );

  Map<String, dynamic> toJson() => {
        'gas_line_confirmed': gasLineConfirmed,
        'insulation_confirmed': insulationConfirmed,
        'gas_channel_mapping': gasChannelMapping,
      };

  factory Checklist.fromJson(Map<String, dynamic> j) => Checklist(
        gasLineConfirmed: j['gas_line_confirmed'] as bool? ?? false,
        insulationConfirmed: j['insulation_confirmed'] as bool? ?? false,
        gasChannelMapping:
            (j['gas_channel_mapping'] as Map? ?? {}).map(
                  (k, v) => MapEntry(k as String, v as String),
                ),
      );
}

/// 单条炉体时序。
class TelemetryPoint {
  const TelemetryPoint({
    required this.ts,
    required this.stageSeq,
    this.pressurePa,
    this.flowsSccm = const {},
    this.biasVoltageV,
    this.biasCurrentA,
    this.workpieceTempC,
    this.controlTempC,
  });

  final double ts;
  final int stageSeq;
  final double? pressurePa;
  final Map<String, double> flowsSccm;
  final double? biasVoltageV;
  final double? biasCurrentA;
  final double? workpieceTempC;
  final double? controlTempC;

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'stage_seq': stageSeq,
        if (pressurePa != null) 'pressure_pa': pressurePa,
        'flows_sccm': flowsSccm,
        if (biasVoltageV != null) 'bias_voltage_v': biasVoltageV,
        if (biasCurrentA != null) 'bias_current_a': biasCurrentA,
        if (workpieceTempC != null) 'workpiece_temp_c': workpieceTempC,
        if (controlTempC != null) 'control_temp_c': controlTempC,
      };

  factory TelemetryPoint.fromJson(Map<String, dynamic> j) => TelemetryPoint(
        ts: (j['ts'] as num).toDouble(),
        stageSeq: j['stage_seq'] as int,
        pressurePa: (j['pressure_pa'] as num?)?.toDouble(),
        flowsSccm: (j['flows_sccm'] as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        biasVoltageV: (j['bias_voltage_v'] as num?)?.toDouble(),
        biasCurrentA: (j['bias_current_a'] as num?)?.toDouble(),
        workpieceTempC: (j['workpiece_temp_c'] as num?)?.toDouble(),
        controlTempC: (j['control_temp_c'] as num?)?.toDouble(),
      );
}

/// 打弧事件。[preserved] 恒为 true —— 局部打弧必须被保留,
/// 不允许抑制/去重/随保留期清除。
class ArcEvent {
  const ArcEvent({
    required this.ts,
    required this.stageSeq,
    required this.kind,
    required this.peakCurrentA,
    this.durationMs = 1.0,
    this.locationHint,
  });

  final double ts;
  final int stageSeq;
  final ArcKind kind;
  final double peakCurrentA;
  final double durationMs;
  final String? locationHint;

  bool get preserved => true;

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'stage_seq': stageSeq,
        'kind': kind.wire,
        'peak_current_a': peakCurrentA,
        'duration_ms': durationMs,
        if (locationHint != null) 'location_hint': locationHint,
      };

  factory ArcEvent.fromJson(Map<String, dynamic> j) => ArcEvent(
        ts: (j['ts'] as num).toDouble(),
        stageSeq: j['stage_seq'] as int,
        kind: ArcKindWire.fromWire(j['kind'] as String),
        peakCurrentA: (j['peak_current_a'] as num).toDouble(),
        durationMs: (j['duration_ms'] as num?)?.toDouble() ?? 1.0,
        locationHint: j['location_hint'] as String?,
      );
}

/// 辉光图像元数据。图像本身仅用于人工观察辉光均匀性, 不做自动判废。
class GlowImage {
  const GlowImage({
    required this.ts,
    required this.stageSeq,
    required this.imageUri,
    required this.meanPixelValue,
    required this.overexposed,
    this.note,
  });

  final double ts;
  final int stageSeq;
  final String imageUri;
  final double meanPixelValue;
  final bool overexposed;
  final String? note;

  factory GlowImage.fromJson(Map<String, dynamic> j) => GlowImage(
        ts: (j['ts'] as num).toDouble(),
        stageSeq: j['stage_seq'] as int,
        imageUri: j['image_uri'] as String,
        meanPixelValue: (j['mean_pixel_value'] as num).toDouble(),
        overexposed: j['overexposed'] as bool,
        note: j['note'] as String?,
      );
}

/// 异常/偏差记录。
class Anomaly {
  const Anomaly({
    required this.anomalyId,
    required this.batchId,
    required this.kind,
    required this.status,
    required this.detail,
    required this.createdTs,
    this.stageSeq,
    this.disposition,
  });

  final String anomalyId;
  final String batchId;
  final AnomalyKind kind;
  final AnomalyStatus status;
  final String detail;
  final double createdTs;
  final int? stageSeq;
  final String? disposition;

  bool get isOpen => status != AnomalyStatus.dispositioned;

  factory Anomaly.fromJson(Map<String, dynamic> j) => Anomaly(
        anomalyId: j['anomaly_id'] as String,
        batchId: j['batch_id'] as String,
        kind: AnomalyKindWire.fromWire(j['kind'] as String),
        status: AnomalyStatusWire.fromWire(j['status'] as String),
        detail: j['detail'] as String,
        stageSeq: j['stage_seq'] as int?,
        createdTs: (j['created_ts'] as num).toDouble(),
        disposition: j['disposition'] as String?,
      );
}

/// 实验室回填结果 (金相 / 显微硬度 / 化合物层 / 扩散层)。
class LabResult {
  const LabResult({
    required this.sampleNo,
    required this.metallography,
    required this.microhardnessHv,
    required this.compoundLayerUm,
    required this.diffusionLayerMm,
  });

  final String sampleNo;
  final String metallography;
  final List<double> microhardnessHv;
  final double compoundLayerUm;
  final double diffusionLayerMm;

  Map<String, dynamic> toJson() => {
        'sample_no': sampleNo,
        'metallography': metallography,
        'microhardness_hv': microhardnessHv,
        'compound_layer_um': compoundLayerUm,
        'diffusion_layer_mm': diffusionLayerMm,
      };
}
