import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ion_nitriding_core/ion_nitriding_core.dart';

/// 执行阶段监视: 按阶段展示真空(压力)/气体比例/偏压电流/工件温度波动与打弧事件。
/// 辉光图像仅给操作员人工判断均匀性, 过曝仅提示不判废。
class StagePage extends StatefulWidget {
  const StagePage({
    required this.api,
    required this.batchId,
    required this.channelMapping,
    super.key,
  });

  final ApiClient api;
  final String batchId;
  final Map<String, String> channelMapping;

  static const _stages = [
    (0, '抽真空'),
    (1, '升温'),
    (2, '辉光清洗'),
    (3, '氮化'),
    (4, '冷却'),
  ];

  @override
  State<StagePage> createState() => _StagePageState();
}

class _StagePageState extends State<StagePage> {
  int _seq = 3;
  bool _loading = false;
  String? _error;
  List<dynamic> _series = const [];
  List<dynamic> _arcs = const [];
  List<dynamic> _glows = const [];
  Map<String, dynamic>? _checks;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.api.stageSeries(widget.batchId, _seq),
        widget.api.arcEvents(widget.batchId, stageSeq: _seq),
        widget.api.glowImages(widget.batchId, stageSeq: _seq),
      ]);
      setState(() {
        _series = results[0] as List<dynamic>;
        _arcs = results[1] as List<dynamic>;
        _glows = results[2] as List<dynamic>;
      });
    } on ApiException catch (e) {
      setState(() => _error = '${e.code}: ${e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runChecks() async {
    try {
      final r = await widget.api.runStageChecks(widget.batchId, _seq);
      setState(() => _checks = r);
      await _load();
    } on ApiException catch (e) {
      setState(() => _error = '${e.code}: ${e.message}');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('阶段监视 ${widget.batchId}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          TextButton.icon(
            onPressed: _runChecks,
            icon: const Icon(Icons.fact_check_outlined, color: Colors.white),
            label: const Text('阶段检查', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(spacing: 8, children: [
                  for (final (seq, name) in StagePage._stages)
                    ChoiceChip(
                      selected: _seq == seq,
                      label: Text('$seq $name'),
                      onSelected: (_) {
                        setState(() => _seq = seq);
                        _load();
                      },
                    ),
                ]),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                if (_checks != null) _ChecksPanel(checks: _checks!),
                const SizedBox(height: 12),
                _MetricsCards(series: _series, mapping: widget.channelMapping),
                const SizedBox(height: 12),
                Text('偏压电压/电流波动',
                    style: Theme.of(context).textTheme.titleMedium),
                SizedBox(
                  height: 180,
                  child: _WaveChart(series: _series),
                ),
                const SizedBox(height: 12),
                Text('打弧事件 (全部保留, 共 ${_arcs.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final a in _arcs) _ArcTile(a as Map),
                const SizedBox(height: 12),
                Text('辉光图像 (仅人工观察均匀性)',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final g in _glows) _GlowTile(g as Map),
              ],
            ),
    );
  }
}

class _ChecksPanel extends StatelessWidget {
  const _ChecksPanel({required this.checks});
  final Map<String, dynamic> checks;

  @override
  Widget build(BuildContext context) {
    final gas = checks['gas_channels'] as Map?;
    final tc = checks['thermocouple'] as Map?;
    final micro = checks['micro_arcs'] as Map?;
    Widget line(IconData icon, Color color, String text) => Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(text)),
        ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (gas != null)
            line(
              gas['suspect'] == true ? Icons.warning : Icons.check_circle,
              gas['suspect'] == true ? Colors.red : Colors.green,
              gas['suspect'] == true
                  ? '疑似气体通道互换: ${(gas['swapped'] as List).join(' <-> ')}'
                  : '气体通道正常',
            ),
          if (tc != null)
            line(
              tc['suspect'] == true ? Icons.thermostat : Icons.check_circle,
              tc['suspect'] == true ? Colors.orange : Colors.green,
              '工件热电偶 ${tc['suspect'] == true ? '疑似受等离子体干扰' : '正常"} '
                  '(${tc['hits']}/${tc['checked']})',
            ),
          if (micro != null)
            line(
              micro['alarm'] == true ? Icons.bolt : Icons.check_circle,
              micro['alarm'] == true ? Colors.red : Colors.green,
              '微弧峰值 ${(micro['peak_rate_per_min'] as num).toStringAsFixed(1)} '
                  '次/min (限值 ${(micro['limit'] as num?) ?? 6})',
            ),
        ]),
      ),
    );
  }
}

class _MetricsCards extends StatelessWidget {
  const _MetricsCards({required this.series, required this.mapping});
  final List<dynamic> series;
  final Map<String, String> mapping;

  double? _avg(String key) {
    final v = series
        .where((p) => (p as Map).containsKey(key))
        .map((p) => (p[key] as num).toDouble())
        .toList();
    if (v.isEmpty) return null;
    return v.reduce((a, b) => a + b) / v.length;
  }

  @override
  Widget build(BuildContext context) {
    final pressure = _avg('pressure_pa');
    final biasV = _avg('bias_voltage_v');
    final biasA = _avg('bias_current_a');
    final workT = _avg('workpiece_temp_c');

    // 由物理通道(MFCx)按映射汇总气体比例。
    final gasTotals = <String, double>{};
    for (final p in series) {
      final flows = (p as Map)['flows_sccm'] as Map?;
      flows?.forEach((ch, v) {
        final gas = mapping[ch] ?? ch.toString();
        gasTotals[gas] = (gasTotals[gas] ?? 0) + (v as num).toDouble();
      });
    }
    final total = gasTotals.values.fold<double>(0, (a, b) => a + b);
    final ratio = {
      if (total > 0)
        for (final e in gasTotals.entries) e.key: e.value / total,
    };

    return Wrap(spacing: 8, runSpacing: 8, children: [
      _Card('平均压力', pressure == null ? '-' : '${pressure.toStringAsFixed(0)} Pa'),
      _Card('平均偏压', biasV == null ? '-' : '${biasV.toStringAsFixed(0)} V'),
      _Card('平均偏流', biasA == null ? '-' : '${biasA.toStringAsFixed(1)} A'),
      _Card('工件温度', workT == null ? '-' : '${workT.toStringAsFixed(0)} °C'),
      _Card('气体比例',
          ratio.entries.map((e) => '${e.key} ${(e.value * 100).round()}%').join(' / ')),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
      );
}

/// 自绘极简电压/电流波动曲线, 平板无第三方图表依赖。
class _WaveChart extends StatelessWidget {
  const _WaveChart({required this.series});
  final List<dynamic> series;

  @override
  Widget build(BuildContext context) {
    final pts = series.cast<Map>();
    if (pts.isEmpty) return const Center(child: Text('暂无时序数据'));
    return CustomPaint(
      size: Size.infinite,
      painter: _WavePainter(
        volts: pts
            .where((p) => p.containsKey('bias_voltage_v'))
            .map((p) => (p['bias_voltage_v'] as num).toDouble())
            .toList(),
        amps: pts
            .where((p) => p.containsKey('bias_current_a'))
            .map((p) => (p['bias_current_a'] as num).toDouble())
            .toList(),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.volts, required this.amps});
  final List<double> volts;
  final List<double> amps;

  void _paintLine(Canvas canvas, Size size, List<double> values, Color color) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV) == 0 ? 1 : maxV - minV;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final y = size.height - (values[i] - minV) / span * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintLine(canvas, size, volts, Colors.indigo);
    _paintLine(canvas, size, amps, Colors.deepOrange);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.volts != volts || old.amps != amps;
}

class _ArcTile extends StatelessWidget {
  const _ArcTile(this.a);
  final Map a;

  @override
  Widget build(BuildContext context) {
    final hard = a['kind'] == 'HARD_ARC';
    return ListTile(
      dense: true,
      leading: Icon(hard ? Icons.flash_on : Icons.bolt,
          color: hard ? Colors.red : Colors.orange),
      title: Text(
        '${hard ? '硬打弧' : '微弧'} · ${a['peak_current_a']}A · '
        '${a['duration_ms']}ms'
        '${a['location_hint'] != null && (a['location_hint'] as String).isNotEmpty
            ? ' · ${a['location_hint']}'
            : ''}',
      ),
      subtitle: const Text('事件已永久保留 (arc_events, 无限保留期)'),
    );
  }
}

class _GlowTile extends StatelessWidget {
  const _GlowTile(this.g);
  final Map g;

  @override
  Widget build(BuildContext context) {
    final over = g['overexposed'] == true;
    return ListTile(
      dense: true,
      leading: Icon(over ? Icons.brightness_alert : Icons.image,
          color: over ? Colors.red : Colors.green),
      title: Text('${g['image_uri']} · 平均灰度 ${g['mean_pixel_value']}'),
      subtitle: Text(over
          ? '过曝, 该图像不可用于均匀性人工观察 (批次不自动判废)'
          : '供人工观察辉光均匀性, 不做自动判定'),
    );
  }
}
