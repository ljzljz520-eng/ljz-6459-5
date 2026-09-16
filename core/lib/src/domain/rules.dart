/// 平板端业务规则 (纯 Dart, 与后端 anomaly_service 对齐, 便于离线预判与展示)。
///
/// 这些规则只用于操作员端的即时提示; 最终判定仍以后端阶段检查为准。
library;

import 'dart:math' as math;

import 'models.dart';

class GasChannelVerdict {
  const GasChannelVerdict({
    required this.suspect,
    this.swapped = const [],
    this.directError = 0,
    this.reason,
  });

  final bool suspect;

  /// 疑似互换对, 如 ['N2', 'H2']。
  final List<String> swapped;
  final double directError;
  final String? reason;
}

class ThermocoupleVerdict {
  const ThermocoupleVerdict({
    required this.suspect,
    required this.hits,
    required this.checked,
    this.maxDeviationC = 0,
  });

  final bool suspect;
  final int hits;
  final int checked;
  final double maxDeviationC;
}

class MicroArcVerdict {
  const MicroArcVerdict({
    required this.alarm,
    required this.peakRatePerMin,
    required this.limit,
  });

  final bool alarm;
  final double peakRatePerMin;
  final double limit;
}

/// 与后端相同的阈值。
const double kGasRatioTolerance = 0.05;
const double kTcPlasmaDeviationC = 40.0;
const double kDefaultMaxMicroArcRatePerMin = 6.0;
const double kArcWindowS = 60.0;
const double kBiasOnVoltageV = 100.0;
const double kOverexposureMeanPixel = 220.0;

class DomainRules {
  const DomainRules();

  /// 气体流量通道互换检测。
  ///
  /// - [setpoints]: 气体设定 sccm, 键为气体种类 {'N2':300,'H2':700}
  /// - [measuredAvg]: 物理通道实测均值, 键为气体种类 (经通道映射换算)
  GasChannelVerdict checkGasChannels(
    Map<String, double> setpoints,
    Map<String, double> measuredAvg,
  ) {
    final setTotal = setpoints.values.fold<double>(0, (a, b) => a + b);
    final meaTotal = measuredAvg.values.fold<double>(0, (a, b) => a + b);
    if (setTotal <= 0 || meaTotal <= 0) {
      return const GasChannelVerdict(suspect: false, reason: '数据不足');
    }
    final setShare = {
      for (final e in setpoints.entries) e.key: e.value / setTotal,
    };
    final meaShare = {
      for (final e in measuredAvg.entries) e.key: e.value / meaTotal,
    };
    final gases = {...setShare.keys, ...meaShare.keys};
    final directErr = gases
        .map((g) => (setShare[g] ?? 0) - (meaShare[g] ?? 0))
        .fold<double>(0, (a, d) => math.max(a, d.abs()));

    if (directErr <= kGasRatioTolerance) {
      return GasChannelVerdict(suspect: false, directError: directErr);
    }
    for (final entry in setShare.entries) {
      for (final m in meaShare.entries) {
        if (entry.key != m.key &&
            (entry.value - m.value).abs() <= kGasRatioTolerance) {
          return GasChannelVerdict(
            suspect: true,
            swapped: [entry.key, m.key],
            directError: directErr,
          );
        }
      }
    }
    return GasChannelVerdict(
      suspect: false,
      directError: directErr,
      reason: '比例超差但非通道互换模式',
    );
  }

  /// 热电偶受等离子体干扰: 仅在偏压 > 100V 的点上比较工件偶与控温偶,
  /// 偏差 > 40°C 的点占比 >= 50% 判可疑。
  ThermocoupleVerdict checkThermocouple(List<TelemetryPoint> pts) {
    var hits = 0;
    var checked = 0;
    var maxDev = 0.0;
    for (final p in pts) {
      if (p.workpieceTempC == null || p.controlTempC == null) continue;
      if ((p.biasVoltageV ?? 0) <= kBiasOnVoltageV) continue;
      checked++;
      final dev = (p.workpieceTempC! - p.controlTempC!).abs();
      maxDev = math.max(maxDev, dev);
      if (dev > kTcPlasmaDeviationC) hits++;
    }
    final suspect = checked > 0 && hits / checked >= 0.5;
    return ThermocoupleVerdict(
      suspect: suspect,
      hits: hits,
      checked: checked,
      maxDeviationC: maxDev,
    );
  }

  /// 频繁微弧: 60s 滑窗内微弧峰值速率 (次/min), 超过限值报警。
  /// 事件必须全部保留, 这里只做统计, 不删除任何事件。
  MicroArcVerdict checkMicroArcRate(
    List<ArcEvent> arcs, {
    double maxRatePerMin = kDefaultMaxMicroArcRatePerMin,
  }) {
    final micros = arcs.where((a) => a.kind == ArcKind.micro).toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));
    if (micros.length < 2) {
      return MicroArcVerdict(
        alarm: false,
        peakRatePerMin: micros.length.toDouble(),
        limit: maxRatePerMin,
      );
    }
    var peak = 0.0;
    for (var i = 0; i < micros.length; i++) {
      var j = i;
      while (j < micros.length &&
          micros[j].ts - micros[i].ts <= kArcWindowS) {
        j++;
      }
      peak = math.max(peak, (j - i) * 60.0 / kArcWindowS);
    }
    return MicroArcVerdict(
      alarm: peak > maxRatePerMin,
      peakRatePerMin: peak,
      limit: maxRatePerMin,
    );
  }

  /// 辉光过曝: 仅标记供人工观察, 不自动判废。
  bool isGlowOverexposed(double meanPixelValue) =>
      meanPixelValue >= kOverexposureMeanPixel;
}

/// 装炉确认校验: 计划见证样必须全部出现, 且不允许未登记编号。
class LoadingCheck {
  const LoadingCheck();

  /// 返回 (漏装编号, 未登记编号)。
  ({List<String> missing, List<String> unknown}) verify(
    List<String> plannedSampleNos,
    List<String> loadedSampleNos,
  ) {
    final missing = plannedSampleNos
        .where((no) => !loadedSampleNos.contains(no))
        .toList();
    final unknown = loadedSampleNos
        .where((no) => !plannedSampleNos.contains(no))
        .toList();
    return (missing: missing, unknown: unknown);
  }
}
