import 'dart:async';
import 'package:basha_hisab/data.dart';
import 'package:basha_hisab/features/groups/groups_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PendingProfileRepository extends HouseholdRepository {
  _PendingProfileRepository()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          mockUser: MockUser(uid: 'alice', email: 'alice@example.com'),
          signedIn: true,
        ),
      );
  final complete = Completer<void>();
  @override
  Future<void> ensureProfile() => complete.future;
}

void main() {
  testWidgets(
    'signed-in groups shell appears before profile recovery completes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = _PendingProfileRepository();
      await tester.pumpWidget(
        MaterialApp(home: GroupsScreen(repository: repository)),
      );
      await tester.pump();
      expect(find.text('My Groups / Homes'), findsOneWidget);
      expect(find.byTooltip('Personal profile'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      repository.complete.complete();
      await tester.pumpAndSettle();
      expect(find.text('Create group'), findsOneWidget);
      expect(find.text('Join with invite code'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
