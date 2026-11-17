import 'package:flutter/material.dart';

import '../../../../core/format/formatters.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/app_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/surfaces.dart';
import '../../../../core/widgets/modals.dart';
import '../../../../core/widgets/panels.dart';
import '../../domain/entities/party.dart';
import '../cubit/parties_cubit.dart';

/// A party's ledger, straight out of the journal.
///
/// Every line here is a real posting — an invoice, a receipt, an opening
/// balance — with the balance as it stood after it. Nothing is derived from the
/// invoice tables, which is why this and the trial balance can never disagree.
Future<void> showStatement(
  BuildContext context,
  PartiesCubit cubit,
  Party party,
) =>
    showAppModal<void>(
      context,
      width: 720,
      title: context.tr(AppText.partiesStatement),
      subtitle: party.name,
      builder: (BuildContext context) => _Statement(cubit: cubit, party: party),
    );

class _Statement extends StatefulWidget {
  const _Statement({required this.cubit, required this.party});

  final PartiesCubit cubit;
  final Party party;

  @override
  State<_Statement> createState() => _StatementState();
}

class _StatementState extends State<_Statement> {
  bool _loading = true;
  List<StatementRow> _rows = const <StatementRow>[];
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final List<StatementRow> rows =
        await widget.cubit.statement(widget.party.id, from: _from, to: _to);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.surfaces.raised,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TotalRow(
                  emphasis: true,
                  label: context.tr(widget.party.owesUs
                      ? AppText.partiesOwesUs
                      : AppText.partiesWeOwe),
                  value: Fmt.money(widget.party.balance.abs),
                  color: widget.party.owesUs
                      ? AppColors.warning
                      : AppColors.info,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final DateTimeRange? picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(DateTime.now().year - 5),
                  lastDate: DateTime(DateTime.now().year + 1),
                );
                if (picked != null) {
                  _from = picked.start;
                  _to = picked.end;
                  await _load();
                }
              },
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(context.tr(AppText.period)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_rows.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            message: context.tr(AppText.nothingYet),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.surfaces.hairline),
            ),
            child: Column(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.surfaces.raised,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(11),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        flex: 4,
                        child: Text(context.tr(AppText.date),
                            style: theme.textTheme.labelSmall),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          context.tr(AppText.acctDebit),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          context.tr(AppText.acctCredit),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          context.tr(AppText.partiesRunning),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final StatementRow row in _rows) ...<Widget>[
                  Divider(height: 1, color: theme.surfaces.hairline),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                '${Fmt.date(row.date)}  ·  ${row.entryNo}',
                                style: theme.textTheme.bodySmall,
                              ),
                              if (row.memo.isNotEmpty)
                                Text(row.memo,
                                    style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            row.debit.isZero ? '' : Fmt.money(row.debit,
                                withSymbol: false),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyMedium
                                ?.merge(theme.tabular),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            row.credit.isZero
                                ? ''
                                : Fmt.money(row.credit, withSymbol: false),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyMedium
                                ?.merge(theme.tabular),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            Fmt.money(row.balance, withSymbol: false),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700)
                                .merge(theme.tabular),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
