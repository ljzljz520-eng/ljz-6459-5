import 'package:flutter/material.dart';
import 'package:ion_nitriding_core/ion_nitriding_core.dart';

import 'stage_page.dart';
import 'release_page.dart';

class BatchDetailPage extends StatefulWidget {
  const BatchDetailPage({
    required this.controller,
    required this.batch,
    super.key,
  });

  final BatchController controller;
  final BatchRecord batch;

  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage> {
  late BatchRecord _batch = widget.batch;
  String? _error;

  Future<void> _run(Future<BatchRecord> Function() action) async {
    try {
      final updated = await action();
      setState(() {
        _batch = updated;
        _error = null;
      });
    } on ApiException catch (e) {
      setState(() => _error = '${e.code}: ${e.message}');
    } on LoadingMismatch catch (e) {
      setState(() => _error = '装炉确认失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final planned = widget.batch.witnessSamples;
    return Scaffold(
      appBar: AppBar(title: Text('批次 ${widget.batch.batchId}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('状态: ${_batch.status.wire}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _SectionTitle('工件'),
          for (final p in widget.batch.parts)
            ListTile(
              dense: true,
              title: Text('${p.partNo} · ${p.material}'),
              subtitle: Text('${p.pretreatment} · ${p.fixturePosition}'),
            ),
          _SectionTitle('见证样 (计划 / 装炉确认)'),
          for (final w in planned)
            CheckboxListTile(
              value: _batch.loadedWitness.any((l) => l.sampleNo == w.sampleNo),
              onChanged: null,
              title: Text('${w.sampleNo} · ${w.fixturePosition}'),
              subtitle: Text(w.material),
            ),
          if (_batch.status == BatchStatus.draft)
            FilledButton.icon(
              onPressed: () => _run(() => widget.controller.confirmLoading(
                    widget.batch.batchId,
                    [
                      for (final w in planned)
                        LoadedWitness(
                          sampleNo: w.sampleNo,
                          fixturePosition: w.fixturePosition,
                        ),
                    ],
                  )),
              icon: const Icon(Icons.fact_check),
              label: const Text('装炉确认 (全部计划见证样已装)'),
            ),
          const Divider(height: 32),
          _ChecklistView(
            initial: _batch.checklist,
            enabled: _batch.status == BatchStatus.draft &&
                _batch.loadedWitness.isNotEmpty,
            confirmed: _batch.status != BatchStatus.draft,
            onConfirm: (c) =>
                _run(() => widget.controller.confirmChecklist(
                    widget.batch.batchId, c)),
          ),
          if (_batch.status == BatchStatus.checked)
            FilledButton.icon(
              onPressed: () =>
                  _run(() => widget.controller.start(widget.batch.batchId)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('执行批准程序 (开炉)'),
            ),
          if (_batch.status == BatchStatus.running) ...[
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StagePage(
                    api: widget.controller.api,
                    batchId: widget.batch.batchId,
                    channelMapping: _batch.checklist.gasChannelMapping,
                  ),
                ),
              ),
              icon: const Icon(Icons.monitor_heart),
              label: const Text('按阶段查看电压电流波动 / 打弧 / 辉光'),
            ),
            FilledButton.icon(
              onPressed: () => _run(
                  () => widget.controller.complete(widget.batch.batchId)),
              icon: const Icon(Icons.stop),
              label: const Text('出炉 (等待实验室回填)'),
            ),
          ],
          if (_batch.status == BatchStatus.labComplete ||
              _batch.status == BatchStatus.completed ||
              _batch.status == BatchStatus.labPartial)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReleasePage(
                    api: widget.controller.api,
                    batchId: widget.batch.batchId,
                  ),
                ),
              ),
              icon: const Icon(Icons.science_outlined),
              label: const Text('实验室结果 / 异常处置 / 工程师放行'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _ChecklistView extends StatefulWidget {
  const _ChecklistView({
    required this.initial,
    required this.enabled,
    required this.confirmed,
    required this.onConfirm,
  });

  final Checklist initial;
  final bool enabled;
  final bool confirmed;
  final ValueChanged<Checklist> onConfirm;

  @override
  State<_ChecklistView> createState() => _ChecklistViewState();
}

class _ChecklistViewState extends State<_ChecklistView> {
  late bool _gas = widget.initial.gasLineConfirmed;
  late bool _ins = widget.initial.insulationConfirmed;
  late final _mfc1 =
      TextEditingController(text: widget.initial.gasChannelMapping['MFC1'] ?? 'N2');
  late final _mfc2 =
      TextEditingController(text: widget.initial.gasChannelMapping['MFC2'] ?? 'H2');
  late final _mfc3 =
      TextEditingController(text: widget.initial.gasChannelMapping['MFC3'] ?? 'Ar');

  Checklist get _value => Checklist(
        gasLineConfirmed: _gas,
        insulationConfirmed: _ins,
        gasChannelMapping: {
          'MFC1': _mfc1.text.trim(),
          'MFC2': _mfc2.text.trim(),
          'MFC3': _mfc3.text.trim(),
        },
      );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: widget.confirmed || !widget.enabled,
      child: Column(children: [
        SwitchListTile(
          value: _gas,
          onChanged: (v) => setState(() => _gas = v),
          title: const Text('气路已确认'),
        ),
        SwitchListTile(
          value: _ins,
          onChanged: (v) => setState(() => _ins = v),
          title: const Text('绝缘已确认'),
        ),
        Row(children: [
          Expanded(child: TextField(
            controller: _mfc1,
            decoration: const InputDecoration(labelText: 'MFC1 ->'),
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: _mfc2,
            decoration: const InputDecoration(labelText: 'MFC2 ->'),
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: _mfc3,
            decoration: const InputDecoration(labelText: 'MFC3 ->'),
          )),
        ]),
        if (!widget.confirmed)
          FilledButton(
            onPressed: widget.enabled ? () => widget.onConfirm(_value) : null,
            child: const Text('确认检查清单'),
          ),
      ]),
    );
  }
}
