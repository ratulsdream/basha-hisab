import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'domain.dart';
import 'features/items/items_repository.dart';
import 'features/planning/planning_domain.dart';
import 'package:flutter/foundation.dart' show mapEquals;

String friendlyError(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'invalid-email' => 'Enter a valid email address.',
      'weak-password' => 'Choose a stronger password (at least 6 characters).',
      'email-already-in-use' =>
        'This email already has an account. Try signing in.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'The email or password is incorrect.',
      'network-request-failed' || 'unavailable' =>
        'Cannot reach the server. Check your connection and try again.',
      'permission-denied' =>
        'This action is not allowed. The group may be full or its membership changed. Check the invite, reopen the group, and verify the v2 Firestore rules are deployed.',
      'too-many-requests' => 'Too many attempts. Please wait and try again.',
      'failed-precondition' =>
        'Firebase is not ready. Check that Firestore is enabled and its rules are deployed.',
      _ => 'Could not complete the request (${error.code}). Please try again.',
    };
  }
  if (error is TimeoutException) {
    return 'This is taking too long. Check your connection and retry. Your account and saved data are safe.';
  }
  if (error is StateError) return error.message;
  return 'Something went wrong. Please try again.';
}

class Household {
  Household(this.id, Map<String, dynamic> data)
    : members = List<String>.from(data['memberIds'] as List),
      names = Map<String, String>.from(data['memberNames'] as Map),
      currency = data['currency'] as String,
      inviteCode = data['inviteCode'] as String,
      title = data['title'] as String? ?? 'Shared home',
      maxMembers = data['maxMembers'] as int? ?? 2,
      legacyMembers = List<String>.from(
        data['legacyMemberIds'] as List? ?? data['memberIds'] as List,
      );
  final String id;
  final String title;
  final int maxMembers;
  final List<String> members, legacyMembers;
  final Map<String, String> names;
  final String currency;
  final String inviteCode;
  String name(String id) => names[id] ?? 'Roommate';
}

class Expense {
  Expense(this.id, Map<String, dynamic> data)
    : merchant = data['merchant'] as String,
      payer = data['payer'] as String,
      creator = data['createdBy'] as String,
      date = (data['date'] as Timestamp).toDate().toUtc(),
      total = data['total'] as int,
      itemCount = data['itemCount'] as int,
      category = data['category'] as String? ?? 'uncategorized',
      refund = data['kind'] == 'refund',
      voided = data['voided'] == true,
      splits = data['splitCents'] == null
          ? null
          : Map<String, int>.from(data['splitCents'] as Map),
      splitBetween = data['splitBetween'] == null
          ? null
          : List<String>.from(data['splitBetween'] as List);
  final String id, merchant, payer, creator;
  final DateTime date;
  final int total;
  final int itemCount;
  final List<String>? splitBetween;
  final String category;
  final bool refund, voided;
  final Map<String, int>? splits;
}

class HouseholdRepository {
  HouseholdRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this.enableItemIntelligence = false,
  }) : db = firestore ?? FirebaseFirestore.instance,
       auth = auth ?? FirebaseAuth.instance;
  final bool enableItemIntelligence;
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  String get uid => auth.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get profile =>
      db.collection('users').doc(uid);
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchProfile() =>
      profile.snapshots();
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchHousehold(String id) =>
      db.collection('households').doc(id).snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> watchExpenses(
    String household,
    DateTime month,
  ) => db
      .collection('households')
      .doc(household)
      .collection('expenses')
      .where('month', isEqualTo: monthKey(month))
      .snapshots(includeMetadataChanges: true);

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMemberships() =>
      profile.collection('memberships').snapshots();

  /// Idempotent and safe after Auth succeeds but profile creation fails.
  /// Legacy identity fields are retained as migration hints, never used to select a home.
  Future<void> ensureProfile() async {
    final user = auth.currentUser!;
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(profile);
      final data = snapshot.data() ?? <String, dynamic>{};
      var name =
          data['displayName'] as String? ??
          data['name'] as String? ??
          user.displayName ??
          user.email?.split('@').first ??
          'Roommate';
      name = name.trim();
      if (name.isEmpty) name = 'Roommate';
      if (name.length > 50) name = name.substring(0, 50);
      final fields = <String, dynamic>{
        'uid': uid,
        'email': user.email ?? '',
        'displayName': name,
        if (data['createdAt'] == null)
          'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (snapshot.exists) {
        tx.update(profile, fields);
      } else {
        tx.set(profile, fields);
      }
    });
    await migrateLegacyMembership();
  }

  Future<void> migrateLegacyMembership() async {
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(profile);
      final data = snapshot.data();
      final id = data?['householdId'] as String?;
      if (id == null || data?['legacyMembershipMigrated'] == true) return;
      final house = db.collection('households').doc(id);
      final home = await tx.get(house);
      final mine = profile.collection('memberships').doc(id);
      final membership = await tx.get(mine);
      if (!home.exists) {
        throw StateError(
          'Your previous home could not be found. Retry or contact support.',
        );
      }
      final members = List<String>.from(home.data()!['memberIds'] as List);
      if (members.contains(uid) && !membership.exists) {
        final record = {
          'uid': uid,
          'groupId': id,
          'displayName': data?['displayName'] ?? data?['name'] ?? 'Roommate',
          'joinedAt': FieldValue.serverTimestamp(),
          'inviteCode': home.data()!['inviteCode'],
        };
        tx.set(mine, record);
        tx.set(house.collection('members').doc(uid), record);
      }
      // Atomic marker prevents an intentional later leave being undone on next launch.
      tx.update(profile, {
        'legacyMembershipMigrated': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateProfile(String name) => profile.update({
    'displayName': name.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<String> createHousehold(String title, String currency) async {
    final house = db.collection('households').doc();
    final code = newInviteCode();
    final person = PersonalProfile.fromMap((await profile.get()).data()!);
    final record = {
      'uid': uid,
      'groupId': house.id,
      'displayName': person.displayName,
      'joinedAt': FieldValue.serverTimestamp(),
      'inviteCode': code,
    };
    final batch = db.batch();
    batch.set(house, {
      'title': title.trim(),
      'maxMembers': 2,
      'memberIds': [uid],
      'memberNames': {uid: person.displayName},
      'currency': currency,
      'inviteCode': code,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(db.collection('invites').doc(code), {
      'householdId': house.id,
      'ownerId': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(profile.collection('memberships').doc(house.id), record);
    batch.set(house.collection('members').doc(uid), record);
    await batch.commit();
    return house.id;
  }

  Future<String> joinHousehold(String code) async {
    final normalized = code.trim().toLowerCase();
    return db.runTransaction((tx) async {
      final invitation = await tx.get(db.collection('invites').doc(normalized));
      if (!invitation.exists) {
        throw StateError(
          'Invitation not found. Check the code with your roommate.',
        );
      }
      final id = invitation.data()!['householdId'] as String;
      final mine = profile.collection('memberships').doc(id);
      final existing = await tx.get(mine);
      final person = await tx.get(profile);
      if (existing.exists) return id;
      final name = person.data()!['displayName'] as String;
      // Do not read the private household before membership: capacity is enforced atomically by rules.
      final house = db.collection('households').doc(id);
      final record = {
        'uid': uid,
        'groupId': id,
        'displayName': name,
        'joinedAt': FieldValue.serverTimestamp(),
        'inviteCode': normalized,
      };
      tx.update(house, {
        'memberIds': FieldValue.arrayUnion([uid]),
        'memberNames.$uid': name,
      });
      tx.set(mine, record);
      tx.set(house.collection('members').doc(uid), record);
      return id;
    });
  }

  Future<void> leaveGroup(String id) async {
    final house = db.collection('households').doc(id);
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(house);
      final data = snapshot.data()!;
      tx.update(house, {
        'memberIds': FieldValue.arrayRemove([uid]),
        if (!data.containsKey('legacyMemberIds'))
          'legacyMemberIds': data['memberIds'],
      });
      tx.delete(profile.collection('memberships').doc(id));
      tx.delete(house.collection('members').doc(uid));
    });
  }

  String newExpenseId(String household) => db
      .collection('households')
      .doc(household)
      .collection('expenses')
      .doc()
      .id;
  Future<void> saveExpense({
    required Household household,
    required String id,
    required String merchant,
    required String payer,
    required DateTime date,
    required List<ExpenseItem> items,
    required int total,
  }) async {
    await _persistExpense(
      household: household,
      id: id,
      merchant: merchant,
      payer: payer,
      date: date,
      items: items,
      total: total,
    );
  }

  Future<void> savePlannedExpense({
    required Household household,
    required String id,
    required String merchant,
    required String payer,
    required DateTime date,
    required List<ExpenseItem> items,
    required int total,
    bool personal = false,
    String category = 'uncategorized',
    bool refund = false,
    Map<String, int>? splitCents,
    String? recurringId,
  }) async {
    if (personal && payer != uid) {
      throw ArgumentError('Personal expenses use your account as payer');
    }
    if (!expenseCategories.contains(category)) {
      throw ArgumentError('Unknown category');
    }
    if (splitCents != null) {
      fixedSplit(total, splitCents);
      if (splitCents.keys.any((uid) => !household.members.contains(uid))) {
        throw ArgumentError('Invalid split members');
      }
    }
    await _persistExpense(
      household: household,
      id: id,
      merchant: merchant,
      payer: payer,
      date: date,
      items: items,
      total: total,
      personal: personal,
      metadata: {
        'scope': personal ? 'personal' : 'shared',
        'category': category,
        'kind': refund ? 'refund' : 'expense',
        if (!personal && splitCents != null) 'splitCents': splitCents,
        if (personal) 'groupId': household.id,
        if (recurringId != null) ...{
          'recurringId': recurringId,
          'recurringMonth': monthKey(date),
        },
      },
    );
  }

  Future<void> _persistExpense({
    required Household household,
    required String id,
    required String merchant,
    required String payer,
    required DateTime date,
    required List<ExpenseItem> items,
    required int total,
    bool personal = false,
    Map<String, Object> metadata = const {},
  }) async {
    final expense = personal
        ? profile.collection('personalExpenses').doc(id)
        : db
              .collection('households')
              .doc(household.id)
              .collection('expenses')
              .doc(id);
    await db.runTransaction((batch) async {
      final existing = await batch.get(expense);
      if (existing.exists) {
        final data = existing.data()!;
        final sameDate = (data['date'] as Timestamp).toDate().toUtc();
        var matches =
            data['createdBy'] == uid &&
            data['merchant'] == merchant &&
            data['payer'] == payer &&
            data['total'] == total &&
            sameDate == DateTime.utc(date.year, date.month, date.day) &&
            data['itemCount'] == items.length &&
            metadata.entries
                .where((e) => e.key != 'category')
                .every(
                  (e) => e.value is Map
                      ? mapEquals(data[e.key] as Map?, e.value as Map)
                      : data[e.key] == e.value,
                );
        for (var index = 0; index < items.length && matches; index++) {
          final saved = await batch.get(
            expense.collection('items').doc('$index'),
          );
          matches =
              saved.data()?['name'] == items[index].name &&
              saved.data()?['amount'] == items[index].amount &&
              (!enableItemIntelligence ||
                  (saved.data()?['quantityMilli'] ==
                          items[index].quantityMilli &&
                      saved.data()?['unit'] ==
                          (items[index].quantityMilli == null
                              ? null
                              : items[index].unit ?? 'each')));
        }
        if (!matches) {
          throw StateError(
            'This expense ID already contains different saved details. Reopen it from history before making corrections.',
          );
        }
        return; // Lost acknowledgement / retry: the identical expense is already saved.
      }
      batch.set(expense, {
        ...metadata,
        'merchant': merchant,
        'payer': payer,
        'date': Timestamp.fromDate(
          DateTime.utc(date.year, date.month, date.day),
        ),
        'month': monthKey(date),
        'itemCount': items.length,
        if (!personal && household.members.length >= 2)
          'splitBetween': household.members,
        'total': total,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      for (var index = 0; index < items.length; index++) {
        batch.set(expense.collection('items').doc('$index'), {
          ...items[index].toMap(includeQuantity: enableItemIntelligence),
          'index': index,
        });
      }
    });
    if (enableItemIntelligence && !personal) {
      await ItemsRepository(db, uid, household.id).indexExpense(id);
    }
  }
}

class PersonalProfile {
  const PersonalProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.createdAt,
    this.updatedAt,
  });
  factory PersonalProfile.fromMap(Map<String, dynamic> data) => PersonalProfile(
    uid: data['uid'] as String,
    email: data['email'] as String,
    displayName: data['displayName'] as String,
    createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
  );
  final String uid, email, displayName;
  final DateTime? createdAt, updatedAt;
}
