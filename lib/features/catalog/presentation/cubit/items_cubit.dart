import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/entities/catalog_entities.dart';
import '../../domain/repositories/catalog_repository.dart';
import 'items_state.dart';

/// The items screen.
///
/// Searching is debounced here rather than in the widget: a barcode scanner
/// "types" thirteen characters in about eighty milliseconds, and a query per
/// keystroke is thirteen queries for one scan.
class ItemsCubit extends Cubit<ItemsState> {
  ItemsCubit(this._repository) : super(const ItemsState());

  final CatalogRepository _repository;
  Timer? _debounce;

  /// Guards against an old search overwriting a newer one when the two return
  /// out of order — which happens the moment a shop has ten thousand items.
  int _searchToken = 0;

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }

  Future<void> load() async {
    emit(state.copyWith(status: AppStatus.loading));

    final Result<List<Category>> categories = await _repository.categories();
    final Result<List<UnitDef>> units = await _repository.units();
    final Result<List<Item>> items = await _search();

    final Failure? failure = firstFailure(<Result<Object?>>[
      categories,
      units,
      items,
    ]);
    if (failure != null) {
      emit(state.copyWith(status: AppStatus.failure, failure: failure));
      return;
    }

    emit(state.copyWith(
      status: AppStatus.ready,
      categories: categories.valueOrNull,
      units: units.valueOrNull,
      items: items.valueOrNull,
      clearFailure: true,
    ));
  }

  void search(String query) {
    emit(state.copyWith(query: query));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _refreshItems);
  }

  void filterByCategory(int? categoryId) {
    emit(categoryId == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(categoryId: categoryId));
    _refreshItems();
  }

  void filterByStock(StockFilter filter) {
    emit(state.copyWith(filter: filter));
    _refreshItems();
  }

  Future<Result<List<Item>>> _search() => _repository.searchItems(
        text: state.query,
        categoryId: state.categoryId,
        filter: state.filter,
        // A search string is a reason to look inside the groups: someone typing
        // "red" means the red shirt, not the shirt.
        includeVariants: state.query.trim().isNotEmpty,
      );

  Future<void> _refreshItems() async {
    final int token = ++_searchToken;
    final Result<List<Item>> items = await _search();
    if (isClosed || token != _searchToken) return;

    final Failure? failure = items.failureOrNull;
    emit(failure != null
        ? state.copyWith(failure: failure)
        : state.copyWith(
            status: AppStatus.ready,
            items: items.valueOrNull,
            clearFailure: true,
          ));
  }

  // ------------------------------------------------------------- reading --

  /// A one-off lookup that does **not** touch the screen's state — used by the
  /// pickers inside the editor, which need their own results without throwing
  /// away the list the user is standing on.
  Future<List<Item>> lookup(String text, {Set<ItemKind>? kinds}) async {
    final Result<List<Item>> result = await _repository.searchItems(
      text: text,
      kinds: kinds,
      includeVariants: true,
      limit: 40,
    );
    return result.valueOr(const <Item>[]);
  }

  /// Everything the editor needs for one item, or an empty draft for a new one.
  Future<ItemDraft?> loadDraft(int? id) async {
    final Result<ItemDraft> result = await _repository.loadDraft(id);
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      if (!isClosed) emit(state.copyWith(failure: failure));
      return null;
    }
    return result.valueOrNull;
  }

  // ------------------------------------------------------------- writing --

  /// Returns the item's id — the caller needs it to write an opening stock
  /// figure straight afterwards — or null when the save was refused.
  Future<int?> saveItem(ItemSaveRequest request) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<int> result = await _repository.saveItem(request);
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return null;
    }
    await _refreshItems();
    if (!isClosed) emit(state.copyWith(busy: false));
    return result.valueOrNull;
  }

  Future<bool> removeItem(int id) => _write(() => _repository.removeItem(id));

  /// The list's hide/show switch. The row is swapped in place so the table does
  /// not flash a loading state, and rolls back if the write is refused.
  Future<bool> toggleActive(Item item) async {
    final List<Item> optimistic = state.items
        .map((Item e) =>
            e.id == item.id ? e.copyWith(isActive: !e.isActive) : e)
        .toList(growable: false);
    emit(state.copyWith(items: optimistic));

    final Result<Unit> result =
        await _repository.setItemActive(item.id, !item.isActive);
    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(failure: failure));
      await _refreshItems();
      return false;
    }
    // The list is filtered by active state, so the row may now belong
    // somewhere else entirely.
    await _refreshItems();
    return true;
  }

  Future<bool> adjustStock({
    required int itemId,
    required Qty counted,
    int? userId,
    String? note,
    bool isOpening = false,
  }) =>
      _write(() => _repository.adjustStock(
            itemId: itemId,
            counted: counted,
            userId: userId,
            note: note,
            isOpening: isOpening,
          ));

  /// Returns how many variants were created, or null when it failed.
  Future<int?> generateVariants(int groupItemId) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<int> result = await _repository.generateVariants(groupItemId);
    if (isClosed) return null;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return null;
    }
    await _refreshItems();
    emit(state.copyWith(busy: false));
    return result.valueOrNull;
  }

  /// The price and cost trail for one item, fetched when the tab is opened
  /// rather than with the rest of the draft: most edits never look at it.
  Future<ItemHistory> history(int itemId) async {
    final Result<ItemHistory> result = await _repository.history(itemId);
    return result.valueOr(const ItemHistory());
  }

  Future<bool> saveCategory(CategorySaveRequest request) =>
      _write(() => _repository.saveCategory(request), reloadAll: true);

  Future<bool> removeCategory(int id) =>
      _write(() => _repository.removeCategory(id), reloadAll: true);

  Future<bool> saveUnit(UnitSaveRequest request) =>
      _write(() => _repository.saveUnit(request), reloadAll: true);

  Future<bool> removeUnit(int id) =>
      _write(() => _repository.removeUnit(id), reloadAll: true);

  void clearFailure() => emit(state.copyWith(clearFailure: true));

  /* ── Plumbing ───────────────────────────────────────────────────────────── */

  Future<bool> _write<T>(
    Future<Result<T>> Function() action, {
    bool reloadAll = false,
  }) async {
    emit(state.copyWith(busy: true, clearFailure: true));
    final Result<T> result = await action();
    if (isClosed) return false;

    final Failure? failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, failure: failure));
      return false;
    }

    if (reloadAll) {
      final Result<List<Category>> categories = await _repository.categories();
      final Result<List<UnitDef>> units = await _repository.units();
      if (isClosed) return true;
      emit(state.copyWith(
        categories: categories.valueOrNull,
        units: units.valueOrNull,
      ));
    }
    await _refreshItems();
    if (!isClosed) emit(state.copyWith(busy: false));
    return true;
  }
}
