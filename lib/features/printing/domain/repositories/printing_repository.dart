import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/error/guard.dart';
import '../entities/printer_profile.dart';
import '../receipt_data.dart';

/// Everything that ends up on paper.
///
/// The old project spread printing across an 1 800-line controller, a Sunmi
/// controller and a handful of dialogs, each with its own copy of the layout.
/// Here there is one path: gather the document, render it once, hand it to
/// whichever printer the profile names.
abstract class PrintingRepository {
  Future<Result<List<PrinterProfile>>> profiles();

  Future<Result<PrinterProfile?>> defaultProfile();

  Future<Result<int>> saveProfile(PrinterProfile profile);

  Future<Result<Unit>> deleteProfile(int id);

  /// Reads a saved invoice back and turns it into the neutral description the
  /// renderers understand — the same object the preview and the paper use.
  Future<Result<ReceiptData>> saleReceipt(int invoiceId);

  /// Renders to PDF bytes without sending anything anywhere. This is what the
  /// preview shows, so what is on screen is the page that will come out.
  Future<Result<Uint8List>> render(
    ReceiptData data, {
    PrinterProfile? profile,
    bool rtl = false,
  });

  /// Sends a saved sale to the default printer. Never throws at the till: a
  /// receipt is a convenience and the sale is the record.
  Future<Result<Unit>> printSale(int invoiceId);

  Future<Result<Uint8List>> testPage(PrinterProfile profile, {bool rtl = false});

  /// Opens the platform print dialog for bytes already rendered.
  Future<Result<Unit>> present(Uint8List bytes, {String name = 'document'});

  /// Opens the cash drawer on its own, with nothing to print — the button a
  /// cashier needs when a customer wants change for a note.
  Future<Result<Unit>> openDrawer({PrinterProfile? profile});
}
