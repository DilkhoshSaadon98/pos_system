import '../../../../core/localization/app_text.dart';

/// A printer the shop has, and how it should be used.
///
/// A profile rather than a global setting, because a shop that grows ends up
/// with two: the thermal roll at the till and the A4 on the desk for a
/// customer who wants an invoice on paper.
class PrinterProfile {
  const PrinterProfile({
    this.id,
    required this.name,
    required this.driver,
    required this.paper,
    this.address,
    this.copies = 1,
    this.headerText = '',
    this.footerText = '',
    this.logoPath,
    this.showLogo = true,
    this.showBarcode = true,
    this.showTaxLines = true,
    this.openDrawer = false,
    this.autoPrint = true,
    this.fontScaleBp = 10000,
    this.isDefault = false,
    this.isActive = true,
  });

  factory PrinterProfile.fromMap(Map<String, Object?> m) => PrinterProfile(
        id: m['id'] as int?,
        name: '${m['name']}',
        driver: PrinterDriver.fromDb(m['driver']),
        paper: PaperSize.fromDb(m['paper']),
        address: m['address'] as String?,
        copies: m['copies'] as int? ?? 1,
        headerText: '${m['header_text'] ?? ''}',
        footerText: '${m['footer_text'] ?? ''}',
        logoPath: m['logo_path'] as String?,
        showLogo: (m['show_logo'] as int? ?? 1) == 1,
        showBarcode: (m['show_barcode'] as int? ?? 1) == 1,
        showTaxLines: (m['show_tax_lines'] as int? ?? 1) == 1,
        openDrawer: (m['open_drawer'] as int? ?? 0) == 1,
        autoPrint: (m['auto_print'] as int? ?? 1) == 1,
        fontScaleBp: m['font_scale_bp'] as int? ?? 10000,
        isDefault: (m['is_default'] as int? ?? 0) == 1,
        isActive: (m['is_active'] as int? ?? 1) == 1,
      );

  final int? id;
  final String name;
  final PrinterDriver driver;
  final PaperSize paper;

  /// The printer's name on the system, or its address on the network.
  final String? address;

  final int copies;
  final String headerText;
  final String footerText;
  final String? logoPath;
  final bool showLogo;
  final bool showBarcode;
  final bool showTaxLines;
  final bool openDrawer;
  final bool autoPrint;
  final int fontScaleBp;
  final bool isDefault;
  final bool isActive;

  Map<String, Object?> toDb() => <String, Object?>{
        'name': name.trim(),
        'driver': driver.dbValue,
        'paper': paper.dbValue,
        'address': (address ?? '').trim().isEmpty ? null : address!.trim(),
        'copies': copies,
        'header_text': headerText,
        'footer_text': footerText,
        'logo_path': logoPath,
        'show_logo': showLogo ? 1 : 0,
        'show_barcode': showBarcode ? 1 : 0,
        'show_tax_lines': showTaxLines ? 1 : 0,
        'open_drawer': openDrawer ? 1 : 0,
        'auto_print': autoPrint ? 1 : 0,
        'font_scale_bp': fontScaleBp,
        'is_default': isDefault ? 1 : 0,
        'is_active': isActive ? 1 : 0,
      };

  PrinterProfile copyWith({
    String? name,
    PrinterDriver? driver,
    PaperSize? paper,
    String? address,
    int? copies,
    String? headerText,
    String? footerText,
    String? logoPath,
    bool? showLogo,
    bool? showBarcode,
    bool? showTaxLines,
    bool? openDrawer,
    bool? autoPrint,
    int? fontScaleBp,
    bool? isDefault,
    bool? isActive,
  }) =>
      PrinterProfile(
        id: id,
        name: name ?? this.name,
        driver: driver ?? this.driver,
        paper: paper ?? this.paper,
        address: address ?? this.address,
        copies: copies ?? this.copies,
        headerText: headerText ?? this.headerText,
        footerText: footerText ?? this.footerText,
        logoPath: logoPath ?? this.logoPath,
        showLogo: showLogo ?? this.showLogo,
        showBarcode: showBarcode ?? this.showBarcode,
        showTaxLines: showTaxLines ?? this.showTaxLines,
        openDrawer: openDrawer ?? this.openDrawer,
        autoPrint: autoPrint ?? this.autoPrint,
        fontScaleBp: fontScaleBp ?? this.fontScaleBp,
        isDefault: isDefault ?? this.isDefault,
        isActive: isActive ?? this.isActive,
      );

  static PrinterProfile blank() => const PrinterProfile(
        name: 'Receipt 80mm',
        driver: PrinterDriver.pdf,
        paper: PaperSize.roll80,
        footerText: 'Thank you',
      );
}

/// How the page reaches the printer.
enum PrinterDriver {
  pdf('pdf', AppText.printDriverPdf),
  system('system', AppText.printDriverSystem),
  escPosUsb('esc_pos_usb', AppText.printDriverUsb),
  escPosNetwork('esc_pos_network', AppText.printDriverNetwork),
  sunmi('sunmi', AppText.printDriverSunmi);

  const PrinterDriver(this.dbValue, this.labelKey);

  final String dbValue;
  final String labelKey;

  static PrinterDriver fromDb(Object? value) => PrinterDriver.values.firstWhere(
        (PrinterDriver d) => d.dbValue == '$value',
        orElse: () => PrinterDriver.pdf,
      );

  /// The thermal transports want a network or device address; the others do
  /// not, and asking for one only invites a wrong answer.
  bool get needsAddress =>
      this == PrinterDriver.escPosNetwork ||
      this == PrinterDriver.escPosUsb ||
      this == PrinterDriver.system;
}

enum PaperSize {
  roll58('roll58', AppText.printPaper58, 58),
  roll80('roll80', AppText.printPaper80, 80),
  a5('a5', AppText.printPaperA5, 148),
  a4('a4', AppText.printPaperA4, 210);

  const PaperSize(this.dbValue, this.labelKey, this.widthMm);

  final String dbValue;
  final String labelKey;
  final int widthMm;

  static PaperSize fromDb(Object? value) => PaperSize.values.firstWhere(
        (PaperSize p) => p.dbValue == '$value',
        orElse: () => PaperSize.roll80,
      );

  bool get isRoll => this == PaperSize.roll58 || this == PaperSize.roll80;
}
