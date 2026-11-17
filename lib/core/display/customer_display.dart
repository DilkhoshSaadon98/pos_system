import 'dart:convert';
import 'dart:io';

//? One line as the customer sees it.
class CustomerLine {
  const CustomerLine({
    required this.name,
    required this.qty,
    required this.price,
    required this.total,
  });

  final String name;
  final String qty;
  final String price;
  final String total;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'qty': qty,
        'price': price,
        'total': total,
      };
}

//? The whole screen, as one message.
class CustomerView {
  const CustomerView({
    this.lines = const <CustomerLine>[],
    this.subtotal = '',
    this.discount = '',
    this.total = '',
    this.paid = '',
    this.change = '',
    this.message = '',
  });

  factory CustomerView.thankYou(String message, {String change = ''}) =>
      CustomerView(message: message, change: change);

  final List<CustomerLine> lines;
  final String subtotal;
  final String discount;
  final String total;
  final String paid;
  final String change;

  /// Shown instead of the basket — "Thank you", or the shop's own greeting
  /// while the till is idle.
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
        'lines': lines.map((CustomerLine l) => l.toJson()).toList(),
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'paid': paid,
        'change': change,
        'message': message,
      };
}


class CustomerDisplay {
  CustomerDisplay._();

  static final CustomerDisplay instance = CustomerDisplay._();

  static const int defaultPort = 8088;

  HttpServer? _server;
  final List<HttpResponse> _watchers = <HttpResponse>[];

  CustomerView _view = const CustomerView();
  String _shopName = '';
  Map<String, String> _labels = const <String, String>{};

  bool get isRunning => _server != null;

  /// `http://<lan address>:<port>`, or null when the display is off.
  String? get url {
    final HttpServer? server = _server;
    if (server == null) return null;
    return 'http://localhost:${server.port}';
  }

  /// The shop's name and the five words the page shows. Set from the till,
  /// which is the only place that knows the chosen language.
  void configure({
    required String shopName,
    required Map<String, String> labels,
  }) {
    _shopName = shopName;
    _labels = labels;
    _push();
  }

  /// Starts listening. Returns the address, or null if the port was taken —
  /// a customer display that cannot start must never stop a till from opening.
  Future<String?> start({int port = defaultPort, bool lan = false}) async {
    if (_server != null) return url;
    try {
      _server = await HttpServer.bind(
        lan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
    } on Object {
      _server = null;
      return null;
    }

    _server!.listen(_handle, onError: (Object _) {});
    return url;
  }

  Future<void> stop() async {
    for (final HttpResponse watcher in List<HttpResponse>.of(_watchers)) {
      try {
        await watcher.close();
      } on Object {
        // The browser had already gone.
      }
    }
    _watchers.clear();
    await _server?.close(force: true);
    _server = null;
  }

  /// What the customer should be looking at now.
  void show(CustomerView view) {
    _view = view;
    _push();
  }

  void _handle(HttpRequest request) {
    switch (request.uri.path) {
      case '/events':
        _subscribe(request);
      case '/state':
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_payload()))
          ..close();
      default:
        request.response
          ..headers.contentType = ContentType.html
          ..write(_page)
          ..close();
    }
  }

  void _subscribe(HttpRequest request) {
    final HttpResponse response = request.response;
    response.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set('Cache-Control', 'no-cache')
      ..set('Connection', 'keep-alive');
    response.bufferOutput = false;

    _watchers.add(response);
    _write(response);

    // A browser that is closed, refreshed or put to sleep drops out here.
    response.done.then<void>(
      (_) => _watchers.remove(response),
      onError: (Object _) => _watchers.remove(response),
    );
  }

  void _push() {
    for (final HttpResponse watcher in List<HttpResponse>.of(_watchers)) {
      _write(watcher);
    }
  }

  void _write(HttpResponse response) {
    try {
      response.write('data: ${jsonEncode(_payload())}\n\n');
    } on Object {
      _watchers.remove(response);
    }
  }

  Map<String, Object?> _payload() => <String, Object?>{
        'shop': _shopName,
        'labels': _labels,
        ..._view.toJson(),
      };

  static const String _page = r'''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Customer display</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; height: 100vh; overflow: hidden;
    background: #0d1117; color: #e8edf4;
    font-family: "Segoe UI", Tahoma, system-ui, sans-serif;
    display: flex; flex-direction: column;
  }
  header {
    padding: 18px 28px; font-size: 26px; font-weight: 600;
    border-bottom: 1px solid #1e2733; color: #9db4d0;
  }
  main { flex: 1; overflow-y: auto; padding: 10px 28px; }
  table { width: 100%; border-collapse: collapse; font-size: 26px; }
  td { padding: 10px 4px; border-bottom: 1px solid #161d27; }
  td.q { color: #9db4d0; width: 6em; }
  td.p { color: #9db4d0; width: 8em; text-align: end; }
  td.t { width: 9em; text-align: end; font-variant-numeric: tabular-nums; }
  tr:last-child td { border-bottom: none; }
  footer { border-top: 1px solid #1e2733; padding: 16px 28px 24px; }
  .row { display: flex; justify-content: space-between; font-size: 24px;
         color: #9db4d0; padding: 4px 0; }
  .total { font-size: 54px; font-weight: 700; color: #fff;
           font-variant-numeric: tabular-nums; }
  .change { color: #4ade80; }
  .idle { flex: 1; display: flex; align-items: center; justify-content: center;
          font-size: 46px; color: #6b8199; text-align: center; padding: 40px; }
  .flash { animation: pop .18s ease-out; }
  @keyframes pop { from { background: #1b2836; } to { background: transparent; } }
</style>
</head>
<body>
<header id="shop"></header>
<main id="main"></main>
<footer id="foot" hidden></footer>
<script>
const $ = (id) => document.getElementById(id);
let lastCount = -1;

function render(s) {
  document.documentElement.lang = s.labels && s.labels.rtl === '1' ? 'ar' : 'en';
  document.body.dir = s.labels && s.labels.rtl === '1' ? 'rtl' : 'ltr';
  $('shop').textContent = s.shop || '';

  const L = s.labels || {};
  if (!s.lines || s.lines.length === 0) {
    $('main').innerHTML =
      '<div class="idle">' + (s.message || L.welcome || '') + '</div>';
    $('foot').hidden = !s.change;
    if (s.change) {
      $('foot').innerHTML =
        '<div class="row"><span>' + (L.change || '') +
        '</span><span class="total change">' + s.change + '</span></div>';
    }
    lastCount = 0;
    return;
  }

  const rows = s.lines.map((l) =>
    '<tr><td>' + esc(l.name) + '</td><td class="q">' + esc(l.qty) +
    '</td><td class="p">' + esc(l.price) + '</td><td class="t">' +
    esc(l.total) + '</td></tr>').join('');
  $('main').innerHTML = '<table>' + rows + '</table>';

  // The newest line is at the bottom; keep it in view on a long basket.
  $('main').scrollTop = $('main').scrollHeight;

  let foot = '';
  if (s.discount) {
    foot += '<div class="row"><span>' + (L.discount || '') + '</span><span>' +
            s.discount + '</span></div>';
  }
  foot += '<div class="row"><span>' + (L.total || '') +
          '</span><span class="total">' + (s.total || '') + '</span></div>';
  if (s.paid) {
    foot += '<div class="row"><span>' + (L.paid || '') + '</span><span>' +
            s.paid + '</span></div>';
  }
  if (s.change) {
    foot += '<div class="row"><span>' + (L.change || '') +
            '</span><span class="change">' + s.change + '</span></div>';
  }
  $('foot').innerHTML = foot;
  $('foot').hidden = false;

  if (s.lines.length !== lastCount) {
    const t = $('main').querySelector('tr:last-child');
    if (t) { t.classList.add('flash'); }
    lastCount = s.lines.length;
  }
}

function esc(v) {
  return String(v == null ? '' : v)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function connect() {
  const source = new EventSource('/events');
  source.onmessage = (e) => { try { render(JSON.parse(e.data)); } catch (_) {} };
  // A till that restarts must not leave a blank screen on the counter.
  source.onerror = () => { source.close(); setTimeout(connect, 1500); };
}
fetch('/state').then((r) => r.json()).then(render).catch(() => {});
connect();
</script>
</body>
</html>
''';
}
