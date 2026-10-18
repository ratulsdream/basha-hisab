import 'package:flutter/material.dart';
import '../../l10n/app_text.dart';

class FeatureAvailability extends StatelessWidget {
  const FeatureAvailability({
    super.key,
    required this.features,
    this.onHistory,
  });
  final List<({IconData icon, String title, String subtitle})> features;
  final VoidCallback? onHistory;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 28),
                SizedBox(height: 12),
                AppText(
                  'Security review needed',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                SizedBox(height: 8),
                AppText(
                  'Your saved expenses are still available. These tools will open after your home’s access permissions have been verified.',
                ),
              ],
            ),
          ),
        ),
        for (final f in features)
          Card(
            child: ListTile(
              leading: Icon(f.icon),
              title: AppText(f.title),
              subtitle: AppText(f.subtitle),
              trailing: const Icon(Icons.lock_outline),
            ),
          ),
        if (onHistory != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: FilledButton.icon(
              onPressed: onHistory,
              icon: const Icon(Icons.history),
              label: const AppText('View expense history'),
            ),
          ),
        const ExpansionTile(
          title: AppText('How to enable safely'),
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: AppText(
                'Ask the account owner to provide the currently published database rules for review. No rules or saved data are changed here.',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

const itemFeatures = [
  (
    icon: Icons.inventory_2_outlined,
    title: 'Automatic Items Library',
    subtitle: 'Saved items from reviewed receipts',
  ),
  (
    icon: Icons.repeat,
    title: 'Regular Items',
    subtitle: 'Frequently purchased items',
  ),
  (
    icon: Icons.shopping_basket_outlined,
    title: 'Shared Shopping List',
    subtitle: 'Plan your next shopping trip',
  ),
  (
    icon: Icons.kitchen_outlined,
    title: 'Kitchen Inventory',
    subtitle: 'Track stock and expiry dates',
  ),
  (
    icon: Icons.trending_up,
    title: 'Item Price History',
    subtitle: 'Compare previous prices',
  ),
];
const planningFeatures = [
  (
    icon: Icons.pie_chart_outline,
    title: 'Category breakdown',
    subtitle: 'Monthly expense history',
  ),
  (
    icon: Icons.account_balance_wallet_outlined,
    title: 'Budget settings',
    subtitle: 'Monthly budget',
  ),
  (
    icon: Icons.payments_outlined,
    title: 'Payment history',
    subtitle: 'Settlement',
  ),
  (icon: Icons.repeat, title: 'Recurring bills', subtitle: 'Recurring'),
  (
    icon: Icons.person_outline,
    title: 'Personal & shared expenses',
    subtitle: 'History',
  ),
  (
    icon: Icons.download_outlined,
    title: 'Export PDF / Excel',
    subtitle: 'Monthly expense history',
  ),
];
