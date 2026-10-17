import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class QueuedExpense {
  QueuedExpense(
    this.payload, {
    this.state = 'pending',
    this.reason = '',
    this.attempts = 0,
    DateTime? queuedAt,
  }) : queuedAt = queuedAt ?? DateTime.now().toUtc();
  final Map<String, dynamic> payload;
  final String state, reason;
  final int attempts;
  final DateTime queuedAt;
  String get id => payload['id'] as String;
  String get owner => payload['owner'] as String;
  String get group => payload['groupId'] as String;
  String get fingerprint {
    final financial = Map<String, dynamic>.of(payload)
      ..remove('duplicateOverride');
    return sha256.convert(utf8.encode(jsonEncode(financial))).toString();
  }

  factory QueuedExpense.fromRow(Map<String, Object?> row) {
    final p = Map<String, dynamic>.from(
      jsonDecode(row['payload'] as String) as Map,
    );
    if (p['owner'] != row['owner'] || p['id'] != row['id']) {
      throw StateError('A saved draft needs recovery. Do not clear app data.');
    }
    final expense = QueuedExpense(
      p,
      state: row['state'] as String,
      reason: row['reason'] as String,
      attempts: row['attempts'] as int,
      queuedAt: DateTime.parse(row['queued_at'] as String),
    );
    if (row['fingerprint'] != expense.fingerprint) {
      throw StateError(
        'A saved draft failed its integrity check. Keep app data for recovery.',
      );
    }
    return expense;
  }
}

class OutboxStore {
  OutboxStore._(this.uid, this.path, this.database, this.cacheKey);
  final String uid, path, cacheKey;
  final Database database;
  final _changes = StreamController<void>.broadcast();
  static final _opened = <String, Future<OutboxStore>>{};
  static Future<OutboxStore> open(
    String uid, {
    String? path,
    DatabaseFactory? factory,
  }) async {
    if (path == null) {
      final root = await getApplicationSupportDirectory();
      final directory = await Directory(
        '${root.path}/outbox',
      ).create(recursive: true);
      path = '${directory.path}/${sha256.convert(utf8.encode(uid))}.db';
    }
    final cacheKey = '$uid:$path';
    return _opened.putIfAbsent(cacheKey, () async {
      final db = await (factory ?? databaseFactory).openDatabase(
        path!,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) async {
            await db.rawQuery('PRAGMA journal_mode=WAL');
            await db.execute('PRAGMA synchronous=FULL');
          },
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE drafts (owner TEXT NOT NULL, id TEXT NOT NULL, group_id TEXT NOT NULL, payload TEXT NOT NULL, fingerprint TEXT NOT NULL, state TEXT NOT NULL, reason TEXT NOT NULL, attempts INTEGER NOT NULL, queued_at TEXT NOT NULL, PRIMARY KEY(owner,id))',
            );
          },
          onOpen: (db) async {
            await db.update(
              'drafts',
              {'state': 'pending'},
              where: 'owner = ? AND state = ?',
              whereArgs: [uid, 'syncing'],
            );
          },
        ),
      );
      return OutboxStore._(uid, path, db, cacheKey);
    });
  }

  Future<List<QueuedExpense>> read() async => (await database.query(
    'drafts',
    where: 'owner = ?',
    whereArgs: [uid],
    orderBy: 'queued_at ASC',
  )).map(QueuedExpense.fromRow).toList();
  Stream<List<QueuedExpense>> watch() {
    late StreamController<List<QueuedExpense>> controller;
    StreamSubscription<void>? subscription;
    controller = StreamController<List<QueuedExpense>>(
      onListen: () {
        subscription = _changes.stream.listen((_) async {
          try {
            final rows = await read();
            if (!controller.isClosed) controller.add(rows);
          } catch (e, st) {
            if (!controller.isClosed) controller.addError(e, st);
          }
        });
        read().then(
          (rows) {
            if (!controller.isClosed) controller.add(rows);
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
        );
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> enqueue(QueuedExpense expense) async {
    if (expense.owner != uid) {
      throw StateError('Cannot queue an expense for another account.');
    }
    await database.transaction((tx) async {
      final old = await tx.query(
        'drafts',
        where: 'owner = ? AND id = ?',
        whereArgs: [uid, expense.id],
      );
      if (old.isNotEmpty) {
        if (old.single['fingerprint'] != expense.fingerprint) {
          throw StateError(
            'This draft ID already has different details. Keep the original draft for review.',
          );
        }
        return;
      }
      final count =
          Sqflite.firstIntValue(
            await tx.rawQuery('SELECT COUNT(*) FROM drafts WHERE owner = ?', [
              uid,
            ]),
          ) ??
          0;
      if (count >= 500) {
        throw StateError('Sync or review saved drafts before adding more.');
      }
      await tx.insert('drafts', {
        'owner': uid,
        'id': expense.id,
        'group_id': expense.group,
        'payload': jsonEncode(expense.payload),
        'fingerprint': expense.fingerprint,
        'state': 'pending',
        'reason': '',
        'attempts': 0,
        'queued_at': expense.queuedAt.toIso8601String(),
      });
    });
    _changes.add(null);
  }

  Future<void> mark(
    String id,
    String state,
    String reason, {
    bool attempted = false,
  }) async {
    await database.transaction((tx) async {
      final rows = await tx.query(
        'drafts',
        where: 'owner = ? AND id = ?',
        whereArgs: [uid, id],
      );
      if (rows.isEmpty) return;
      await tx.update(
        'drafts',
        {
          'state': state,
          'reason': reason,
          'attempts': (rows.single['attempts'] as int) + (attempted ? 1 : 0),
        },
        where: 'owner = ? AND id = ?',
        whereArgs: [uid, id],
      );
    });
    _changes.add(null);
  }

  Future<void> approveDuplicate(String id) async {
    await database.transaction((tx) async {
      final rows = await tx.query(
        'drafts',
        where: 'owner = ? AND id = ?',
        whereArgs: [uid, id],
      );
      if (rows.isEmpty) return;
      final payload = Map<String, dynamic>.from(
        jsonDecode(rows.single['payload'] as String) as Map,
      )..['duplicateOverride'] = true;
      await tx.update(
        'drafts',
        {'payload': jsonEncode(payload), 'state': 'pending', 'reason': ''},
        where: 'owner = ? AND id = ?',
        whereArgs: [uid, id],
      );
    });
    _changes.add(null);
  }

  Future<void> remove(String id) async {
    await database.delete(
      'drafts',
      where: 'owner = ? AND id = ?',
      whereArgs: [uid, id],
    );
    _changes.add(null);
  }

  Future<void> close() async {
    _opened.remove(cacheKey);
    await database.close();
    await _changes.close();
  }
}
