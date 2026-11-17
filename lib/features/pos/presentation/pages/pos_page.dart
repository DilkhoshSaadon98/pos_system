import 'dart:async';

import 'package:cashier_system_v2/features/pos/presentation/widgets/pos_category_strip.dart';
import 'package:cashier_system_v2/features/pos/presentation/widgets/pos_mobile_cart_bar.dart';
import 'package:cashier_system_v2/features/pos/presentation/widgets/pos_search_bar_widget.dart';
import 'package:cashier_system_v2/features/pos/presentation/widgets/pos_shortcut_bar.dart';
import 'package:cashier_system_v2/features/sales/domain/entities/posted_sale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/calc/sale_calculator.dart';
import '../../../../core/classes/enums.dart';
import '../../../../core/display/customer_display.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/state/app_status.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/modals.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../catalog/domain/entities/catalog_entities.dart';
import '../../../parties/domain/entities/party.dart';
import '../cubit/pos_cubit.dart';
import '../cubit/pos_state.dart';
import '../widgets/line_edit_sheet.dart';
import '../widgets/payment_sheet.dart';
import '../widgets/pos_cart_panel.dart';
import '../widgets/pos_item_grid.dart';
import '../widgets/pos_sheets.dart';

class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  StreamSubscription<PosPrompt>? _prompts;

  @override
  void initState() {
    super.initState();
    _prompts = context.read<PosCubit>().prompts.listen(_answer);
  }

  @override
  void dispose() {
    _prompts?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _answer(PosPrompt prompt) async {
    final PosCubit cubit = context.read<PosCubit>();

    switch (prompt) {
      case VariantPrompt(
          group: final Item group,
          variants: final List<Item> list
        ):
        final Item? chosen = await showVariantPicker(
          context,
          group: group,
          variants: list,
          priceMode: cubit.state.priceMode,
        );
        if (chosen != null) await cubit.addItem(chosen);

      case WeighPrompt(item: final Item item, unit: final ItemUnit? unit):
        final Qty? qty = await showWeighSheet(context, item: item, unit: unit);
        if (qty != null) await cubit.addItem(item, unit: unit, qty: qty);
    }
    _focusSearch();
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(PosState state) {
    final PosCubit cubit = context.read<PosCubit>();

    void onLine(void Function(int index) action) {
      final int? index = state.selectedLine;
      if (index == null || index < 0 || index >= state.lines.length) return;
      action(index);
    }

    void move(int delta) {
      if (state.lines.isEmpty) return;
      final int next =
          ((state.selectedLine ?? -1) + delta) % state.lines.length;
      cubit.selectLine(next < 0 ? state.lines.length - 1 : next);
    }

    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f2): _focusSearch,
      const SingleActivator(LogicalKeyboardKey.f3): () =>
          _pickCustomer(context, state),
      const SingleActivator(LogicalKeyboardKey.f4): () => _hold(context),
      const SingleActivator(LogicalKeyboardKey.f5): () => _openHeld(state),
      const SingleActivator(LogicalKeyboardKey.f6): () => cubit.setPriceMode(
          state.priceMode == PriceMode.retail
              ? PriceMode.wholesale
              : PriceMode.retail),
      const SingleActivator(LogicalKeyboardKey.f7): () => onLine(
            (int i) => showLineEditor(context, cubit, i, state.lines[i]),
          ),
      const SingleActivator(LogicalKeyboardKey.f8): () => _clearCart(state),
      const SingleActivator(LogicalKeyboardKey.f9): () => _reprint(),
      const SingleActivator(LogicalKeyboardKey.f12): () => _pay(context, state),
      const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
          _pay(context, state),
      const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () =>
          move(1),
      const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () =>
          move(-1),
      const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () =>
          onLine((int i) => cubit.bumpQty(i, 1000)),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () =>
          onLine((int i) => cubit.bumpQty(i, -1000)),
      const SingleActivator(LogicalKeyboardKey.delete, control: true): () =>
          onLine(cubit.removeLine),
      const SingleActivator(LogicalKeyboardKey.escape): _focusSearch,
    };
  }

  Future<void> _openHeld(PosState state) async {
    final PosCubit cubit = context.read<PosCubit>();
    final int? cartId = await showHeldCarts(
      context,
      carts: state.heldCarts,
      onDiscard: cubit.discardCart,
    );
    if (cartId != null) await cubit.resumeCart(cartId);
    if (mounted) _focusSearch();
  }

  Future<void> _clearCart(PosState state) async {
    if (state.isEmpty) return;
    final bool ok = await confirm(
      context,
      icon: Icons.remove_shopping_cart_outlined,
      title: context.tr(AppText.posClearCart),
      message: context.tr(AppText.posClearConfirm),
      confirmLabel: context.tr(AppText.posClearCart),
    );
    if (!ok || !mounted) return;
    context.read<PosCubit>().clearCart();
    _focusSearch();
  }

  Future<void> _reprint() async {
    final bool done = await context.read<PosCubit>().reprintLast();
    if (!mounted) return;
    if (!done) AppSnack.info(context, context.tr(AppText.posNothingToReprint));
    _focusSearch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    CustomerDisplay.instance.configure(
      shopName: context.read<PosCubit>().state.config.shopName,
      labels: <String, String>{
        'welcome': context.tr(AppText.displayWelcome),
        'total': context.tr(AppText.total),
        'discount': context.tr(AppText.discount),
        'paid': context.tr(AppText.paid),
        'change': context.tr(AppText.posChange),
        'thanks': context.tr(AppText.displayThanks),
        'rtl': Directionality.of(context) == TextDirection.rtl ? '1' : '0',
      },
    );
  }

  void _focusSearch() {
    _search.clear();
    _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PosCubit, PosState>(
      listenWhen: (PosState a, PosState b) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, PosState state) {
        AppSnack.warning(context, state.failure!.detail);
        context.read<PosCubit>().clearFailure();
      },
      builder: (BuildContext context, PosState state) {
        if (state.status.isBusyFirstTime) {
          return const Center(child: CircularProgressIndicator());
        }

        final Widget left = Column(
          children: <Widget>[
            //? Search Bar
            SearchBarWidget(
              controller: _search,
              focusNode: _searchFocus,
              state: state,
            ),
            CategoryStrip(state: state),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: PosItemGrid(
                  items: state.results,
                  priceMode: state.priceMode,
                  loading: state.searching,
                  onTap: (Item item) async {
                    await context.read<PosCubit>().addItem(item);
                    _focusSearch();
                  },
                ),
              ),
            ),
          ],
        );

        if (Responsive.isMobile(context)) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: left,
            bottomNavigationBar: PosMobileCartBar(
              state: state,
              onOpen: () => _openCartSheet(context, state),
            ),
          );
        }

        return CallbackShortcuts(
          bindings: _shortcuts(state),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    Expanded(child: left),
                    const PosShortcutBar(),
                  ],
                ),
              ),
              Container(
                width: 420,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: BorderDirectional(
                    start:
                        BorderSide(color: Theme.of(context).surfaces.hairline),
                  ),
                ),
                child: PosCartPanel(
                  state: state,
                  onPay: () => _pay(context, state),
                  onHold: () => _hold(context),
                  onCustomer: () => _pickCustomer(context, state),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCartSheet(BuildContext context, PosState state) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => BlocProvider<PosCubit>.value(
        value: context.read<PosCubit>(),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.9,
          child: BlocBuilder<PosCubit, PosState>(
            builder: (BuildContext context, PosState state) => PosCartPanel(
              state: state,
              onPay: () async {
                Navigator.of(context).pop();
                await _pay(this.context, state);
              },
              onHold: () {
                Navigator.of(context).pop();
                _hold(this.context);
              },
              onCustomer: () => _pickCustomer(context, state),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickCustomer(BuildContext context, PosState state) async {
    final Party? party =
        await showCustomerPicker(context, customers: state.customers);
    if (!mounted) return;
    await context.read<PosCubit>().setCustomer(party);
  }

  Future<void> _hold(BuildContext context) async {
    final PosCubit cubit = context.read<PosCubit>();
    final int? userId = context.read<AuthCubit>().state.user?.id;
    final int? slot = await cubit.holdCart(userId: userId);
    if (!mounted || slot == null) return;
    AppSnack.info(
      context,
      context.tr(AppText.posSlot, params: <String, Object?>{'n': slot}),
    );
    _focusSearch();
  }

  Future<void> _pay(BuildContext context, PosState state) async {
    final PosCubit cubit = context.read<PosCubit>();

    // Better to say so before the customer has their money out than to let
    // the posting fail after the goods are scanned.
    if (state.blockedByShift) {
      await cubit.refreshShift();
      if (!mounted) return;
      if (cubit.state.blockedByShift) {
        AppSnack.warning(context, context.tr(AppText.shiftRequiredWarning));
        return;
      }
    }

    final List<TenderInput>? tenders = await showPaymentSheet(
      context,
      state,
      onPointsChosen: cubit.setPointsToSpend,
    );
    if (!mounted || tenders == null) return;

    final int? userId = context.read<AuthCubit>().state.user?.id;
    final PostedSale? posted =
        await cubit.checkout(tenders: tenders, userId: userId);
    if (!mounted) return;

    if (posted == null) {
      final String? detail = cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
      return;
    }

    // The customer's screen keeps the change on it until the next item is
    // scanned — long enough to count what was handed back.
    CustomerDisplay.instance.show(CustomerView.thankYou(
      context.tr(AppText.displayThanks),
      change: posted.changeMinor > 0 ? Fmt.money(posted.change) : '',
    ));

    AppSnack.success(
      context,
      '${context.tr(AppText.posSaleDone)} — ${posted.invoiceNo}'
      '${posted.changeMinor > 0 ? '   ${context.tr(AppText.posChange)}: ${Fmt.money(posted.change)}' : ''}',
    );
    _focusSearch();
  }
}
