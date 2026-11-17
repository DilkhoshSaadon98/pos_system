import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../utils/audit.dart';
import '../utils/time.dart';

//? The result of a backup attempt, whether it copied the database or not.
class BackupOutcome {
  const BackupOutcome({
    required this.ranAt,
    this.path,
    this.pruned = 0,
    this.skippedReason,
    this.error,
  });

  final String ranAt;
  final String? path;

  //? How many old copies were deleted to stay within the limit.
  final int pruned;

  final String? skippedReason;

  final String? error;

  bool get didCopy => path != null;
}

class BackupScheduler {
  BackupScheduler(this._database, {required this.copy});

  final AppDatabase _database;

//? The function that actually copies the database to a backup file.
  final Future<String> Function(String directory) copy;

  Timer? _timer;
  bool _running = false;
  BackupOutcome? _last;

  BackupOutcome? get last => _last;

  bool get enabled => _database.settingBool('backup_auto');

  String get folder => _database.settingString('backup_folder');

  int get everyHours {
    final int h = _database.settingInt('backup_every_hours', 24);
    return h < 1 ? 1 : h;
  }

  int get keep {
    final int k = _database.settingInt('backup_keep', 14);
    return k < 1 ? 1 : k;
  }


  void start() {
    stop();
    if (!enabled) return;
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => runIfDue());
    unawaited(runIfDue());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  //? 
  Future<BackupOutcome> runIfDue({bool force = false}) async {
    if (_running) {
      return _remember(BackupOutcome(
        ranAt: Time.stamp(),
        skippedReason: 'already running',
      ));
    }
    if (!force) {
      if (!enabled) {
        return _remember(
            BackupOutcome(ranAt: Time.stamp(), skippedReason: 'switched off'));
      }
      if (!_isDue()) {
        return _remember(
            BackupOutcome(ranAt: Time.stamp(), skippedReason: 'not due yet'));
      }
    }

    _running = true;
    try {
      final String target = folder.isEmpty ? '' : folder;
      final String path = await copy(target);
      final int pruned = await _prune(File(path).parent);

      await _database.setSetting('backup_last_at', Time.stamp());
      await Audit.write(
        _database.db,
        action: Audit.backup,
        entity: 'database',
        detail: '${p.basename(path)}'
            '${pruned > 0 ? ' · $pruned old copies removed' : ''}',
      );

      return _remember(BackupOutcome(
        ranAt: Time.stamp(),
        path: path,
        pruned: pruned,
      ));
    } catch (error) {
      return _remember(BackupOutcome(
        ranAt: Time.stamp(),
        error: '$error',
      ));
    } finally {
      _running = false;
    }
  }

  bool _isDue() {
    final String lastAt = _database.settingString('backup_last_at');
    if (lastAt.isEmpty) return true;
    final DateTime? last = DateTime.tryParse(lastAt);
    if (last == null) return true;
    return DateTime.now().difference(last).inMinutes >= everyHours * 60;
  }


  Future<int> _prune(Directory dir) async {
    if (!dir.existsSync()) return 0;

    final List<File> copies = dir
        .listSync()
        .whereType<File>()
        .where((File f) =>
            p.basename(f.path).startsWith('cashier-backup-') &&
            p.extension(f.path) == '.db')
        .toList();
    if (copies.length <= keep) return 0;

    copies.sort((File a, File b) =>
        a.statSync().modified.compareTo(b.statSync().modified));

    int removed = 0;
    for (final File f in copies.take(copies.length - keep)) {
      try {
        f.deleteSync();
        removed++;
      } catch (_) {
      }
    }
    return removed;
  }

  BackupOutcome _remember(BackupOutcome outcome) {
    if (outcome.didCopy || outcome.error != null) _last = outcome;
    return outcome;
  }
}
