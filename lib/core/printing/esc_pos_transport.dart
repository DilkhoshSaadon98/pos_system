import 'dart:io';

import '../error/exceptions.dart';

/// How the bytes get from here to the printer.
///
/// Two ways, because thermal printers in this trade are wired one of two ways
/// and a shop should not have to care which:
///
/// * **Over the network** — the printer has an IP address and listens on port
///   9100. This is a plain socket and needs nothing installed.
/// * **Through Windows** — the printer is on a cable. Windows will pass raw
///   bytes straight through to a *shared* printer if you write them to its
///   share path, so a printer shared as `POS80` is reachable at
///   `\\localhost\POS80`. That is the whole trick: no driver work, no native
///   plugin, and the drawer command reaches the printer intact.
///
/// A printer that is not shared can still be used — it just prints through the
/// Windows driver as a normal document, which is what the `system` driver does
/// and which loses only the drawer kick.
abstract class EscPosTransport {
  const EscPosTransport();

  /// Sends [bytes], or throws an [AppFailure] a cashier can act on.
  Future<void> send(List<int> bytes);

  /// A short, human description for the settings screen.
  String get describe;
}

/// A printer with an IP address, on the usual raw-printing port.
class NetworkEscPos extends EscPosTransport {
  const NetworkEscPos({
    required this.host,
    this.port = 9100,
    this.timeout = const Duration(seconds: 6),
  });

  /// Parses `192.168.1.50`, `192.168.1.50:9100`.
  factory NetworkEscPos.parse(String address) {
    final List<String> parts = address.trim().split(':');
    return NetworkEscPos(
      host: parts.first.trim(),
      port: parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 9100) : 9100,
    );
  }

  final String host;
  final int port;
  final Duration timeout;

  @override
  String get describe => '$host:$port';

  @override
  Future<void> send(List<int> bytes) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(bytes);
      await socket.flush();
    } on SocketException catch (e) {
      throw AppFailure.database(
        'The printer at $host did not answer. Check that it is switched on '
        'and on the same network. (${e.osError?.message ?? e.message})',
      );
    } finally {
      await socket?.close();
    }
  }
}

/// A printer on a cable, reached through its Windows share.
class WindowsShareEscPos extends EscPosTransport {
  const WindowsShareEscPos(this.path);

  /// `POS80` and `\\localhost\POS80` both mean the same thing to a shopkeeper,
  /// so both are accepted.
  factory WindowsShareEscPos.parse(String address) {
    final String a = address.trim();
    if (a.startsWith(r'\\')) return WindowsShareEscPos(a);
    return WindowsShareEscPos(r'\\localhost\' + a);
  }

  final String path;

  @override
  String get describe => path;

  @override
  Future<void> send(List<int> bytes) async {
    if (!Platform.isWindows) {
      throw const AppFailure.validation(
        'A shared printer path only works on Windows. Use the network address '
        'instead, or print through the system driver.',
      );
    }
    try {
      final RandomAccessFile file =
          await File(path).open(mode: FileMode.writeOnly);
      try {
        await file.writeFrom(bytes);
        await file.flush();
      } finally {
        await file.close();
      }
    } on FileSystemException catch (e) {
      throw AppFailure.database(
        'Windows would not send anything to "$path". The printer has to be '
        'shared under that exact name — right-click it in Printers, then '
        'Printer properties, Sharing. (${e.osError?.message ?? e.message})',
      );
    }
  }
}

/// Picks the transport an address describes.
///
/// An address with dots and no backslashes is a network printer; anything else
/// is a Windows share. Guessing rather than asking is deliberate: the shop
/// types what it knows and the software works out the rest.
EscPosTransport? transportFor(String? address) {
  final String a = (address ?? '').trim();
  if (a.isEmpty) return null;
  if (a.startsWith(r'\\')) return WindowsShareEscPos.parse(a);

  final String host = a.split(':').first;
  final bool looksLikeIp =
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains('.');
  return looksLikeIp ? NetworkEscPos.parse(a) : WindowsShareEscPos.parse(a);
}
