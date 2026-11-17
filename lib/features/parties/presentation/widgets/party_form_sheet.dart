import 'package:flutter/material.dart';

import '../../../../core/classes/enums.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/money/money.dart';
import '../../../../core/widgets/app_snack.dart';
import '../../../../core/widgets/form_fields.dart';
import '../../../../core/widgets/modals.dart';
import '../../domain/entities/party.dart';
import '../cubit/parties_cubit.dart';

Future<void> showPartyForm(
  BuildContext context,
  PartiesCubit cubit,
  Party? party,
) =>
    showAppModal<void>(
      context,
      width: 520,
      title: context.tr(
        party != null
            ? AppText.edit
            : cubit.state.isCustomers
                ? AppText.partiesNewCustomer
                : AppText.partiesNewSupplier,
      ),
      subtitle: party?.name,
      builder: (BuildContext context) => _PartyForm(cubit: cubit, party: party),
    );

class _PartyForm extends StatefulWidget {
  const _PartyForm({required this.cubit, this.party});

  final PartiesCubit cubit;
  final Party? party;

  @override
  State<_PartyForm> createState() => _PartyFormState();
}

class _PartyFormState extends State<_PartyForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.party?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.party?.phone ?? '');
  late final TextEditingController _phone2 =
      TextEditingController(text: widget.party?.phone2 ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.party?.email ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.party?.address ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.party?.note ?? '');
  late final TextEditingController _limit = TextEditingController(
    text: (widget.party?.creditLimit ?? Money.zero).isZero
        ? ''
        : Fmt.moneyPlain(widget.party!.creditLimit.minor),
  );

  late PartyKind _kind = widget.party?.kind ??
      (widget.cubit.state.isCustomers
          ? PartyKind.customer
          : PartyKind.supplier);
  late bool _active = widget.party?.isActive ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _phone2.dispose();
    _email.dispose();
    _address.dispose();
    _note.dispose();
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            controller: _name,
            autofocus: true,
            label: context.tr(AppText.name),
            prefixIcon: Icons.person_outline,
            validator: (String? v) => (v ?? '').trim().isEmpty
                ? context.tr(AppText.requiredField)
                : null,
          ),
          const SizedBox(height: 14),
          AppDropdown<PartyKind>(
            label: context.tr(AppText.partiesKind),
            value: _kind,
            items: PartyKind.values,
            itemLabel: (PartyKind k) => context.tr(k.labelKey),
            onChanged: (PartyKind? k) =>
                setState(() => _kind = k ?? _kind),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  controller: _phone,
                  label: context.tr(AppText.phone),
                  prefixIcon: Icons.call_outlined,
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  controller: _phone2,
                  label: context.tr(AppText.partiesPhone2),
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _email,
            label: context.tr(AppText.partiesEmail),
            prefixIcon: Icons.alternate_email,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _address,
            label: context.tr(AppText.address),
            prefixIcon: Icons.place_outlined,
            maxLines: 2,
          ),
          const SizedBox(height: 14),
          MoneyField(
            controller: _limit,
            label: context.tr(AppText.partiesCreditLimit),
            helper: context.tr(AppText.none),
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _note,
            label: context.tr(AppText.note),
            maxLines: 2,
          ),
          const SizedBox(height: 6),
          AppSwitchTile(
            icon: Icons.visibility_outlined,
            title: context.tr(AppText.active),
            value: _active,
            onChanged: (bool v) => setState(() => _active = v),
          ),
          const SizedBox(height: 18),
          ModalActions(busy: _busy, onSave: _save),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);

    final bool ok = await widget.cubit.save(PartySaveRequest(
      id: widget.party?.id,
      name: _name.text,
      kind: _kind,
      phone: _phone.text,
      phone2: _phone2.text,
      email: _email.text,
      address: _address.text,
      note: _note.text,
      creditLimit: MoneyField.read(_limit) ?? Money.zero,
      isActive: _active,
    ));
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      AppSnack.success(context, context.tr(AppText.saved));
      Navigator.of(context).pop();
    } else {
      final String? detail = widget.cubit.state.failure?.detail;
      if (detail != null) AppSnack.error(context, detail);
    }
  }
}
