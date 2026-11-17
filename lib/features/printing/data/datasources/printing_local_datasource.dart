import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:printing/printing.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/printing/esc_pos.dart';
import '../../../../core/printing/esc_pos_transport.dart';
import '../../../../core/printing/receipt_raster.dart';
import '../../../../core/utils/time.dart';
import '../../domain/entities/printer_profile.dart';
import '../../domain/receipt_data.dart';
import '../receipt_pdf.dart';

/// Printer profiles, receipt assembly, and the one path to paper.
class PrintingLocalDataSource {
  PrintingLocalDataSource(this._database);

  final AppDatabase _database;

  PrinterProfile? _cachedDefault;

  // ------------------------------------------------------------ profiles ---

  Future<List<PrinterProfile>> profiles() async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'printer_profiles',
      orderBy: 'is_default DESC, name COLLATE NOCASE',
    );
    return rows.map(PrinterProfile.fromMap).toList();
  }

  Future<PrinterProfile?> defaultProfile({bool refresh = false}) async {
    if (_cachedDefault != null && !refresh) return _cachedDefault;

    final List<Map<String, Object?>> rows = await _database.db.query(
      'printer_profiles',
      where: 'is_active = 1',
      orderBy: 'is_default DESC, id',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _cachedDefault = PrinterProfile.fromMap(rows.first);
  }

  Future<int> saveProfile(PrinterProfile profile) async {
    if (profile.name.trim().isEmpty) {
      throw const AppFailure.validation('The printer needs a name.');
    }
    if (profile.driver.needsAddress &&
        profile.driver != PrinterDriver.system &&
        (profile.address ?? '').trim().isEmpty) {
      throw const AppFailure.validation(
        'A thermal printer needs an address — the device or the IP it answers '
        'on.',
      );
    }
    if (profile.copies < 1 || profile.copies > 5) {
      throw const AppFailure.validation('Print between one and five copies.');
    }

    final String stamp = Time.stamp();
    final Map<String, Object?> values = profile.toDb()..['updated_at'] = stamp;

    final int id;
    if (profile.id == null) {
      values['created_at'] = stamp;
      id = await _database.db.insert('printer_profiles', values);
    } else {
      id = profile.id!;
      await _database.db.update('printer_profiles', values,
          where: 'id = ?', whereArgs: <Object?>[id]);
    }

    // Exactly one default, always.
    if (profile.isDefault) {
      await _database.db.update(
        'printer_profiles',
        <String, Object?>{'is_default': 0},
        where: 'id <> ?',
        whereArgs: <Object?>[id],
      );
    }

    _cachedDefault = null;
    return id;
  }

  Future<void> deleteProfile(int id) async {
    await _database.db
        .delete('printer_profiles', where: 'id = ?', whereArgs: <Object?>[id]);
    _cachedDefault = null;

    // Never leave the shop without a default: the first surviving profile
    // takes over, or the till would silently stop printing.
    final List<Map<String, Object?>> left = await _database.db.query(
      'printer_profiles',
      columns: <String>['id', 'is_default'],
      orderBy: 'id',
    );
    if (left.isNotEmpty &&
        !left.any((Map<String, Object?> r) => (r['is_default'] as int? ?? 0) == 1)) {
      await _database.db.update(
        'printer_profiles',
        <String, Object?>{'is_default': 1},
        where: 'id = ?',
        whereArgs: <Object?>[left.first['id']],
      );
    }
  }

  // ------------------------------------------------------------ documents --

  Future<ReceiptData> saleReceipt(int invoiceId) async {
    final List<Map<String, Object?>> head = await _database.db.query(
      'v_sales_invoices_full',
      where: 'id = ?',
      whereArgs: <Object?>[invoiceId],
      limit: 1,
    );
    if (head.isEmpty) {
      throw const AppFailure.notFound('That invoice no longer exists.');
    }
    final Map<String, Object?> h = head.first;

    final List<Map<String, Object?>> lines = await _database.db.rawQuery(
      '''
      SELECT l.*,
             CASE WHEN i.variant_name IS NULL OR i.variant_name = ''
                  THEN i.name
                  ELSE i.name || ' — ' || i.variant_name END AS item_name
        FROM sales_invoice_lines l
        JOIN items i ON i.id = l.item_id
       WHERE l.invoice_id = ?
       ORDER BY l.line_no
      ''',
      <Object?>[invoiceId],
    );

    final List<Map<String, Object?>> tenders = await _database.db.query(
      'sale_tenders',
      where: 'invoice_id = ?',
      whereArgs: <Object?>[invoiceId],
    );

    final PrinterProfile? profile = await defaultProfile();

    return ReceiptData(
      title: '${h['doc_type']}' == 'sale_return' ? 'RETURN' : 'INVOICE',
      documentNo: '${h['invoice_no']}',
      issuedAt: '${h['issued_at']}',
      businessName: _database.settingString('business_name'),
      businessPhone: _database.settingString('business_phone'),
      businessAddress: _database.settingString('business_address'),
      headerText: profile?.headerText ?? '',
      footerText: profile?.footerText ?? '',
      partyName: h['party_name'] as String?,
      partyPhone: h['party_phone'] as String?,
      cashierName: h['cashier_name'] as String?,
      note: h['note'] as String?,
      showBarcode: profile?.showBarcode ?? true,
      logoPath: profile?.showLogo ?? true ? profile?.logoPath : null,
      subtotalMinor: h['subtotal_minor'] as int? ?? 0,
      discountMinor: h['discount_total_minor'] as int? ?? 0,
      taxMinor: h['tax_minor'] as int? ?? 0,
      serviceMinor: h['service_charge_minor'] as int? ?? 0,
      roundingMinor: h['rounding_minor'] as int? ?? 0,
      totalMinor: h['total_minor'] as int? ?? 0,
      paidMinor: h['paid_minor'] as int? ?? 0,
      changeMinor: h['change_minor'] as int? ?? 0,
      dueMinor: h['due_minor'] as int? ?? 0,
      lines: lines
          .map((Map<String, Object?> l) => ReceiptLine(
                name: '${l['item_name']}',
                qtyMilli: l['qty_milli'] as int? ?? 0,
                unitName: '${l['unit_name'] ?? ''}',
                unitPriceMinor: l['unit_price_minor'] as int? ?? 0,
                discountMinor: (l['line_discount_minor'] as int? ?? 0) +
                    (l['alloc_discount_minor'] as int? ?? 0),
                totalMinor: l['total_minor'] as int? ?? 0,
                isGift: (l['is_gift'] as int? ?? 0) == 1,
              ))
          .toList(),
      tenders: tenders
          .map((Map<String, Object?> t) => ReceiptTender(
                method: '${t['method']}',
                amountMinor: t['amount_minor'] as int? ?? 0,
                currencyCode: '${t['currency_code'] ?? ''}',
                amountFxMinor: t['amount_fx_minor'] as int? ?? 0,
                fxRateMilli: t['fx_rate_milli'] as int? ?? 0,
              ))
          .toList(),
    );
  }

  Future<Uint8List> render(
    ReceiptData data, {
    PrinterProfile? profile,
    bool rtl = false,
  }) async {
    final PrinterProfile? p = profile ?? await defaultProfile();
    return ReceiptPdf.build(
      data,
      paper: (p?.paper ?? PaperSize.roll80).dbValue,
      rtl: rtl,
    );
  }

  Future<void> printSale(int invoiceId, {bool rtl = false}) async {
    final PrinterProfile? profile = await defaultProfile();
    if (profile == null) {
      throw const AppFailure.notFound(
        'No printer is set up yet — add one in Printing.',
      );
    }
    final ReceiptData data = await saleReceipt(invoiceId);
    final Uint8List bytes = await render(data, profile: profile, rtl: rtl);

    // A thermal printer takes all the copies in one conversation — the page is
    // rasterised once and repeated, rather than rendered again per copy.
    if (_isThermal(profile)) {
      await _sendThermal(bytes, profile);
      return;
    }

    for (int copy = 0; copy < profile.copies; copy++) {
      await _send(bytes, profile);
    }
  }

  /// Opens the drawer without printing anything — the button a cashier presses
  /// when they need change and there is no sale to ring up.
  Future<void> kickDrawer({PrinterProfile? profile}) async {
    final PrinterProfile? p = profile ?? await defaultProfile();
    final EscPosTransport? transport =
        p == null ? null : transportFor(p.address);
    if (p == null || transport == null || !_isThermal(p)) {
      throw const AppFailure.validation(
        'The cash drawer opens through a thermal printer. Set the printer up '
        'as a network or shared printer first.',
      );
    }
    await transport.send(EscPos.openDrawerBoth());
  }

  bool _isThermal(PrinterProfile profile) =>
      (profile.driver == PrinterDriver.escPosNetwork ||
          profile.driver == PrinterDriver.escPosUsb) &&
      (profile.address ?? '').trim().isNotEmpty;

  /// The raster path: lay the receipt out once, turn it into dots, and send it
  /// with the drawer and the cutter in the same burst.
  Future<void> _sendThermal(Uint8List pdf, PrinterProfile profile) async {
    final EscPosTransport? transport = transportFor(profile.address);
    if (transport == null) {
      throw const AppFailure.validation(
        'This printer has no address. Give it an IP address, or the name it '
        'is shared under in Windows.',
      );
    }

    final RasterBitmap? bitmap = await ReceiptRaster.monochrome(
      pdf,
      dotsWide: ReceiptRaster.dotsFor(profile.paper.dbValue),
    );
    if (bitmap == null || bitmap.isEmpty) {
      // Rasterising is not available on every platform. Falling back keeps the
      // receipt coming out, just through the system dialog.
      await Printing.layoutPdf(onLayout: (_) async => pdf, name: profile.name);
      return;
    }

    await transport.send(EscPos.receipt(
      bitmap.bits,
      widthBytes: bitmap.widthBytes,
      height: bitmap.height,
      kickDrawer: profile.openDrawer,
      copies: profile.copies,
    ));
  }

  Future<void> present(Uint8List bytes, {String name = 'document'}) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  /// Every driver we support today can consume a rendered page. The dedicated
  /// thermal transports plug in here — `directPrintPdf` when the profile names
  /// a printer we can find — and the dialog keeps the till working until one is
  /// configured.
  Future<void> _send(Uint8List bytes, PrinterProfile profile) async {
    if (_isThermal(profile)) {
      await _sendThermal(bytes, profile);
      return;
    }
    if (profile.driver == PrinterDriver.pdf || profile.address == null) {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: profile.name);
      return;
    }

    final List<Printer> found = await Printing.listPrinters();
    final Printer? match = found.firstWhereOrNull(
      (Printer p) => p.name == profile.address || p.url == profile.address,
    );
    if (match != null) {
      await Printing.directPrintPdf(
        printer: match,
        onLayout: (_) async => bytes,
        name: profile.name,
      );
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: profile.name);
  }

  /// A page of sample content, so a printer can be proved before a customer is
  /// standing at the counter.
  Future<Uint8List> testPage(PrinterProfile profile, {bool rtl = false}) async {
    final ReceiptData data = ReceiptData(
      title: 'TEST',
      documentNo: 'TEST-000001',
      issuedAt: Time.stamp(),
      businessName: _database.settingString('business_name', 'My Store'),
      businessPhone: _database.settingString('business_phone'),
      businessAddress: _database.settingString('business_address'),
      headerText: profile.headerText,
      footerText: profile.footerText,
      showBarcode: profile.showBarcode,
      logoPath: profile.showLogo ? profile.logoPath : null,
      lines: const <ReceiptLine>[
        ReceiptLine(
          name: 'Sample item',
          qtyMilli: 2000,
          unitName: 'pcs',
          unitPriceMinor: 125000,
          discountMinor: 0,
          totalMinor: 250000,
        ),
        ReceiptLine(
          name: 'Sample item in a carton',
          qtyMilli: 1000,
          unitName: 'ctn',
          unitPriceMinor: 1400000,
          discountMinor: 100000,
          totalMinor: 1300000,
        ),
      ],
      subtotalMinor: 1550000,
      discountMinor: 100000,
      taxMinor: 0,
      serviceMinor: 0,
      roundingMinor: 0,
      totalMinor: 1550000,
      paidMinor: 1600000,
      changeMinor: 50000,
      dueMinor: 0,
      tenders: const <ReceiptTender>[
        ReceiptTender(method: 'cash', amountMinor: 1600000),
      ],
    );
    return render(data, profile: profile, rtl: rtl);
  }
}
