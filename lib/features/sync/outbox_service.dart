import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show listEquals;
import '../../data.dart';
import '../../domain.dart';
import '../items/items_repository.dart';
import '../planning/planning_repository.dart';
import 'outbox_store.dart';

class DraftNeedsReview implements Exception {
  const DraftNeedsReview(this.message);
  final String message;
}

class OutboxService {
  OutboxService(this.store, HouseholdRepository source, {this.sender})
    : repository = HouseholdRepository(
        firestore: source.db,
        auth: source.auth,
        enableItemIntelligence: source.enableItemIntelligence,
        boundUid: store.uid,
      );
  final OutboxStore store;
  final HouseholdRepository repository;
  final Future<void> Function(QueuedExpense)? sender;
  static final _running = <String, Future<void>>{};
  Future<void> drain() {
    if (repository.auth.currentUser?.uid != store.uid) return Future.value();
    return _running.putIfAbsent(
      store.uid,
      () => _drain().whenComplete(() {
        _running.remove(store.uid);
      }),
    );
  }

  Future<void> _drain() async {
    for (final draft in await store.read()) {
      if (draft.state == 'attention' ||
          repository.auth.currentUser?.uid != store.uid) {
        continue;
      }
      await store.mark(
        draft.id,
        'syncing',
        'Waiting for server acceptance',
        attempted: true,
      );
      try {
        await (sender?.call(draft) ?? _send(draft));
        await store.remove(draft.id);
      } on DraftNeedsReview catch (e) {
        await store.mark(draft.id, 'attention', e.message);
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          await store.mark(
            draft.id,
            'attention',
            'Access changed or rules reject this draft. Keep it and verify history before creating another expense.',
          );
        } else {
          await store.mark(
            draft.id,
            'pending',
            'Connection interrupted. Still saved on this phone; server acceptance is not confirmed.',
          );
          break;
        }
      } catch (e) {
        await store.mark(
          draft.id,
          'attention',
          'This draft needs review. Its extracted data remains saved on this phone.',
        );
      }
    }
  }

  Future<void> _send(QueuedExpense draft) async {
    final p = draft.payload;
    final homeSnapshot = await repository.db
        .collection('households')
        .doc(draft.group)
        .get(const GetOptions(source: Source.server));
    if (!homeSnapshot.exists) {
      throw const DraftNeedsReview(
        'The original group is unavailable. Do not move this draft into another group without reviewing history.',
      );
    }
    final home = Household(homeSnapshot.id, homeSnapshot.data()!);
    final prior = List<String>.from(p['members'] as List)..sort(),
        current = [...home.members]..sort();
    if (!listEquals(prior, current) ||
        !current.contains(store.uid) ||
        !current.contains(p['payer'])) {
      throw const DraftNeedsReview(
        'Group members changed. Review this draft and the existing history before retrying.',
      );
    }
    final personal = p['personal'] == true;
    final reference = personal
        ? repository.profile.collection('personalExpenses').doc(draft.id)
        : repository.db
              .collection('households')
              .doc(draft.group)
              .collection('expenses')
              .doc(draft.id);
    final existing = await reference.get(
      const GetOptions(source: Source.server),
    );
    final signature = p['signature'] as String?;
    if (!existing.exists &&
        signature != null &&
        p['duplicateOverride'] != true) {
      final matches = personal
          ? await PlanningRepository(
              repository.db,
              store.uid,
              draft.group,
            ).personalDuplicates(
              signature,
              p['imageHash'] as String?,
              serverOnly: true,
            )
          : await ItemsRepository(
              repository.db,
              store.uid,
              draft.group,
            ).duplicates(
              signature,
              p['imageHash'] as String?,
              serverOnly: true,
            );
      if (matches.any((m) => m.expenseId != draft.id)) {
        throw const DraftNeedsReview(
          'Possible duplicate: review history, then explicitly approve a separate purchase.',
        );
      }
    }
    await repository.savePlannedExpense(
      household: home,
      id: draft.id,
      merchant: p['merchant'] as String,
      payer: p['payer'] as String,
      date: DateTime.parse(p['date'] as String),
      items: (p['items'] as List).map((row) {
        final d = Map<String, dynamic>.from(row as Map);
        return ExpenseItem(
          d['name'] as String,
          d['amount'] as int,
          quantityMilli: d['quantityMilli'] as int?,
          unit: d['unit'] as String?,
        );
      }).toList(),
      total: p['total'] as int,
      personal: personal,
      category: p['category'] as String,
      refund: p['refund'] == true,
      splitCents: p['splitCents'] == null
          ? null
          : Map<String, int>.from(p['splitCents'] as Map),
    );
    if (signature != null) {
      if (personal) {
        await PlanningRepository(
          repository.db,
          store.uid,
          draft.group,
        ).recordPersonalSignature(
          draft.id,
          signature,
          p['imageHash'] as String?,
        );
      } else {
        await ItemsRepository(
          repository.db,
          store.uid,
          draft.group,
        ).recordSignature(draft.id, signature, p['imageHash'] as String?);
      }
    }
  }
}

class OutboxRunner with WidgetsBindingObserver {
  OutboxRunner(this.repository);
  final HouseholdRepository repository;
  Timer? timer;
  OutboxService? service;
  bool stopped = false;
  Future<void> start() async {
    final store = await OutboxStore.open(repository.uid);
    if (stopped) return;
    service = OutboxService(store, repository);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_drain());
    timer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => unawaited(_drain()),
    );
  }

  Future<void> _drain() async {
    try {
      await service?.drain();
    } catch (_) {
      /* Drafts are durable; a later foreground retry will re-open them. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_drain());
  }

  void stop() {
    stopped = true;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
