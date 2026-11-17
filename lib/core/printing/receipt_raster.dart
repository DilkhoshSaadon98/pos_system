import 'dart:typed_data';

import 'package:printing/printing.dart';

/// The finished receipt, turned into dots.
///
/// Takes the PDF the app already builds — the same bytes the preview shows and
/// the same layout the A4 printer would produce — and renders it to the
/// one-bit bitmap a thermal head actually prints. See `esc_pos.dart` for why a
/// picture rather than text.
class ReceiptRaster {
  const ReceiptRaster._();

  /// Dots across the head. Every 58 mm printer in this trade is 384 and every
  /// 80 mm one is 576; a shop with an unusual head can pass its own.
  static const int dots58 = 384;
  static const int dots80 = 576;

  /// Renders [pdf] and packs it into rows of bits.
  ///
  /// [threshold] is the grey level below which a pixel becomes a black dot.
  /// 160 rather than 128 on purpose: thermal paper renders thin strokes lighter
  /// than a screen does, and Arabic diacritics are thin strokes.
  static Future<RasterBitmap?> monochrome(
    Uint8List pdf, {
    required int dotsWide,
    int threshold = 160,
  }) async {
    // The receipt is one long page, so only the first raster is needed. A
    // multi-page document (an A4 invoice sent to a roll printer by mistake)
    // still prints its first page rather than nothing.
    await for (final PdfRaster page in Printing.raster(pdf, dpi: 203)) {
      return _pack(page, dotsWide: dotsWide, threshold: threshold);
    }
    return null;
  }

  /// Nearest-neighbour scale to the head's width, then one bit per dot.
  ///
  /// Nearest-neighbour rather than a smooth filter because the output is a
  /// single bit: smoothing produces grey that the threshold then throws away,
  /// and on 384 dots it leaves text looking chewed rather than crisp.
  static RasterBitmap _pack(
    PdfRaster page, {
    required int dotsWide,
    required int threshold,
  }) {
    final int srcWidth = page.width;
    final int srcHeight = page.height;
    final int height = srcWidth == 0
        ? 0
        : ((srcHeight * dotsWide) / srcWidth).round();

    final int widthBytes = (dotsWide + 7) ~/ 8;
    final Uint8List out = Uint8List(widthBytes * height);
    final Uint8List src = page.pixels;

    for (int y = 0; y < height; y++) {
      final int srcY = srcHeight == 0 ? 0 : (y * srcHeight) ~/ height;
      final int rowStart = y * widthBytes;

      for (int x = 0; x < dotsWide; x++) {
        final int srcX = (x * srcWidth) ~/ dotsWide;
        final int i = (srcY * srcWidth + srcX) * 4;
        if (i + 3 >= src.length) continue;

        final int a = src[i + 3];
        // A transparent pixel is paper, not ink.
        if (a < 128) continue;

        // Rec. 601 luma, in integers: the eye weighs green most heavily, and a
        // plain average turns red totals into grey mush.
        final int luma = (src[i] * 299 + src[i + 1] * 587 + src[i + 2] * 114) ~/ 1000;
        if (luma < threshold) {
          out[rowStart + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }

    return RasterBitmap(bits: out, widthBytes: widthBytes, height: height);
  }

  /// Dots across for a paper size name as the profile stores it.
  static int dotsFor(String paper) => paper == 'roll58' ? dots58 : dots80;
}

/// A packed one-bit image, ready for `GS v 0`.
class RasterBitmap {
  const RasterBitmap({
    required this.bits,
    required this.widthBytes,
    required this.height,
  });

  final Uint8List bits;
  final int widthBytes;
  final int height;

  bool get isEmpty => height == 0 || bits.isEmpty;
}
