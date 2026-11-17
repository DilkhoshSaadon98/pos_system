import '../../../../core/classes/enums.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../domain/entities/catalog_entities.dart';

/// Everything the items screen shows, in one immutable object.
///
/// The filters live here rather than in the widget because the same state
/// drives the table, the counters above it and the empty message underneath —
/// three things that used to disagree when each kept its own copy.
class ItemsState {
  const ItemsState({
    this.status = AppStatus.initial,
    this.items = const <Item>[],
    this.categories = const <Category>[],
    this.units = const <UnitDef>[],
    this.query = '',
    this.categoryId,
    this.filter = StockFilter.all,
    this.busy = false,
    this.failure,
  });

  final AppStatus status;
  final List<Item> items;
  final List<Category> categories;
  final List<UnitDef> units;
  final String query;
  final int? categoryId;
  final StockFilter filter;

  /// A write is in flight — the list stays on screen, the buttons go quiet.
  final bool busy;

  final Failure? failure;

  int get lowStockCount => items.where((Item i) => i.isLowStock).length;
  int get outOfStockCount => items.where((Item i) => i.isOutOfStock).length;

  Money get stockValue => Money(
        items.fold(0, (int sum, Item i) => sum + i.stockValue.minor),
      );

  String categoryName(int? id) {
    if (id == null) return '';
    for (final Category c in categories) {
      if (c.id == id) return c.name;
    }
    return '';
  }

  ItemsState copyWith({
    AppStatus? status,
    List<Item>? items,
    List<Category>? categories,
    List<UnitDef>? units,
    String? query,
    int? categoryId,
    bool clearCategory = false,
    StockFilter? filter,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      ItemsState(
        status: status ?? this.status,
        items: items ?? this.items,
        categories: categories ?? this.categories,
        units: units ?? this.units,
        query: query ?? this.query,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        filter: filter ?? this.filter,
        busy: busy ?? this.busy,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}
