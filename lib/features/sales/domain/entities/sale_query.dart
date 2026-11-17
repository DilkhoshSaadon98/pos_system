
//? This is used to query the sales list from the database.
class SalesQuery {
  const SalesQuery({
    required this.from,
    required this.to,
    this.partyId,
    this.search,
    this.docType,
    this.onlyUnpaid = false,
  });

  final DateTime from;
  final DateTime to;
  final int? partyId;
  final String? search;

  //? `sale`, `sale_return`, or null for both.
  final String? docType;

  final bool onlyUnpaid;

  SalesQuery copyWith({
    DateTime? from,
    DateTime? to,
    int? partyId,
    bool clearParty = false,
    String? search,
    String? docType,
    bool clearDocType = false,
    bool? onlyUnpaid,
  }) =>
      SalesQuery(
        from: from ?? this.from,
        to: to ?? this.to,
        partyId: clearParty ? null : (partyId ?? this.partyId),
        search: search ?? this.search,
        docType: clearDocType ? null : (docType ?? this.docType),
        onlyUnpaid: onlyUnpaid ?? this.onlyUnpaid,
      );
}
