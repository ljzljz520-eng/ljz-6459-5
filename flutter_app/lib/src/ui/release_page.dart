import 'package:flutter/material.dart';
import 'package:ion_nitriding_core/ion_nitriding_core.dart';

/// 实验室回填 + 异常处置 + 工艺工程师放行 (平板端视图; 放行权在工程师)。
class ReleasePage extends StatefulWidget {
  const ReleasePage({required this.api, required this.batchId, super.key});

  final ApiClient api;
  final String batchId;

  @override
  State<ReleasePage> createState() => _ReleasePageState();
}

class _ReleasePageState extends State<ReleasePage> {
  List<dynamic> _anomalies = const [];
  Map<String, dynamic>? _corr;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        widget.api.anomalies(widget.batchId),
        widget.api.correlation(widget.batchId),
      ]);
      setState(() {
        _anomalies = results[0] as List<dynamic>;
        _corr = results[1] as Map<String, dynamic>;
      });
    } on ApiException catch (e) {
      setState(() => _error = '${e.code}: ${e.message}');
    }
  }

  Future<void> _dispose(Map<dynamic, dynamic> a) async {
    final controller = TextEditingController();
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('异常处置说明'),
        content: TextField(controller: controller, maxLines: 3),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确认处置'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    await widget.api.dispositionAnomaly(a['anomaly_id'] as String, {
      'engineer': 'process.eng',
      'disposition': text,
    });
    await _load();
  }

  Future<void> _release(String decision, String comment) async {
    try {
      await widget.api.release(widget.batchId, {
        'engineer': 'process.eng',
        'decision': decision,
        'comment': comment,
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e.code}: ${e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final corr = _corr;
    return Scaffold(
      appBar: AppBar(title: Text('放行 ${widget.batchId}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          Text('异常/偏差', style: Theme.of(context).textTheme.titleMedium),
          if (_anomalies.isEmpty) const ListTile(title: Text('无异常记录')),
          for (final a in _anomalies)
            ListTile(
              leading: Icon(
                a['status'] == 'DISPOSITIONED'
                    ? Icons.check_circle
                    : Icons.warning,
                color: a['status'] == 'DISPOSITIONED'
                    ? Colors.green
                    : Colors.red,
              ),
              title: Text(
                AnomalyKindWire.fromWire(a['kind'] as String).label,
              ),
              subtitle: Text(a['detail'] as String),
              trailing: a['status'] == 'DISPOSITIONED'
                  ? const Text('已处置')
                  : TextButton(
                      onPressed: () => _dispose(a as Map),
                      child: const Text('处置'),
                    ),
            ),
          const Divider(),
          Text('阶段汇总 (过程参数 <-> 层结果)',
              style: Theme.of(context).textTheme.titleMedium),
          if (corr != null)
            for (final s in (corr['stages'] as List))
              ListTile(
                dense: true,
                title: Text('阶段 ${s['stage_seq']} ${s['name'] ?? ''}'),
                subtitle: Text(
                  '压力 ${s['avg_pressure_pa']} · 偏流 ${s['avg_bias_current_a']}A · '
                  '温度 ${s['avg_workpiece_temp_c']}°C · '
                  '微弧 ${s['micro_arc_count']} · 硬弧 ${s['hard_arc_count']}',
                ),
              ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed: () => _release('RELEASED', '工艺工程师放行'),
              child: const Text('放行'),
            ),
            OutlinedButton(
              onPressed: () => _release('HOLD', '挂起待查'),
              child: const Text('挂起'),
            ),
            OutlinedButton(
              onPressed: () => _release('REJECTED', '拒收'),
              child: const Text('拒收'),
            ),
          ]),
        ],
      ),
    );
  }
}
