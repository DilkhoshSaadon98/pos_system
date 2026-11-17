/// One place that decides what a stored date looks like.
///
/// Everything in the database is an ISO-8601 string in **local** time:
/// `2026-08-24T14:31:07`. Sorting a text column that way is the same as sorting
/// by time, and `substr(col, 1, 10)` is the day — which is why the reporting
/// views can group by day without a single date function.
class Time {
  const Time._();

  /// `2026-08-24T14:31:07` — a full timestamp for a row that is being written.
  static String stamp([DateTime? at]) {
    final DateTime d = at ?? DateTime.now();
    return '${_date(d)}T${_time(d)}';
  }

  /// `2026-08-24` — a calendar day, for entry dates and report filters.
  static String day([DateTime? at]) => _date(at ?? DateTime.now());

  static String dayOf(DateTime at) => _date(at);

  /// The first instant of [at]'s day, as a comparable stamp.
  static String startOfDay(DateTime at) => '${_date(at)}T00:00:00';

  /// The last instant of [at]'s day, as a comparable stamp.
  static String endOfDay(DateTime at) => '${_date(at)}T23:59:59';

  static String startOfMonth(DateTime at) =>
      '${_date(DateTime(at.year, at.month))}T00:00:00';

  static DateTime? parse(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
}
