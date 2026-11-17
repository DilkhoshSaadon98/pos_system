import 'dart:typed_data';

import 'package:barcode/barcode.dart' as bc;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/format/formatters.dart';
import '../printing/data/receipt_pdf.dart';

/// What goes on one label, and how many of it to print.
class LabelRequest {
  const LabelRequest({
    required this.name,
    required this.priceMinor,
    required this.code,
    this.copies = 1,
    this.unitName = '',
    this.sku,
  });

  final String name;
  final int priceMinor;

  /// The barcode as it is stored — an EAN-13 if the item has one, otherwise
  /// whatever the shop uses internally.
  final String code;

  final int copies;
  final String unitName;
  final String? sku;

  bool get hasCode => code.trim().isNotEmpty;
}

/// The shapes of label stock a shop actually buys.
enum LabelSize {
  /// A roll label for shelf edges and small goods.
  small('40x30', 40, 30),

  /// The most common roll label in this trade.
  medium('50x30', 50, 30),

  /// A wider roll for anything with a long name.
  wide('58x40', 58, 40),

  /// Plain A4 through an office printer, laid out in a grid.
  sheetA4('a4', 210, 297);

  const LabelSize(this.dbValue, this.widthMm, this.heightMm);

  final String dbValue;
  final double widthMm;
  final double heightMm;

  bool get isSheet => this == LabelSize.sheetA4;

  static LabelSize fromDb(Object? value) => LabelSize.values.firstWhere(
        (LabelSize s) => s.dbValue == '$value',
        orElse: () => LabelSize.medium,
      );
}

/// Draws shelf and product labels.
///
/// The barcode is chosen from the data rather than from a setting: thirteen
/// digits that pass the EAN check digit are printed as an EAN-13, because that
/// is what a supermarket scanner expects and what most suppliers print; and
/// anything else — an internal code, a code with letters — is a Code 128,
/// which scans reliably and can hold whatever the shop wants. Getting this
/// wrong is how a label ends up scanning as a different product.
class LabelPdf {
  const LabelPdf._();

  static Future<Uint8List> build(
    List<LabelRequest> labels, {
    LabelSize size = LabelSize.medium,
    String shopName = '',
    bool showName = true,
    bool showPrice = true,
    bool showShop = false,
    int columns = 3,
  }) async {
    await ReceiptPdf.loadFonts();
    final pw.Document doc = pw.Document();

    final List<LabelRequest> expanded = <LabelRequest>[
      for (final LabelRequest l in labels)
        for (int i = 0; i < (l.copies < 1 ? 1 : l.copies); i++) l,
    ];
    if (expanded.isEmpty) return doc.save();

    if (size.isSheet) {
      _sheet(doc, expanded,
          columns: columns,
          shopName: shopName,
          showName: showName,
          showPrice: showPrice,
          showShop: showShop);
    } else {
      _roll(doc, expanded,
          size: size,
          shopName: shopName,
          showName: showName,
          showPrice: showPrice,
          showShop: showShop);
    }

    return doc.save();
  }

  /// One label per page, which is what a roll printer expects: it cuts or
  /// tears between pages, so a page *is* a label.
  static void _roll(
    pw.Document doc,
    List<LabelRequest> labels, {
    required LabelSize size,
    required String shopName,
    required bool showName,
    required bool showPrice,
    required bool showShop,
  }) {
    final PdfPageFormat format = PdfPageFormat(
      size.widthMm * PdfPageFormat.mm,
      size.heightMm * PdfPageFormat.mm,
      marginAll: 2 * PdfPageFormat.mm,
    );

    for (final LabelRequest label in labels) {
      doc.addPage(
        pw.Page(
          pageFormat: format,
          theme: _theme(size == LabelSize.small ? 6.5 : 7.5),
          build: (pw.Context context) => _label(
            label,
            shopName: shopName,
            showName: showName,
            showPrice: showPrice,
            showShop: showShop,
            barcodeHeight: (size.heightMm * 0.38) * PdfPageFormat.mm,
          ),
        ),
      );
    }
  }

  /// A grid on A4, for shops without a label printer.
  ///
  /// The cells are drawn without borders on purpose: printed borders never
  /// line up with the die-cut of the sheet, and a faint misaligned rectangle
  /// on every label looks worse than none at all.
  static void _sheet(
    pw.Document doc,
    List<LabelRequest> labels, {
    required int columns,
    required String shopName,
    required bool showName,
    required bool showPrice,
    required bool showShop,
  }) {
    final int cols = columns.clamp(1, 5);
    const int rows = 8;
    final int perPage = cols * rows;

    for (int start = 0; start < labels.length; start += perPage) {
      final List<LabelRequest> page = labels.sublist(
        start,
        start + perPage > labels.length ? labels.length : start + perPage,
      );

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.copyWith(
            marginTop: 10 * PdfPageFormat.mm,
            marginBottom: 10 * PdfPageFormat.mm,
            marginLeft: 6 * PdfPageFormat.mm,
            marginRight: 6 * PdfPageFormat.mm,
          ),
          theme: _theme(7.5),
          build: (pw.Context context) => pw.GridView(
            crossAxisCount: cols,
            childAspectRatio: 1.55,
            children: <pw.Widget>[
              for (final LabelRequest label in page)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: _label(
                    label,
                    shopName: shopName,
                    showName: showName,
                    showPrice: showPrice,
                    showShop: showShop,
                    barcodeHeight: 26,
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }

  static pw.Widget _label(
    LabelRequest label, {
    required String shopName,
    required bool showName,
    required bool showPrice,
    required bool showShop,
    required double barcodeHeight,
  }) {
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: <pw.Widget>[
        if (showShop && shopName.isNotEmpty)
          pw.Text(
            shopName,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: const pw.TextStyle(fontSize: 6),
          ),
        if (showName)
          pw.Text(
            label.name,
            textAlign: pw.TextAlign.center,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        if (showPrice)
          pw.Text(
            Fmt.moneyMinor(label.priceMinor) +
                (label.unitName.isEmpty ? '' : ' / ${label.unitName}'),
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        if (label.hasCode) ...<pw.Widget>[
          pw.SizedBox(height: 2),
          pw.BarcodeWidget(
            barcode: _barcodeFor(label.code),
            data: label.code.trim(),
            drawText: true,
            height: barcodeHeight,
            textStyle: const pw.TextStyle(fontSize: 6),
          ),
        ] else if (label.sku != null && label.sku!.isNotEmpty)
          pw.Text(label.sku!, style: const pw.TextStyle(fontSize: 6)),
      ],
    );
  }

  /// EAN-13 when the code really is one, Code 128 otherwise.
  static bc.Barcode _barcodeFor(String code) {
    final String c = code.trim();
    if (c.length == 13 && RegExp(r'^\d{13}$').hasMatch(c) && _eanValid(c)) {
      return bc.Barcode.ean13();
    }
    if (c.length == 8 && RegExp(r'^\d{8}$').hasMatch(c)) {
      return bc.Barcode.ean8();
    }
    return bc.Barcode.code128();
  }

  /// The EAN check digit, so a mistyped code is printed as a Code 128 that
  /// scans rather than as an EAN-13 the printer refuses to draw.
  static bool _eanValid(String code) {
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final int d = code.codeUnitAt(i) - 48;
      sum += i.isEven ? d : d * 3;
    }
    final int check = (10 - (sum % 10)) % 10;
    return check == code.codeUnitAt(12) - 48;
  }

  static pw.ThemeData _theme(double base) => pw.ThemeData.withFont(
        base: ReceiptPdf.regularFont,
        bold: ReceiptPdf.boldFont,
      ).copyWith(
        defaultTextStyle: pw.TextStyle(
          font: ReceiptPdf.regularFont,
          fontBold: ReceiptPdf.boldFont,
          fontSize: base,
        ),
      );
}
