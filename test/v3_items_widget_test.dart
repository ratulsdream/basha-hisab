import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/features/items/items_screen.dart';
import 'package:basha_hisab/features/items/items_repository.dart';
import 'package:basha_hisab/features/items/items_domain.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final home = Household('home', {
    'memberIds': ['a', 'b'],
    'memberNames': {'a': 'A', 'b': 'B'},
    'currency': 'EUR',
    'inviteCode': 'a' * 32,
  });
  testWidgets(
    'production gate prevents module reads/writes until security verification',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
        MaterialApp(
          home: ItemsScreen(
            repository: ItemsRepository(db, 'a', 'home'),
            household: home,
            enabled: false,
          ),
        ),
      );
      expect(find.text('Security review needed'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
    },
  );
  testWidgets(
    'enabled isolated build shows group-specific module tabs and library',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('households/home/catalog/${itemKey('Milk')}').set({
        'name': 'Milk',
        'category': 'food',
        'mergedInto': '',
        'revision': 0,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ItemsScreen(
            repository: ItemsRepository(db, 'a', 'home'),
            household: home,
            enabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Regular items'), findsOneWidget);
      expect(find.text('Kitchen'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
