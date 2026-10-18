import 'package:basha_hisab/l10n/app_text.dart';
import 'package:flutter/material.dart';
import '../../data.dart';
import 'planning_domain.dart';

class ExpenseOptions extends StatelessWidget {
  const ExpenseOptions({
    super.key,
    required this.home,
    required this.personal,
    required this.refund,
    required this.category,
    required this.splitMode,
    required this.splitValue,
    required this.change,
  });
  final Household home;
  final bool personal, refund;
  final String category, splitMode;
  final TextEditingController splitValue;
  final void Function({
    bool? personal,
    bool? refund,
    String? category,
    String? splitMode,
  })
  change;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          SwitchListTile(
            value: personal,
            onChanged: (v) => change(personal: v),
            title: const Text('Personal expense'),
            subtitle: const Text(
              'Personal details are private to your account and excluded from the group split.',
            ),
          ),
          SwitchListTile(
            value: refund,
            onChanged: (v) => change(refund: v),
            title: const AppText('Refund'),
            subtitle: const Text(
              'Enter a positive amount; a refund reduces spending.',
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: InputDecoration(labelText: tr(context, 'Category')),
            items: expenseCategories
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => change(category: v!),
          ),
          if (!personal && home.members.length == 2) ...[
            DropdownButtonFormField<String>(
              initialValue: splitMode,
              decoration: InputDecoration(
                labelText: tr(context, 'Shared split'),
              ),
              items: const [
                DropdownMenuItem(value: 'equal', child: Text('Equal 50/50')),
                DropdownMenuItem(
                  value: 'percentage',
                  child: Text('Custom percentage'),
                ),
                DropdownMenuItem(value: 'fixed', child: Text('Fixed amounts')),
              ],
              onChanged: (v) => change(splitMode: v!),
            ),
            if (splitMode != 'equal')
              TextField(
                controller: splitValue,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      '${home.name(([...home.members]..sort()).first)} share ${splitMode == 'percentage' ? '(%)' : '(${home.currency})'}',
                  helperText: 'The other member receives the exact remainder.',
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
