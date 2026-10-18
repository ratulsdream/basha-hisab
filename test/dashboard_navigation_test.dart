import 'package:basha_hisab/features/groups/groups_screen.dart';
import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/features/expenses/home_screen.dart';
import 'package:basha_hisab/features/shell/app_preferences.dart';
import 'package:basha_hisab/features/shell/preferences_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeFirebaseFirestore db;
  late HouseholdRepository repository;
  Future<void> open(
    WidgetTester tester, {
    bool enabled = false,
    Locale locale = const Locale('en'),
    double scale = 1,
  }) async {
    repository = HouseholdRepository(
      firestore: db,
      auth: MockFirebaseAuth(mockUser: MockUser(uid: 'a'), signedIn: true),
      enableItemIntelligence: enabled,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('bn')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: HomeScreen(repository: repository, householdId: 'home'),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    await db.doc('households/home').set({
      'title': 'Our home',
      'memberIds': ['a', 'b'],
      'memberNames': {'a': 'Alice', 'b': 'Bob'},
      'currency': 'EUR',
      'inviteCode': 'a' * 32,
    });
    final now = DateTime.now();
    await db.doc('households/home/expenses/receipt').set({
      'merchant': 'ΑΛΦΑΜΕΓΑ',
      'payer': 'a',
      'createdBy': 'a',
      'date': Timestamp.fromDate(now),
      'month': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      'total': 1000,
      'itemCount': 0,
    });
  });
  testWidgets(
    'four destinations preserve history and useful gated catalog; no source data changes',
    (tester) async {
      final original = (await db.doc('households/home/expenses/receipt').get())
          .data();
      await open(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('EUR 10.00'), findsWidgets);
      expect(find.text('Scan Receipt'), findsOneWidget);
      expect(find.text('Add Expense'), findsOneWidget);
      await tester.tap(find.text('Items').last);
      await tester.pumpAndSettle();
      expect(find.text('Security review needed'), findsOneWidget);
      expect(find.text('Automatic Items Library'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      await tester.tap(find.text('History').last);
      await tester.pumpAndSettle();
      expect(find.text('ΑΛΦΑΜΕΓΑ'), findsOneWidget);
      expect(find.text('Search and filters'), findsOneWidget);
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      expect(find.text('Manage groups'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Language & appearance'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Language & appearance'), findsOneWidget);
      expect(
        (await db.doc('households/home/expenses/receipt').get()).data(),
        original,
      );
      expect(
        (await db.collection('households/home/catalog').get()).docs,
        isEmpty,
      );
    },
  );
  testWidgets(
    'enabled dashboard settlement includes repayments and quick shopping opens correct tab',
    (tester) async {
      final now = DateTime.now();
      final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      await db.doc('households/home/payments/p').set({
        'from': 'b',
        'to': 'a',
        'date': Timestamp.fromDate(now),
        'month': month,
        'amount': 500,
      });
      await open(tester, enabled: true);
      await tester.scrollUntilVisible(
        find.text('All square — no one owes anything.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('All square — no one owes anything.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Shopping List'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Shopping List'));
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsOneWidget);
      final controller = DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      );
      expect(controller.index, 2);
    },
  );
  testWidgets(
    'small Bengali screen with enlarged text keeps navigation usable and Greek data intact',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, locale: const Locale('bn'), scale: 1.6);
      expect(find.text('হোম'), findsOneWidget);
      expect(find.text('রসিদ স্ক্যান'), findsOneWidget);
      await tester.tap(find.text('হিসাব').last);
      await tester.pumpAndSettle();
      expect(find.text('ΑΛΦΑΜΕΓΑ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('language and dark appearance persist without Firestore writes', (
    tester,
  ) async {
    await AppPreferences.instance.load();
    await tester.pumpWidget(MaterialApp(home: const PreferencesScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ui.language'), 'bn');
    expect(prefs.getString('ui.theme'), 'dark');
    await AppPreferences.instance.load();
    expect(AppPreferences.instance.language, 'bn');
    expect(AppPreferences.instance.theme, ThemeMode.dark);
    await AppPreferences.instance.update(locale: 'en', mode: ThemeMode.system);
  });
  testWidgets(
    'group switcher returns to membership list and remembers a separate home',
    (tester) async {
      repository = HouseholdRepository(
        firestore: db,
        auth: MockFirebaseAuth(
          mockUser: MockUser(uid: 'a', email: 'a@example.com'),
          signedIn: true,
        ),
      );
      final original = (await db.doc('households/home').get()).data()!;
      await db.doc('households/other').set({
        ...original,
        'title': 'Second home',
      });
      for (final id in ['home', 'other']) {
        await db.doc('users/a/memberships/$id').set({
          'uid': 'a',
          'groupId': id,
          'displayName': 'Alice',
          'joinedAt': Timestamp.now(),
          'inviteCode': 'a' * 32,
        });
      }
      await tester.pumpWidget(
        MaterialApp(home: GroupsScreen(repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Our home'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.byTooltip('Switch group'));
      await tester.pumpAndSettle();
      expect(find.text('My Groups / Homes'), findsOneWidget);
      await tester.tap(find.text('Second home'));
      await tester.pumpAndSettle();
      expect(find.text('Second home'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('v2.lastGroup.a'), 'other');
      await tester.tap(find.text('History').last);
      await tester.pumpAndSettle();
      expect(find.text('ΑΛΦΑΜΕΓΑ'), findsNothing);
      expect(
        (await db.doc('households/home/expenses/receipt').get()).exists,
        true,
      );
    },
  );
}
