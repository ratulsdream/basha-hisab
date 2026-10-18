@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:js_interop_unsafe';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/domain.dart';
import 'package:basha_hisab/features/items/feature_gate.dart';
import 'package:basha_hisab/features/items/items_repository.dart';
import 'package:basha_hisab/features/planning/planning_repository.dart';
import 'package:basha_hisab/features/planning/planning_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

@JS('window.addEventListener')
external void browserEvent(JSString name, JSFunction listener);

@JS('document.createElement')
external JSObject createElement(JSString name);
@JS('document.head.appendChild')
external void appendElement(JSObject element);
Future<void> loadTestSdk() async {
  final script = createElement('script'.toJS);
  final loaded = Completer<void>();
  script['type'] = 'module'.toJS;
  script['src'] = 'http://127.0.0.1:9030/firebase-sdk.js'.toJS;
  script['onload'] = ((JSAny? _) {
    loaded.complete();
  }).toJS;
  script['onerror'] = ((JSAny? _) {
    loaded.completeError(
      StateError(
        'The local, locked test SDK bundle could not load. Start tool/run_web_repository_tests.sh.',
      ),
    );
  }).toJS;
  appendElement(script);
  await loaded.future.timeout(const Duration(seconds: 15));
}

/// Real FlutterFire SDKs + actual local emulators; never fake Firestore or production config.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Browser unit-test runners do not run an app's generated plugin registrant.
  // These are the genuine FlutterFire implementations, not test mocks.
  FirebaseCoreWeb.registerWith(webPluginRegistrar);
  FirebaseAuthWeb.registerWith(webPluginRegistrar);
  FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
  browserEvent(
    'unhandledrejection'.toJS,
    ((JSObject event) {
      final reason = event.getProperty<JSObject>('reason'.toJS);
      debugPrint(
        'Browser promise rejection: ${reason.callMethod<JSString>('toString'.toJS).toDart}',
      );
    }).toJS,
  );
  test(
    'enabled real repositories preserve expenses, share with members and isolate groups',
    () async {
      expect(
        v3ItemsEnabled,
        true,
        reason: 'Run with --dart-define=V3_ENABLED=true',
      );
      debugPrint('EMULATOR: load the integrity-locked local browser SDK');
      await loadTestSdk();
      final apps = <FirebaseApp>[];
      Future<HouseholdRepository> account(String label) async {
        debugPrint('EMULATOR: initialize Firebase app for $label');
        final app = await Firebase.initializeApp(
          name: '$label-${DateTime.now().microsecondsSinceEpoch}',
          options: const FirebaseOptions(
            apiKey: 'demo-key',
            appId: '1:1234567890:web:emulator',
            messagingSenderId: '1234567890',
            projectId: 'demo-bashahisab',
          ),
        ).timeout(const Duration(seconds: 30));
        debugPrint('EMULATOR: Firebase app initialized for $label');
        apps.add(app);
        final auth = FirebaseAuth.instanceFor(app: app);
        debugPrint('EMULATOR: configure Auth and Firestore for $label');
        await auth.useAuthEmulator('127.0.0.1', 9099);
        final db = FirebaseFirestore.instanceFor(app: app);
        db.settings = const Settings(persistenceEnabled: false);
        db.useFirestoreEmulator('127.0.0.1', 8080, automaticHostMapping: false);
        debugPrint('EMULATOR: create local account for $label');
        await auth.createUserWithEmailAndPassword(
          email: '$label-${DateTime.now().microsecondsSinceEpoch}@example.test',
          password: 'Only-for-emulators-2026',
        );
        final repo = HouseholdRepository(
          auth: auth,
          firestore: db,
          enableItemIntelligence: v3ItemsEnabled,
        );
        debugPrint('EMULATOR: ensure profile for $label');
        await repo.ensureProfile();
        debugPrint('EMULATOR: profile ready for $label');
        return repo;
      }

      final a = await account('alice'),
          b = await account('bob'),
          outsider = await account('outsider');
      debugPrint('EMULATOR: create group');
      final id = await a.createHousehold('Emulator home', 'EUR');
      var home = Household(
        id,
        (await a.db.collection('households').doc(id).get()).data()!,
      );
      debugPrint('EMULATOR: join group');
      await b.joinHousehold(home.inviteCode);
      home = Household(
        id,
        (await a.db.collection('households').doc(id).get()).data()!,
      );
      final date = DateTime(2026, 10, 18);
      Future<void> save() => a.savePlannedExpense(
        household: home,
        id: 'stable-receipt',
        merchant: 'ΑΛΦΑΜΕΓΑ',
        payer: a.uid,
        date: date,
        items: [
          const ExpenseItem('ΓΑΛΑ', 1000, quantityMilli: 2000, unit: 'each'),
        ],
        total: 1000,
        category: 'food',
      );
      debugPrint('EMULATOR: save receipt and retry stable ID');
      await save();
      await save();
      final shared = b.db.collection('households').doc(id);
      expect((await shared.collection('expenses').get()).docs.length, 1);
      expect(
        (await shared
                .collection('expenses')
                .doc('stable-receipt')
                .collection('items')
                .get())
            .docs
            .single
            .data()['name'],
        'ΓΑΛΑ',
      );
      debugPrint('EMULATOR: purchase indexing and stock');
      final items = ItemsRepository(a.db, a.uid, id);
      final purchaseDoc =
          (await items.collection('purchases').get()).docs.single;
      final purchase = purchaseFromMap(purchaseDoc.id, purchaseDoc.data());
      await items.restock(purchase, quantityMilli: 2000, unit: 'each');
      await items.restock(purchase, quantityMilli: 2000, unit: 'each');
      await items.consume('receipt_${purchase.id}', 500, 'consume-once');
      await items.consume('receipt_${purchase.id}', 500, 'consume-once');
      expect(
        (await items.collection('stock').doc('receipt_${purchase.id}').get())
            .data()!['quantityMilli'],
        1500,
      );
      debugPrint('EMULATOR: budget and payments');
      final planning = PlanningRepository(a.db, a.uid, id);
      await planning.setBudget('2026-10', 5000, {'food': 3000}, -1);
      await planning.recordPayment(
        id: 'settle-once',
        from: b.uid,
        to: a.uid,
        amount: 500,
        date: date,
      );
      await planning.recordPayment(
        id: 'settle-once',
        from: b.uid,
        to: a.uid,
        amount: 500,
        date: date,
      );
      final expenses = (await shared.collection('expenses').get()).docs.map(
        (d) => financeFromMap(d.id, d.data()),
      );
      final transfers = (await shared.collection('payments').get()).docs.map(
        (d) => paymentFromMap(d.id, d.data()),
      );
      expect(
        financeSettlement(
          home.members,
          home.legacyMembers,
          expenses,
          transfers,
        ).transfers,
        isEmpty,
      );
      await expectLater(
        outsider.db
            .collection('households')
            .doc(id)
            .collection('expenses')
            .get(const GetOptions(source: Source.server)),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      await a.savePlannedExpense(
        household: home,
        id: 'private',
        merchant: 'Private',
        payer: a.uid,
        date: date,
        items: [],
        total: 500,
        personal: true,
      );
      await expectLater(
        b.db
            .collection('users')
            .doc(a.uid)
            .collection('personalExpenses')
            .get(const GetOptions(source: Source.server)),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      debugPrint('EMULATOR: second group and leave preservation');
      final second = await a.createHousehold('Second emulator home', 'EUR');
      expect((await a.watchMemberships().first).docs.length, 2);
      expect(
        (await a.db
                .collection('households')
                .doc(second)
                .collection('expenses')
                .get())
            .docs,
        isEmpty,
      );
      await b.leaveGroup(id);
      await expectLater(
        shared
            .collection('expenses')
            .get(const GetOptions(source: Source.server)),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      expect(
        (await a.db
                .collection('households')
                .doc(id)
                .collection('expenses')
                .get())
            .docs
            .single
            .id,
        'stable-receipt',
      );
      for (final app in apps) {
        await FirebaseAuth.instanceFor(app: app).signOut();
        await app.delete();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
