import 'package:flutter/material.dart';
import '../../domain.dart';

class FinanceField {
  const FinanceField(
    this.keyName,
    this.label, {
    this.initial = '',
    this.choices,
    this.flag = false,
    this.readOnly = false,
    this.required = false,
    this.money = false,
    this.integer = false,
    this.date = false,
    this.positive = false,
  });
  final String keyName, label, initial;
  final Map<String, String>? choices;
  final bool flag, readOnly, required, money, integer, date, positive;
}

Future<Map<String, String>?> financeForm(
  BuildContext context,
  String title,
  List<FinanceField> fields,
) => showDialog<Map<String, String>>(
  context: context,
  builder: (_) => _FinanceForm(title: title, fields: fields),
);

class _FinanceForm extends StatefulWidget {
  const _FinanceForm({required this.title, required this.fields});
  final String title;
  final List<FinanceField> fields;
  @override
  State<_FinanceForm> createState() => _FinanceFormState();
}

class _FinanceFormState extends State<_FinanceForm> {
  final form = GlobalKey<FormState>();
  late final controllers = {
    for (final f in widget.fields)
      f.keyName: TextEditingController(text: f.initial),
  };
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _field(f),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, {
              for (final f in widget.fields)
                f.keyName: controllers[f.keyName]!.text.trim(),
            });
          }
        },
        child: const Text('Confirm'),
      ),
    ],
  );
  Widget _field(FinanceField f) {
    final c = controllers[f.keyName]!;
    if (f.flag) {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: c.text == 'true',
        onChanged: f.readOnly ? null : (v) => setState(() => c.text = '$v'),
        title: Text(f.label),
      );
    }
    if (f.choices != null) {
      final value = f.choices!.containsKey(c.text)
          ? c.text
          : f.choices!.keys.first;
      c.text = value;
      return DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: f.label),
        items: f.choices!.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: f.readOnly ? null : (v) => c.text = v!,
      );
    }
    return TextFormField(
      controller: c,
      readOnly: f.readOnly,
      maxLength: f.money || f.integer || f.date ? null : 300,
      keyboardType: f.money || f.integer
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: f.label,
        suffixIcon: f.date
            ? IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100, 12, 31),
                    initialDate: DateTime.tryParse(c.text) ?? DateTime.now(),
                  );
                  if (value != null) {
                    c.text = value.toIso8601String().split('T').first;
                  }
                },
              )
            : null,
      ),
      validator: (v) {
        final text = v?.trim() ?? '';
        if (f.required && text.isEmpty) return 'Required';
        if (text.isEmpty) return null;
        if (f.money &&
            (parseMoney(text) == null ||
                (f.positive
                    ? parseMoney(text)! <= 0
                    : parseMoney(text)! < 0))) {
          return 'Enter a valid amount';
        }
        if (f.integer && int.tryParse(text) == null) {
          return 'Enter a whole number';
        }
        if (f.date) {
          final date = DateTime.tryParse(text);
          if (date == null ||
              date.year < 2000 ||
              date.year > 2100 ||
              date.toIso8601String().split('T').first != text) {
            return 'Use YYYY-MM-DD';
          }
        }
        return null;
      },
    );
  }
}
