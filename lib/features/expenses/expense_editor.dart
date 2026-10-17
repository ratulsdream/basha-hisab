import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data.dart';
import '../../domain.dart';
import '../items/items_repository.dart';
import '../planning/planning_repository.dart';
import '../planning/planning_domain.dart';
import '../planning/expense_options.dart';
import '../items/items_domain.dart';
import '../items/items_screen.dart' show quantityMilliInput;

import '../../widgets/common.dart';

class _ItemFields {
  _ItemFields([ExpenseItem? item])
    : name = TextEditingController(text: item?.name ?? ''),
      amount = TextEditingController(
        text: item == null ? '' : moneyInput(item.amount),
      ),
      quantity = TextEditingController(
        text: item?.quantityMilli == null
            ? ''
            : '${item!.quantityMilli! / 1000}',
      ),
      unit = item?.unit ?? 'each';
  final TextEditingController name, amount;
  final TextEditingController quantity;
  String unit;
  void dispose() {
    name.dispose();
    amount.dispose();
    quantity.dispose();
  }
}

class ExpenseEditor extends StatefulWidget {
  const ExpenseEditor({
    super.key,
    required this.repository,
    required this.household,
    required this.draft,
    required this.fromReceipt,
  });
  final HouseholdRepository repository;
  final Household household;
  final ReceiptDraft draft;
  final bool fromReceipt;
  @override
  State<ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<ExpenseEditor> {
  final _form = GlobalKey<FormState>();
  late final _merchant = TextEditingController(text: widget.draft.merchant);
  late final _total = TextEditingController(
    text: widget.draft.total == null ? '' : moneyInput(widget.draft.total!),
  );
  late final List<_ItemFields> _items = widget.draft.items
      .map(_ItemFields.new)
      .toList();
  late DateTime _date = widget.draft.date ?? DateTime.now();
  late String _payer = widget.repository.uid;
  late final String _id = widget.repository.newExpenseId(widget.household.id);
  bool _saving = false, _reviewed = false, _checkingDuplicate = false;
  String? _acknowledgedDuplicate;
  bool _personal = false, _refund = false;
  String _category = 'uncategorized', _splitMode = 'equal';
  final _splitValue = TextEditingController(text: '50');
  String? _error;
  @override
  void dispose() {
    _merchant.dispose();
    _splitValue.dispose();
    _total.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _checkingDuplicate) return;
    // Validate controllers as well as mounted fields: long receipts are lazy
    // lists, and fields outside the viewport may not currently be in the Form.
    final parsedTotal = parseMoney(_total.text);
    String? validationError;
    if (_merchant.text.trim().isEmpty || _merchant.text.trim().length > 100) {
      validationError =
          'Enter a merchant or expense name (up to 100 characters).';
    } else if (parsedTotal == null || parsedTotal <= 0) {
      validationError = 'Enter a total greater than zero (up to 10,000,000).';
    } else {
      for (var index = 0; index < _items.length; index++) {
        final item = _items[index];
        if (widget.repository.enableItemIntelligence &&
            item.quantity.text.trim().isNotEmpty &&
            quantityMilliInput(item.quantity.text) == null) {
          validationError =
              'Check item ${index + 1}: enter a positive quantity with up to three decimals, or leave it blank.';
          break;
        }
        if (item.name.text.trim().isEmpty ||
            item.name.text.trim().length > 100 ||
            parseMoney(item.amount.text) == null) {
          validationError =
              'Check item ${index + 1}: enter a name up to 100 characters and a valid price.';
          break;
        }
      }
    }
    final visibleFieldsValid = _form.currentState!.validate();
    if (validationError != null || !visibleFieldsValid) {
      setState(() => _error = validationError);
      return;
    }

    if (widget.fromReceipt && !_reviewed) {
      setState(
        () => _error =
            'Review the receipt fields and confirm the checkbox before saving.',
      );
      return;
    }
    final total = parseMoney(_total.text)!;
    final itemTotal = _items.fold<int>(
      0,
      (runningTotal, item) => runningTotal + parseMoney(item.amount.text)!,
    );
    if (_items.isNotEmpty && itemTotal != total) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Items and total differ'),
          content: Text(
            'Items add up to ${displayMoney(widget.household.currency, itemTotal)}, but the receipt total is ${displayMoney(widget.household.currency, total)}. This may be tax, a discount, or an OCR mistake. Save this total?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save this total'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    Map<String, int>? splitCents;
    if (widget.repository.enableItemIntelligence &&
        !_personal &&
        _splitMode != 'equal' &&
        widget.household.members.length == 2) {
      try {
        final ids = [...widget.household.members]..sort();
        final value = parseMoney(_splitValue.text);
        if (value == null) throw StateError('Enter a valid share.');
        splitCents = _splitMode == 'percentage'
            ? percentageSplit(total, {ids[0]: value, ids[1]: 10000 - value})
            : fixedSplit(total, {ids[0]: value, ids[1]: total - value});
      } catch (e) {
        setState(
          () => _error =
              'Shares must be nonnegative and add up to the exact total / 100%.',
        );
        return;
      }
    }
    String? signature;
    if (widget.repository.enableItemIntelligence) {
      signature = receiptSignature(
        merchant: _merchant.text,
        date: _date,
        total: total,
        items: _items.map(
          (i) => (name: i.name.text, amount: parseMoney(i.amount.text)!),
        ),
      );
      if (_acknowledgedDuplicate != signature) {
        setState(() => _checkingDuplicate = true);
        try {
          final matches = _personal
              ? await PlanningRepository(
                  widget.repository.db,
                  widget.repository.uid,
                  widget.household.id,
                ).personalDuplicates(signature, widget.draft.imageHash)
              : await ItemsRepository(
                  widget.repository.db,
                  widget.repository.uid,
                  widget.household.id,
                ).duplicates(signature, widget.draft.imageHash);
          if (matches.any((m) => m.expenseId != _id)) {
            if (!mounted) return;
            final proceed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Possible duplicate receipt'),
                content: const Text(
                  'A saved expense has matching image or receipt details. This may still be a separate purchase. Review history before deciding.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep editing'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save as separate purchase'),
                  ),
                ],
              ),
            );
            if (proceed != true) return;
          }
          _acknowledgedDuplicate = signature;
        } catch (e) {
          if (mounted) setState(() => _error = friendlyError(e));
          return;
        } finally {
          if (mounted) setState(() => _checkingDuplicate = false);
        }
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.repository.enableItemIntelligence) {
        await widget.repository.savePlannedExpense(
          personal: _personal,
          category: _category,
          refund: _refund,
          splitCents: splitCents,
          household: widget.household,
          id: _id,
          merchant: _merchant.text.trim(),
          payer: _payer,
          date: _date,
          items: _items
              .map(
                (item) => ExpenseItem(
                  item.name.text.trim(),
                  parseMoney(item.amount.text)!,
                  quantityMilli: quantityMilliInput(item.quantity.text),
                  unit: item.unit,
                ),
              )
              .toList(),
          total: total,
        );
      } else {
        await widget.repository.saveExpense(
          household: widget.household,
          id: _id,
          merchant: _merchant.text.trim(),
          payer: _payer,
          date: _date,
          items: _items
              .map(
                (item) => ExpenseItem(
                  item.name.text.trim(),
                  parseMoney(item.amount.text)!,
                  quantityMilli: quantityMilliInput(item.quantity.text),
                  unit: item.unit,
                ),
              )
              .toList(),
          total: total,
        );
      }
      if (signature != null) {
        if (_personal) {
          await PlanningRepository(
            widget.repository.db,
            widget.repository.uid,
            widget.household.id,
          ).recordPersonalSignature(_id, signature, widget.draft.imageHash);
        } else {
          await ItemsRepository(
            widget.repository.db,
            widget.repository.uid,
            widget.household.id,
          ).recordSignature(_id, signature, widget.draft.imageHash);
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.fromReceipt ? 'Review receipt' : 'Add expense'),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.repository.enableItemIntelligence)
                ExpenseOptions(
                  home: widget.household,
                  personal: _personal,
                  refund: _refund,
                  category: _category,
                  splitMode: _splitMode,
                  splitValue: _splitValue,
                  change:
                      ({
                        bool? personal,
                        bool? refund,
                        String? category,
                        String? splitMode,
                      }) => setState(() {
                        if (personal != null) {
                          _personal = personal;
                          if (personal) _payer = widget.repository.uid;
                        }
                        if (refund != null) _refund = refund;
                        if (category != null) _category = category;
                        if (splitMode != null) _splitMode = splitMode;
                      }),
                ),
              if (widget.fromReceipt)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Check every field before saving. OCR can miss or misread text. Only extracted data is shared; the receipt image stays on this device.',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Greek and English are processed offline. Dates are day-first when the year is last. Highlighted suggestions need particular attention.',
                        ),
                        for (final warning in widget.draft.warnings)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '⚠ $warning',
                              style: const TextStyle(color: Colors.deepOrange),
                            ),
                          ),
                        if (widget.draft.rawText.isEmpty)
                          const Text(
                            'No text was detected. Enter the details below.',
                          ),
                        if (widget.draft.rawText.isNotEmpty)
                          ExpansionTile(
                            title: const Text('View detected text'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: SelectableText(widget.draft.rawText),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _merchant,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: 'Merchant / expense name',
                  helperText:
                      widget.fromReceipt && widget.draft.merchant.isEmpty
                      ? 'Not detected — enter merchant'
                      : null,
                  filled: widget.fromReceipt && widget.draft.merchant.isEmpty,
                  fillColor: Theme.of(context).colorScheme.tertiaryContainer,
                ),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ||
                        value!.trim().length > 100
                    ? 'Enter a name up to 100 characters.'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _payer,
                decoration: const InputDecoration(labelText: 'Who paid?'),
                items: widget.household.members
                    .where((uid) => !_personal || uid == widget.repository.uid)
                    .map(
                      (id) => DropdownMenuItem(
                        value: id,
                        child: Text(widget.household.name(id)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _payer = value!),
              ),
              const SizedBox(height: 12),
              if (widget.fromReceipt && widget.draft.date == null)
                const Text(
                  '⚠ Date not detected — select the receipt date',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(DateFormat.yMMMd().format(_date)),
              ),
              const SizedBox(height: 20),
              Text(
                'Items (optional)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Use each line’s total price, including quantity. Up to 100 items.',
              ),
              for (var i = 0; i < _items.length; i++)
                Padding(
                  key: ObjectKey(_items[i]),
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _items[i].name,
                              maxLength: 100,
                              decoration: InputDecoration(
                                labelText: 'Item ${i + 1}',
                              ),
                              validator: (value) =>
                                  (value?.trim().isEmpty ?? true) ||
                                      value!.trim().length > 100
                                  ? 'Use 1–100 characters.'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _items[i].amount,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Price',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: (value) =>
                                  parseMoney(value ?? '') == null
                                  ? 'Invalid price'
                                  : null,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove item',
                            onPressed: () {
                              final item = _items[i];
                              setState(() => _items.removeAt(i));
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => item.dispose(),
                              );
                            },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                      if (widget.repository.enableItemIntelligence)
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _items[i].quantity,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Reviewed quantity (optional)',
                                  helperText: 'Leave blank when unknown',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _items[i].unit,
                                items: itemUnits
                                    .map(
                                      (u) => DropdownMenuItem(
                                        value: u,
                                        child: Text(u),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (u) =>
                                    setState(() => _items[i].unit = u!),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: _items.length < 100
                    ? () => setState(() => _items.add(_ItemFields()))
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
              if (_items.isNotEmpty)
                TextButton(
                  onPressed: () {
                    var sum = 0;
                    for (final item in _items) {
                      final price = parseMoney(item.amount.text);
                      if (price == null) {
                        setState(
                          () => _error = 'Enter valid item prices first.',
                        );
                        return;
                      }
                      sum += price;
                    }
                    setState(() => _total.text = moneyInput(sum));
                  },
                  child: const Text('Use sum of item prices as total'),
                ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _total,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Total (${widget.household.currency})',
                  helperText: widget.fromReceipt && widget.draft.total == null
                      ? 'Not detected — enter the printed total'
                      : 'This total determines your shared spending.',
                  filled: widget.fromReceipt && widget.draft.total == null,
                  fillColor: Theme.of(context).colorScheme.tertiaryContainer,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final amount = parseMoney(value ?? '');
                  return amount == null || amount <= 0
                      ? 'Enter a total greater than zero (up to 10,000,000).'
                      : null;
                },
              ),
              if (_items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Items sum: ${displayMoney(widget.household.currency, _items.fold<int>(0, (sum, item) => sum + (parseMoney(item.amount.text) ?? 0)))}  ·  Receipt total: ${_total.text}',
                    style: TextStyle(
                      color:
                          _items.fold<int>(
                                0,
                                (sum, item) =>
                                    sum + (parseMoney(item.amount.text) ?? 0),
                              ) ==
                              parseMoney(_total.text)
                          ? null
                          : Colors.deepOrange,
                    ),
                  ),
                ),
              if (widget.fromReceipt)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reviewed,
                  onChanged: (value) => setState(() => _reviewed = value!),
                  title: const Text(
                    'I reviewed the merchant, date, payer, items and total.',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving || _checkingDuplicate ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _saving ? 'Saving — waiting for sync…' : 'Save expense',
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Keep this screen open. If offline, saving completes when the connection returns.',
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}
