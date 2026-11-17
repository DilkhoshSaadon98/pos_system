import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/test_catalogue.dart';
import '../../../../core/database/legacy_import.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/state/app_status.dart';
import '../../settings_injection.dart';

class SettingsState {
  const SettingsState({
    this.status = AppStatus.initial,
    this.values = const <String, String>{},
    this.dirty = const <String, String>{},
    this.databasePath = '',
    this.databaseBytes = 0,
    this.busy = false,
    this.failure,
    this.lastBackupPath,
    this.lastImport,
    this.lastTest,
  });

  final AppStatus status;

  /// What is saved.
  final Map<String, String> values;

  /// What has been changed but not saved yet. Keeping the two apart is what
  /// lets the screen show a Save button that means something.
  final Map<String, String> dirty;

  final String databasePath;
  final int databaseBytes;
  final bool busy;
  final Failure? failure;
  final String? lastBackupPath;
  final LegacyImportReport? lastImport;
  final TestCatalogueReport? lastTest;

  bool get hasChanges => dirty.isNotEmpty;

  String read(String key, [String fallback = '']) {
    final String? value = dirty[key] ?? values[key];
    return (value == null || value.isEmpty) ? fallback : value;
  }

  int readInt(String key, [int fallback = 0]) =>
      int.tryParse(read(key)) ?? fallback;

  bool readBool(String key, [bool fallback = false]) {
    final String v = read(key);
    if (v.isEmpty) return fallback;
    return v == '1' || v.toLowerCase() == 'true';
  }

  SettingsState copyWith({
    AppStatus? status,
    Map<String, String>? values,
    Map<String, String>? dirty,
    String? databasePath,
    int? databaseBytes,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
    String? lastBackupPath,
    LegacyImportReport? lastImport,
    TestCatalogueReport? lastTest,
  }) =>
      SettingsState(
        status: status ?? this.status,
        values: values ?? this.values,
        dirty: dirty ?? this.dirty,
        databasePath: databasePath ?? this.databasePath,
        databaseBytes: databaseBytes ?? this.databaseBytes,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
        lastBackupPath: lastBackupPath ?? this.lastBackupPath,
        lastImport: lastImport ?? this.lastImport,
        lastTest: lastTest ?? this.lastTest,
      );
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._repository) : super(const SettingsState());

  final SettingsRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading));

    final Result<String> path = await _repository.databasePath();
    final Result<int> bytes = await _repository.databaseBytes();
    if (isClosed) return;

    emit(SettingsState(
      status: AppStatus.ready,
      values: _repository.all(),
      databasePath: path.valueOr(''),
      databaseBytes: bytes.valueOr(0),
    ));
  }

  void set(String key, String value) => emit(state.copyWith(
        dirty: <String, String>{...state.dirty, key: value},
      ));

  void setBool(String key, bool value) => set(key, value ? '1' : '0');

  void discard() => emit(state.copyWith(dirty: const <String, String>{}));

  Future<bool> save() async {
    if (!state.hasChanges) return true;

    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<dynamic> result = await _repository.save(state.dirty);
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return false;
    }

    emit(state.copyWith(
      busy: false,
      values: _repository.all(),
      dirty: const <String, String>{},
    ));
    return true;
  }

  Future<String?> backup({String? directory}) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<String> result = await _repository.backup(directory: directory);
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    emit(state.copyWith(
      busy: false,
      failure: failure,
      lastBackupPath: result.valueOrNull,
    ));
    return result.valueOrNull;
  }

  /// Returns true when the file has been swapped. The app must be restarted
  /// afterwards — the connection to the old file is gone and every repository
  /// is holding a handle to it.
  Future<bool> restore(String path) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<dynamic> result = await _repository.restore(path);
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    emit(state.copyWith(busy: false, failure: failure));
    return failure == null;
  }

  Future<LegacyImportReport?> importLegacy(String path, {int? userId}) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<LegacyImportReport> result =
        await _repository.importLegacy(path, userId: userId);
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    emit(state.copyWith(
      busy: false,
      failure: failure,
      values: _repository.all(),
      lastImport: result.valueOrNull,
    ));
    return result.valueOrNull;
  }

  int get imageBytes => _repository.imageBytes;

  Future<int?> cleanUpImages() async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<int> result = await _repository.cleanUpImages();
    if (isClosed) return null;
    emit(state.copyWith(busy: false, failure: result.failureOrNull));
    return result.valueOrNull;
  }

  bool get testDataLoaded => _repository.testDataLoaded;

  /// Fills the shop with a supermarket catalogue for testing.
  Future<TestCatalogueReport?> loadTestData({int? userId}) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<TestCatalogueReport> result =
        await _repository.seedTestCatalogue(userId: userId);
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    emit(state.copyWith(
      busy: false,
      failure: failure,
      values: _repository.all(),
      lastTest: result.valueOrNull,
    ));
    return result.valueOrNull;
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}
