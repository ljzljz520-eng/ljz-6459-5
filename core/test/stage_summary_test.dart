import 'package:ion_nitriding_core/ion_nitriding_core.dart';
import 'package:test/test.dart';

void main() {
  const agg = StageAggregation();
  const mapping = {'MFC1': 'N2', 'MFC2': 'H2', 'MFC3': 'Ar'};

  test('阶段聚合: 均值/气体比例/打弧计数/辉光 URI', () {
    final telemetry = List.generate(
      12,
      (i) => TelemetryPoint(
        ts: 1000000 + i * 10,
        stageSeq: 3,
        pressurePa: 300,
        biasVoltageV: 650,
        biasCurrentA: 30,
        workpieceTempC: 520,
        controlTempC: 520,
        flowsSccm: {'MFC1': 300, 'MFC2': 700},
      ),
    );
    final arcs = [
      ArcEvent(
        ts: 1000050,
        stageSeq: 3,
        kind: ArcKind.hard,
        peakCurrentA: 85,
        durationMs: 3,
        locationHint: '上层A1齿顶',
      ),
      for (var i = 0; i < 8; i++)
        ArcEvent(
          ts: 1000100 + i * 5,
          stageSeq: 3,
          kind: ArcKind.micro,
          peakCurrentA: 45,
        ),
    ];
    const glows = [
      GlowImage(
        ts: 1000060,
        stageSeq: 3,
        imageUri: 'cam/glow_1000060.png',
        meanPixelValue: 128,
        overexposed: false,
      ),
    ];

    final s = agg.summarize(
      stageSeq: 3,
      telemetry: telemetry,
      arcs: arcs,
      glows: glows,
      channelMapping: mapping,
      kind: 'NITRIDING',
      name: '氮化',
    );
    expect(s.avgPressurePa, 300);
    expect(s.avgBiasCurrentA, 30);
    expect(s.avgWorkpieceTempC, 520);
    expect(s.avgGasRatio['N2'], closeTo(0.3, 1e-9));
    expect(s.avgGasRatio['H2'], closeTo(0.7, 1e-9));
    expect(s.hardArcCount, 1);
    expect(s.microArcCount, 8);
    expect(s.glowImageUris, ['cam/glow_1000060.png']);
  });

  test('波形极差反映电压电流波动', () {
    final pts = [
      for (var i = 0; i < 5; i++)
        TelemetryPoint(
          ts: 1000000 + i * 10,
          stageSeq: 3,
          biasVoltageV: 640 + i * 4,
          biasCurrentA: 28 + i * 1.0,
        ),
    ];
    final w = agg.waveform(3, pts);
    expect(w.voltageSwing, 16);
    expect(w.currentSwing, 4);
  });
}
