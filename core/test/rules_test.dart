import 'package:ion_nitriding_core/ion_nitriding_core.dart';
import 'package:test/test.dart';

TelemetryPoint _tp({
  required double ts,
  int stage = 3,
  double? pressure = 300,
  double? biasV = 650,
  double? biasA = 30,
  double? work,
  double? control,
  Map<String, double> flows = const {},
}) =>
    TelemetryPoint(
      ts: ts,
      stageSeq: stage,
      pressurePa: pressure,
      biasVoltageV: biasV,
      biasCurrentA: biasA,
      workpieceTempC: work,
      controlTempC: control,
      flowsSccm: flows,
    );

void main() {
  const rules = DomainRules();

  group('气体流量通道互换', () {
    test('设定 N2:H2=3:7 实测接反 -> 可疑并给出互换对', () {
      final v = rules.checkGasChannels(
        {'N2': 300, 'H2': 700},
        {'N2': 700, 'H2': 300},
      );
      expect(v.suspect, isTrue);
      expect(v.swapped.toSet(), {'N2', 'H2'});
    });

    test('通道正常 -> 不报警', () {
      final v = rules.checkGasChannels(
        {'N2': 300, 'H2': 700},
        {'N2': 303, 'H2': 698},
      );
      expect(v.suspect, isFalse);
    });
  });

  group('辉光过曝', () {
    test('245 >= 220 判过曝, 110 不过曝', () {
      expect(rules.isGlowOverexposed(245), isTrue);
      expect(rules.isGlowOverexposed(110), isFalse);
      expect(rules.isGlowOverexposed(220), isTrue);
    });
  });

  group('热电偶受等离子体影响', () {
    test('偏压期间 10/10 点偏差 80C -> 可疑', () {
      final pts = List.generate(
        10,
        (i) => _tp(ts: 1000000 + i * 10, work: 600, control: 520),
      );
      final v = rules.checkThermocouple(pts);
      expect(v.suspect, isTrue);
      expect(v.hits, 10);
      expect(v.checked, 10);
    });

    test('无偏压(升温阶段)不检查, 即使偏差大也不可疑', () {
      final pts = List.generate(
        10,
        (i) => _tp(
          ts: 1000000 + i * 10,
          stage: 1,
          biasV: 0,
          work: 480,
          control: 520,
        ),
      );
      final v = rules.checkThermocouple(pts);
      expect(v.checked, 0);
      expect(v.suspect, isFalse);
    });
  });

  group('频繁微弧', () {
    List<ArcEvent> arcs(int n, double gap) => List.generate(
          n,
          (i) => ArcEvent(
            ts: 1000000 + i * gap,
            stageSeq: 3,
            kind: ArcKind.micro,
            peakCurrentA: 45,
          ),
        );

    test('5s 间隔 10 个 -> 12/min 报警', () {
      final v = rules.checkMicroArcRate(arcs(10, 5));
      expect(v.alarm, isTrue);
      expect(v.peakRatePerMin, greaterThan(6));
    });

    test('120s 间隔 3 个 -> 不报警', () {
      final v = rules.checkMicroArcRate(arcs(3, 120));
      expect(v.alarm, isFalse);
    });

    test('打弧事件保留标志恒真且统计不删除事件', () {
      final input = arcs(10, 5);
      rules.checkMicroArcRate(input);
      expect(input.length, 10);
      expect(input.every((a) => a.preserved), isTrue);
    });
  });

  group('见证样漏装', () {
    const check = LoadingCheck();
    test('少装 WS-02 -> missing; 多装未登记 -> unknown', () {
      final v = check.verify(['WS-01', 'WS-02'], ['WS-01']);
      expect(v.missing, ['WS-02']);
      final v2 = check.verify(['WS-01'], ['WS-01', 'WS-77']);
      expect(v2.unknown, ['WS-77']);
    });
    test('全部装齐 -> 无缺失', () {
      final v = check.verify(['WS-01', 'WS-02'], ['WS-02', 'WS-01']);
      expect(v.missing, isEmpty);
      expect(v.unknown, isEmpty);
    });
  });
}
