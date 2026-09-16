import 'package:flutter/material.dart';
import 'package:ion_nitriding_core/ion_nitriding_core.dart';

class RegisterBatchPage extends StatefulWidget {
  const RegisterBatchPage({required this.controller, super.key});

  final BatchController controller;

  @override
  State<RegisterBatchPage> createState() => _RegisterBatchPageState();
}

class _RegisterBatchPageState extends State<RegisterBatchPage> {
  final _formKey = GlobalKey<FormState>();
  final _furnace = TextEditingController(text: 'LD-50');
  final _operator = TextEditingController();
  final _procedure = TextEditingController(text: 'PN-42CrMo-520');
  final _parts = <_PartRow>[_PartRow()];
  final _witnesses = <_WitnessRow>[_WitnessRow(), _WitnessRow()];
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.registerBatch(
        furnaceId: _furnace.text.trim(),
        operator: _operator.text.trim(),
        procedureId: _procedure.text.trim(),
        parts: [
          for (final r in _parts)
            Part(
              partNo: r.no.text.trim(),
              material: r.material.text.trim(),
              pretreatment: r.pretreatment.text.trim(),
              fixturePosition: r.position.text.trim(),
            ),
        ],
        witnessSamples: [
          for (final r in _witnesses)
            WitnessSample(
              sampleNo: r.no.text.trim(),
              material: r.material.text.trim(),
              fixturePosition: r.position.text.trim(),
            ),
        ],
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = '${e.code}: ${e.message}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('批次登记 (材质/前处理/装夹/见证样)')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(child: TextFormField(
                controller: _furnace,
                decoration: const InputDecoration(labelText: '炉号'),
                validator: (v) => (v == null || v.isEmpty) ? '必填' : null,
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _operator,
                decoration: const InputDecoration(labelText: '操作员'),
                validator: (v) => (v == null || v.isEmpty) ? '必填' : null,
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _procedure,
                decoration:
                    const InputDecoration(labelText: '已批准工艺规程编号'),
                validator: (v) => (v == null || v.isEmpty) ? '必填' : null,
              )),
            ]),
            const SizedBox(height: 24),
            Text('工件 (材质/前处理/装夹位置)',
                style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < _parts.length; i++)
              _partTile(i),
            TextButton.icon(
              onPressed: () => setState(() => _parts.add(_PartRow())),
              icon: const Icon(Icons.add),
              label: const Text('添加工件'),
            ),
            const SizedBox(height: 16),
            Text('见证样', style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < _witnesses.length; i++)
              _witnessTile(i),
            TextButton.icon(
              onPressed: () => setState(() => _witnesses.add(_WitnessRow())),
              icon: const Icon(Icons.add),
              label: const Text('添加见证样'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '提交中…' : '登记批次'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _partTile(int i) {
    final r = _parts[i];
    return Row(children: [
      Expanded(child: TextFormField(
        controller: r.no,
        decoration: const InputDecoration(labelText: '工件号'),
      )),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(
        controller: r.material,
        decoration: const InputDecoration(labelText: '材质 (如 42CrMo)'),
      )),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(
        controller: r.pretreatment,
        decoration: const InputDecoration(labelText: '前处理 (调质+除油)'),
      )),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(
        controller: r.position,
        decoration: const InputDecoration(labelText: '装夹位置'),
      )),
      IconButton(
        onPressed: () => setState(() => _parts.removeAt(i)),
        icon: const Icon(Icons.delete_outline),
      ),
    ]);
  }

  Widget _witnessTile(int i) {
    final r = _witnesses[i];
    return Row(children: [
      Expanded(child: TextFormField(
        controller: r.no,
        decoration: const InputDecoration(labelText: '见证样编号'),
      )),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(
        controller: r.material,
        decoration: const InputDecoration(labelText: '材质'),
      )),
      const SizedBox(width: 8),
      Expanded(child: TextFormField(
        controller: r.position,
        decoration: const InputDecoration(labelText: '计划位置'),
      )),
      IconButton(
        onPressed: () => setState(() => _witnesses.removeAt(i)),
        icon: const Icon(Icons.delete_outline),
      ),
    ]);
  }
}

class _PartRow {
  final no = TextEditingController();
  final material = TextEditingController();
  final pretreatment = TextEditingController();
  final position = TextEditingController();
}

class _WitnessRow {
  final no = TextEditingController();
  final material = TextEditingController();
  final position = TextEditingController();
}
