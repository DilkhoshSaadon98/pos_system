import 'dart:typed_data';

/// The bytes a thermal printer understands.
///
/// ## Why the receipt is sent as a picture
///
/// ESC/POS printers hold a handful of single-byte code pages. None of them can
/// write Arabic the way Arabic is written — letters change shape depending on
/// their neighbours, and the text runs right to left. Printers that claim an
/// Arabic code page produce disconnected letters in the wrong order, which is
/// how most tills in this trade end up printing receipts nobody can read.
///
/// So nothing here prints text. The receipt is laid out once, by the same PDF
/// code that draws the on-screen preview, rendered to a bitmap, and sent as a
/// raster image. Arabic, Kurdish and English all come out exactly as they were
/// laid out, the preview and the paper cannot drift apart, and the printer
/// only has to do the one thing every ESC/POS printer does identically.
///
/// The cost is speed — a raster receipt is a few kilobytes rather than a few
/// hundred bytes — which on a 58 or 80 mm printer is a fraction of a second.
class EscPos {
  const EscPos._();

  /// Wake up and forget any earlier settings.
  static const List<int> initialise = <int>[0x1B, 0x40];

  /// Feed [lines] blank lines — paper past the tear bar before the cut.
  static List<int> feed(int lines) => <int>[0x1B, 0x64, lines.clamp(0, 255)];

  /// Cut the paper. A partial cut leaves a small tab so the receipt does not
  /// fall on the floor.
  static List<int> cut({bool partial = true}) =>
      <int>[0x1D, 0x56, partial ? 0x42 : 0x41, 0x00];

  /// Kick the cash drawer.
  ///
  /// The drawer is wired to one of two pins on the printer's RJ11 socket, and
  /// which one is not something a shop can be expected to know — so [pin] is
  /// configurable and [both] fires them in turn, which opens the drawer
  /// whichever way it was wired and does nothing at all if none is connected.
  static List<int> openDrawer({int pin = 0, int onMs = 100, int offMs = 200}) {
    final int m = pin == 1 ? 0x01 : 0x00;
    // The printer counts in 2 ms ticks, and refuses anything above 255.
    final int on = (onMs ~/ 2).clamp(1, 255);
    final int off = (offMs ~/ 2).clamp(1, 255);
    return <int>[0x1B, 0x70, m, on, off];
  }

  static List<int> openDrawerBoth() =>
      <int>[...openDrawer(pin: 0), ...openDrawer(pin: 1)];

  /// A monochrome bitmap as a GS v 0 raster.
  ///
  /// [mono] is one bit per dot, packed most-significant-bit first, in rows of
  /// [widthBytes] bytes. A set bit is a black dot — the opposite of how a
  /// screen thinks, which is why the conversion happens in one place.
  ///
  /// Tall images are sent in bands: some printers refuse a single image taller
  /// than a few hundred dots, and a band that fails takes a strip of the
  /// receipt with it rather than the whole thing.
  static List<int> raster(
    Uint8List mono, {
    required int widthBytes,
    required int height,
    int bandHeight = 255,
  }) {
    final List<int> out = <int>[];
    int row = 0;

    while (row < height) {
      final int rows = (height - row) < bandHeight ? (height - row) : bandHeight;
      final int start = row * widthBytes;
      final int end = start + rows * widthBytes;

      out.addAll(<int>[
        0x1D, 0x76, 0x30, 0x00, // GS v 0, normal size
        widthBytes & 0xFF, (widthBytes >> 8) & 0xFF,
        rows & 0xFF, (rows >> 8) & 0xFF,
      ]);
      out.addAll(mono.sublist(start, end));
      row += rows;
    }

    return out;
  }

  /// Everything a receipt needs, in the order a printer expects it.
  static List<int> receipt(
    Uint8List mono, {
    required int widthBytes,
    required int height,
    bool kickDrawer = false,
    bool cutPaper = true,
    int copies = 1,
  }) {
    final List<int> out = <int>[];
    for (int i = 0; i < (copies < 1 ? 1 : copies); i++) {
      out
        ..addAll(initialise)
        ..addAll(raster(mono, widthBytes: widthBytes, height: height))
        ..addAll(feed(3));
      if (cutPaper) out.addAll(cut());
    }
    // The drawer opens once per sale, not once per copy.
    if (kickDrawer) out.addAll(openDrawerBoth());
    return out;
  }
}
