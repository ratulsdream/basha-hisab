import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'domain.dart';

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
        'This action is not allowed. The household may already have two members. Check the invitation and deployed Firestore rules.',
      'too-many-requests' => 'Too many attempts. Please wait and try again.',
      'failed-precondition' =>
        'Firebase is not ready. Check that Firestore is enabled and its rules are deployed.',
      _ => 'Could not complete the request (${error.code}). Please try again.',
    };
  }
  if (error is StateError) return error.message;
  return 'Something went wrong. Please try again.';
}

class Household {
  Household(this.id, Map<String, dynamic> data)
    : members = List<String>.from(data['memberIds'] as List),
      names = Map<String, String>.from(data['memberNames'] as Map),
      currency = data['currency'] as String,
      inviteCode = data['inviteCode'] as String;
  final String id;
  final List<String> members;
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
      itemCount = data['itemCount'] as int;
  final String id, merchant, payer, creator;
  final DateTime date;
  final int total;
  final int itemCount;
}

class HouseholdRepository {
  HouseholdRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : db = firestore ?? FirebaseFirestore.instance,
      auth = auth ?? FirebaseAuth.instance;
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

  Future<void> createHousehold(String name, String currency) async {
    final house = db.collection('households').doc();
    final code = newInviteCode();
    final invite = db.collection('invites').doc(code);
    // Transaction prevents a double tap / concurrent device creating two households.
    await db.runTransaction((transaction) async {
      final existing = await transaction.get(profile);
      if (existing.exists) {
        throw StateError('You already belong to a household. Refresh the app.');
      }
      transaction.set(house, {
        'memberIds': [uid],
        'memberNames': {uid: name},
        'currency': currency,
        'inviteCode': code,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(invite, {
        'householdId': house.id,
        'ownerId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(profile, {
        'householdId': house.id,
        'name': name,
        'inviteCode': code,
      });
    });
  }

  Future<void> joinHousehold(String name, String code) async {
    await db.runTransaction((transaction) async {
      final existing = await transaction.get(profile);
      if (existing.exists) {
        throw StateError('You already belong to a household. Refresh the app.');
      }
      final inviteRef = db.collection('invites').doc(code.trim().toLowerCase());
      final invite = await transaction.get(inviteRef);
      if (!invite.exists) {
        throw StateError(
          'Invitation not found. Ask your roommate to copy their invitation code again.',
        );
      }
      final householdId = invite.data()!['householdId'] as String;
      // Rules atomically enforce capacity and require the actual invitation code.
      // Transactions publish local state only after the server accepts membership.
      transaction.update(db.collection('households').doc(householdId), {
        'memberIds': FieldValue.arrayUnion([uid]),
        'memberNames.$uid': name,
      });
      transaction.set(profile, {
        'householdId': householdId,
        'name': name,
        'inviteCode': code.trim().toLowerCase(),
      });
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
    final expense = db
        .collection('households')
        .doc(household.id)
        .collection('expenses')
        .doc(id);
    final batch = db.batch();
    batch.set(expense, {
      'merchant': merchant,
      'payer': payer,
      'date': Timestamp.fromDate(DateTime.utc(date.year, date.month, date.day)),
      'month': monthKey(date),
      'itemCount': items.length,
      'total': total,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    for (var index = 0; index < items.length; index++) {
      batch.set(expense.collection('items').doc('$index'), {
        ...items[index].toMap(),
        'index': index,
      });
    }
    await batch.commit();
  }
}
