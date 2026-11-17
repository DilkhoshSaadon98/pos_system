import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/error/guard.dart';
import '../../domain/entities/printer_profile.dart';
import '../../domain/receipt_data.dart';
import '../../domain/repositories/printing_repository.dart';
import '../datasources/printing_local_datasource.dart';

class PrintingRepositoryImpl implements PrintingRepository {
  const PrintingRepositoryImpl(this._local, this._isRtl);

  final PrintingLocalDataSource _local;

  /// Direction is a presentation concern the renderer needs to know about, so
  /// it is injected rather than read from a global — which is what let the old
  /// service reach into `Get.locale` from inside the data layer.
  final bool Function() _isRtl;

  @override
  Future<Result<List<PrinterProfile>>> profiles() => guard(_local.profiles);

  @override
  Future<Result<PrinterProfile?>> defaultProfile() =>
      guard(() => _local.defaultProfile(refresh: true));

  @override
  Future<Result<int>> saveProfile(PrinterProfile profile) =>
      guard(() => _local.saveProfile(profile));

  @override
  Future<Result<Unit>> deleteProfile(int id) =>
      guardVoid(() => _local.deleteProfile(id));

  @override
  Future<Result<ReceiptData>> saleReceipt(int invoiceId) =>
      guard(() => _local.saleReceipt(invoiceId));

  @override
  Future<Result<Uint8List>> render(
    ReceiptData data, {
    PrinterProfile? profile,
    bool rtl = false,
  }) =>
      guard(() => _local.render(data, profile: profile, rtl: rtl || _isRtl()));

  @override
  Future<Result<Unit>> printSale(int invoiceId) =>
      guardVoid(() => _local.printSale(invoiceId, rtl: _isRtl()));

  @override
  Future<Result<Uint8List>> testPage(
    PrinterProfile profile, {
    bool rtl = false,
  }) =>
      guard(() => _local.testPage(profile, rtl: rtl || _isRtl()));

  @override
  Future<Result<Unit>> present(Uint8List bytes, {String name = 'document'}) =>
      guardVoid(() => _local.present(bytes, name: name));

  @override
  Future<Result<Unit>> openDrawer({PrinterProfile? profile}) =>
      guardVoid(() => _local.kickDrawer(profile: profile));
}
