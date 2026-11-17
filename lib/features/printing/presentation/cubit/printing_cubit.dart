import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/entities/printer_profile.dart';
import '../../domain/receipt_data.dart';
import '../../domain/repositories/printing_repository.dart';

class PrintingState {
  const PrintingState({
    this.status = AppStatus.initial,
    this.profiles = const <PrinterProfile>[],
    this.selected,
    this.draft,
    this.preview,
    this.rendering = false,
    this.busy = false,
    this.failure,
  });

  final AppStatus status;
  final List<PrinterProfile> profiles;

  /// The profile whose settings are on screen.
  final PrinterProfile? selected;

  /// The unsaved version of it. The preview follows this, not the saved one,
  /// so a shopkeeper can see the effect of a footer change before committing
  /// to it.
  final PrinterProfile? draft;

  final Uint8List? preview;
  final bool rendering;
  final bool busy;
  final Failure? failure;

  bool get isDirty => draft != null && selected != null && !_same(draft!, selected!);

  static bool _same(PrinterProfile a, PrinterProfile b) =>
      a.name == b.name &&
      a.driver == b.driver &&
      a.paper == b.paper &&
      a.address == b.address &&
      a.copies == b.copies &&
      a.headerText == b.headerText &&
      a.footerText == b.footerText &&
      a.showLogo == b.showLogo &&
      a.showBarcode == b.showBarcode &&
      a.showTaxLines == b.showTaxLines &&
      a.openDrawer == b.openDrawer &&
      a.autoPrint == b.autoPrint &&
      a.fontScaleBp == b.fontScaleBp &&
      a.isDefault == b.isDefault &&
      a.isActive == b.isActive;

  PrintingState copyWith({
    AppStatus? status,
    List<PrinterProfile>? profiles,
    PrinterProfile? selected,
    PrinterProfile? draft,
    Uint8List? preview,
    bool? rendering,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      PrintingState(
        status: status ?? this.status,
        profiles: profiles ?? this.profiles,
        selected: selected ?? this.selected,
        draft: draft ?? this.draft,
        preview: preview ?? this.preview,
        rendering: rendering ?? this.rendering,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// The printer screen.
///
/// Its one idea: **what you see is what comes out**. Every change to the
/// profile re-renders the same PDF the printer would be handed, from the same
/// sample receipt, so nothing about the layout is a surprise at the counter.
class PrintingCubit extends Cubit<PrintingState> {
  PrintingCubit(this._repository) : super(const PrintingState());

  final PrintingRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading));

    final Result<List<PrinterProfile>> result = await _repository.profiles();
    if (isClosed) return;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(status: AppStatus.failure, failure: failure));
      return;
    }

    final List<PrinterProfile> profiles = result.valueOrNull ?? const <PrinterProfile>[];
    final PrinterProfile? first = profiles.isEmpty ? null : profiles.first;

    emit(PrintingState(
      status: AppStatus.ready,
      profiles: profiles,
      selected: first,
      draft: first,
    ));
    if (first != null) await refreshPreview();
  }

  void select(PrinterProfile profile) {
    emit(state.copyWith(selected: profile, draft: profile, clearFailure: true));
    refreshPreview();
  }

  void startNew() {
    final PrinterProfile blank = PrinterProfile.blank();
    emit(PrintingState(
      status: AppStatus.ready,
      profiles: state.profiles,
      selected: blank,
      draft: blank,
    ));
    refreshPreview();
  }

  /// Edits the unsaved copy and re-renders. The preview is deliberately not
  /// debounced on the toggles — they are single taps — but text fields call
  /// this on every keystroke, so the render is guarded by [state.rendering].
  void edit(PrinterProfile draft) {
    emit(state.copyWith(draft: draft));
    refreshPreview();
  }

  Future<void> refreshPreview() async {
    final PrinterProfile? draft = state.draft;
    if (draft == null || state.rendering) return;

    emit(state.copyWith(rendering: true));
    final Result<Uint8List> result = await _repository.testPage(draft);
    if (isClosed) return;

    emit(state.copyWith(
      rendering: false,
      preview: result.valueOrNull,
      failure: result.failureOrNull,
    ));
  }

  Future<bool> save() async {
    final PrinterProfile? draft = state.draft;
    if (draft == null) return false;

    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<int> result = await _repository.saveProfile(draft);
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return false;
    }

    await load();
    return true;
  }

  Future<bool> delete(int id) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<dynamic> result = await _repository.deleteProfile(id);
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return false;
    }
    await load();
    return true;
  }

  /// Sends the sample page to the real printer — the only way to be sure.
  Future<bool> testPrint() async {
    final Uint8List? bytes = state.preview;
    if (bytes == null) return false;

    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<dynamic> result =
        await _repository.present(bytes, name: state.draft?.name ?? 'test');
    if (isClosed) return false;

    emit(state.copyWith(busy: false, failure: result.failureOrNull));
    return result.succeeded;
  }

  /// Opens the drawer, printing nothing.
  ///
  /// Kept separate from [testPrint] because it is the one printer function a
  /// cashier uses during a shift rather than while setting the shop up.
  Future<bool> openDrawer() async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<dynamic> result =
        await _repository.openDrawer(profile: state.draft);
    if (isClosed) return false;

    emit(state.copyWith(busy: false, failure: result.failureOrNull));
    return result.succeeded;
  }

  /// Renders a real invoice into the preview, so a shopkeeper can check a
  /// layout against a receipt they recognise.
  Future<void> previewInvoice(int invoiceId) async {
    emit(state.copyWith(rendering: true, clearFailure: true));

    final Result<ReceiptData> data = await _repository.saleReceipt(invoiceId);
    final Failure? failure = data.failureOrNull;
    if (failure != null) {
      if (!isClosed) {
        emit(state.copyWith(rendering: false, failure: failure));
      }
      return;
    }

    final Result<Uint8List> bytes = await _repository.render(
      data.valueOrNull!,
      profile: state.draft,
    );
    if (isClosed) return;

    emit(state.copyWith(
      rendering: false,
      preview: bytes.valueOrNull,
      failure: bytes.failureOrNull,
    ));
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}
