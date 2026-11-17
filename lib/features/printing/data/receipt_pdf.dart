import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/formatters.dart';
import '../domain/receipt_data.dart';

/// Draws a receipt.
///
/// Two layouts from one description: a narrow roll for the thermal printer at
/// the till, and a sheet for an office printer. Both are built from the same
/// [ReceiptData], so the paper the shop happens to own never changes what the
/// receipt says.
class ReceiptPdf {
  const ReceiptPdf._();

  static pw.Font? _regular;
  static pw.Font? _bold;

  /// Loads the bundled Arabic-capable face if the project ships one. Without
  /// it, Arabic and Kurdish text would print as empty boxes — the built-in PDF
  /// fonts only cover Latin.
  static Future<void> loadFonts() async {
    if (_regular != null) return;
    try {
      _regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoKufiArabic-Regular.ttf'),
      );
      _bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf'),
      );
    } catch (_) {
      // No bundled font: fall back to the built-in Latin faces.
      _regular = null;
      _bold = null;
    }
  }

  /// The bundled faces, so other documents — labels, reports — are drawn in
  /// the same type as the receipt rather than loading their own copy.
  static pw.Font? get regularFont => _regular;
  static pw.Font? get boldFont => _bold;

  static pw.ThemeData _theme(double base) => pw.ThemeData.withFont(
        base: _regular,
        bold: _bold,
      ).copyWith(
        defaultTextStyle: pw.TextStyle(
          font: _regular,
          fontBold: _bold,
          fontSize: base,
        ),
      );

  static Future<Uint8List> build(
    ReceiptData data, {
    required String paper,
    bool rtl = false,
  }) async {
    await loadFonts();
    final pw.Document doc = pw.Document();

    switch (paper) {
      case 'roll58':
        _roll(doc, data, width: 58 * PdfPageFormat.mm, base: 7, rtl: rtl);
      case 'roll80':
        _roll(doc, data, width: 80 * PdfPageFormat.mm, base: 8.5, rtl: rtl);
      case 'a5':
        _sheet(doc, data, format: PdfPageFormat.a5, rtl: rtl);
      default:
        _sheet(doc, data, format: PdfPageFormat.a4, rtl: rtl);
    }
    return doc.save();
  }

  // ------------------------------------------------------------------ roll --

  static void _roll(
    pw.Document doc,
    ReceiptData data, {
    required double width,
    required double base,
    required bool rtl,
  }) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          width,
          double.infinity,
          marginAll: 6,
        ),
        theme: _theme(base),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            if (data.businessName.isNotEmpty)
              pw.Center(
                child: pw.Text(
                  data.businessName,
                  style: pw.TextStyle(
                    fontSize: base + 3,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            if (data.businessPhone.isNotEmpty || data.businessAddress.isNotEmpty)
              pw.Center(
                child: pw.Text(
                  <String>[data.businessAddress, data.businessPhone]
                      .where((String s) => s.isNotEmpty)
                      .join(' · '),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            if (data.headerText.isNotEmpty)
              pw.Center(child: pw.Text(data.headerText, textAlign: pw.TextAlign.center)),
            pw.SizedBox(height: 4),
            _dashes(),
            _kv(data.title, data.documentNo, bold: true),
            _kv('', Fmt.dateTime(data.issuedAt)),
            if (data.partyName != null) _kv('', data.partyName!),
            if (data.cashierName != null) _kv('', data.cashierName!),
            _dashes(),
            for (final ReceiptLine l in data.lines) ...<pw.Widget>[
              pw.Text(l.name, maxLines: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[
                  pw.Text(
                    '${Fmt.qtyMilli(l.qtyMilli)} ${l.unitName} × '
                    '${Fmt.moneyPlain(l.unitPriceMinor)}'
                    '${l.discountMinor > 0 ? '  −${Fmt.moneyPlain(l.discountMinor)}' : ''}',
                  ),
                  pw.Text(
                    l.isGift ? 'GIFT' : Fmt.moneyPlain(l.totalMinor),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
            ],
            _dashes(),
            _kv('Subtotal', Fmt.moneyPlain(data.subtotalMinor)),
            if (data.discountMinor != 0)
              _kv('Discount', '−${Fmt.moneyPlain(data.discountMinor)}'),
            if (data.taxMinor != 0) _kv('Tax', Fmt.moneyPlain(data.taxMinor)),
            if (data.serviceMinor != 0)
              _kv('Service', Fmt.moneyPlain(data.serviceMinor)),
            if (data.roundingMinor != 0)
              _kv('Rounding', Fmt.moneyPlain(data.roundingMinor)),
            _dashes(),
            _kv('TOTAL', Fmt.moneyMinor(data.totalMinor), bold: true, size: base + 3),
            for (final ReceiptTender t in data.tenders) ...<pw.Widget>[
              _kv(
                t.isForeign ? '${t.method} · ${t.foreignText}' : t.method,
                Fmt.moneyPlain(t.amountMinor),
              ),
              // The rate goes on the receipt, not just in the database: a
              // customer checking their change tomorrow needs the number that
              // was used today.
              if (t.isForeign) _kv(t.rateText, ''),
            ],
            if (data.changeMinor > 0)
              _kv('Change', Fmt.moneyPlain(data.changeMinor), bold: true),
            if (data.dueMinor > 0)
              _kv('Remaining', Fmt.moneyPlain(data.dueMinor), bold: true),
            _dashes(),
            pw.Center(
              child: pw.Text(
                '${data.itemCount} items · ${Fmt.qtyMilli(data.unitsMilli)} units',
              ),
            ),
            if (data.note != null && data.note!.isNotEmpty)
              pw.Center(child: pw.Text(data.note!, textAlign: pw.TextAlign.center)),
            pw.SizedBox(height: 4),
            if (data.showBarcode)
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: data.documentNo,
                  width: width - 40,
                  height: 34,
                  drawText: false,
                ),
              ),
            if (data.footerText.isNotEmpty) ...<pw.Widget>[
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text(data.footerText, textAlign: pw.TextAlign.center)),
            ],
            pw.SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  static pw.Widget _dashes() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Container(height: 0.6, color: PdfColors.grey600),
      );

  static pw.Widget _kv(
    String key,
    String value, {
    bool bold = false,
    double? size,
  }) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            key,
            style: pw.TextStyle(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: size,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: size,
            ),
          ),
        ],
      );

  // ----------------------------------------------------------------- sheet --

  static void _sheet(
    pw.Document doc,
    ReceiptData data, {
    required PdfPageFormat format,
    required bool rtl,
  }) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        theme: _theme(10),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        margin: const pw.EdgeInsets.all(28),
        header: (pw.Context c) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      data.businessName,
                      style: pw.TextStyle(
                        fontSize: 17,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (data.businessAddress.isNotEmpty)
                      pw.Text(data.businessAddress),
                    if (data.businessPhone.isNotEmpty)
                      pw.Text(data.businessPhone),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: <pw.Widget>[
                    pw.Text(
                      data.title,
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(data.documentNo),
                    pw.Text(Fmt.dateTime(data.issuedAt)),
                    if (data.partyName != null) pw.Text(data.partyName!),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(),
          ],
        ),
        build: (pw.Context c) => <pw.Widget>[
          pw.TableHelper.fromTextArray(
            border: null,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignments: <int, pw.Alignment>{
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headers: <String>['#', 'Item', 'Qty', 'Unit', 'Price', 'Total'],
            data: <List<String>>[
              for (int i = 0; i < data.lines.length; i++)
                <String>[
                  '${i + 1}',
                  data.lines[i].name,
                  Fmt.qtyMilli(data.lines[i].qtyMilli),
                  data.lines[i].unitName,
                  Fmt.moneyPlain(data.lines[i].unitPriceMinor),
                  data.lines[i].isGift
                      ? 'GIFT'
                      : Fmt.moneyPlain(data.lines[i].totalMinor),
                ],
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: <pw.Widget>[
              pw.SizedBox(
                width: 240,
                child: pw.Column(
                  children: <pw.Widget>[
                    _kv('Subtotal', Fmt.moneyPlain(data.subtotalMinor)),
                    if (data.discountMinor != 0)
                      _kv('Discount', '−${Fmt.moneyPlain(data.discountMinor)}'),
                    if (data.taxMinor != 0)
                      _kv('Tax', Fmt.moneyPlain(data.taxMinor)),
                    if (data.serviceMinor != 0)
                      _kv('Service', Fmt.moneyPlain(data.serviceMinor)),
                    if (data.roundingMinor != 0)
                      _kv('Rounding', Fmt.moneyPlain(data.roundingMinor)),
                    pw.Divider(),
                    _kv('Total', Fmt.moneyMinor(data.totalMinor),
                        bold: true, size: 13),
                    _kv('Paid', Fmt.moneyPlain(data.paidMinor)),
                    if (data.dueMinor > 0)
                      _kv('Remaining', Fmt.moneyPlain(data.dueMinor), bold: true),
                  ],
                ),
              ),
            ],
          ),
          if (data.footerText.isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 20),
            pw.Center(child: pw.Text(data.footerText)),
          ],
        ],
      ),
    );
  }
}
