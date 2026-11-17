/// Integer arithmetic helpers shared by every calculation in the app.
///
/// The rule the whole system rests on: **no money or quantity value ever
/// touches a double**. Multiplying and dividing integers loses nothing, and
/// rounding happens exactly once, at a place we choose, with a rule we wrote
/// down — half away from zero, the way a person rounds on paper.
library;

/// `(a * b) / c` rounded half away from zero.
///
/// Used for every price × quantity, percentage and unit conversion. Returns 0
/// when [c] is 0 rather than throwing, because a zero divisor here always means
/// "there is nothing to spread" and the callers treat it that way.
int mulDivRound(int a, int b, int c) {
  if (c == 0) return 0;
  final int product = a * b;
  final int half = c.abs() ~/ 2;
  if ((product < 0) != (c < 0)) {
    return (product - half) ~/ c;
  }
  return (product + half) ~/ c;
}

/// `a / b` rounded half away from zero.
int divRound(int a, int b) => mulDivRound(a, 1, b);

/// `value` rounded to the nearest multiple of [step], half away from zero.
/// A [step] of 0 or 1 returns the value untouched.
int roundToStep(int value, int step) {
  if (step <= 1) return value;
  return divRound(value, step) * step;
}

/// Clamps [value] into `[low, high]`.
int clampInt(int value, int low, int high) =>
    value < low ? low : (value > high ? high : value);

/// Spreads [amount] across [weights] so that the parts add up to exactly
/// [amount] — no cent appears or disappears.
///
/// Largest-remainder method: give everyone their floor share, then hand the
/// leftover units one at a time to the lines with the biggest fractional part
/// (ties go to the earlier line). This is what makes an invoice-level discount
/// or a freight charge split correctly across lines instead of leaving a
/// one-cent hole in the total.
///
/// * A negative [amount] (a return, a credit) is spread with the same shape.
/// * Zero total weight spreads the amount evenly across all entries, so a
///   discount on a cart of free items still lands somewhere.
List<int> allocate(int amount, List<int> weights) {
  final int n = weights.length;
  if (n == 0) return const <int>[];
  if (amount == 0) return List<int>.filled(n, 0);

  final int sign = amount < 0 ? -1 : 1;
  final int total = amount.abs();

  List<int> w = weights.map((int e) => e.abs()).toList(growable: false);
  int weightSum = w.fold(0, (int a, int b) => a + b);
  if (weightSum == 0) {
    w = List<int>.filled(n, 1);
    weightSum = n;
  }

  final List<int> parts = List<int>.filled(n, 0);
  final List<int> remainders = List<int>.filled(n, 0);
  int distributed = 0;

  for (int i = 0; i < n; i++) {
    final int exact = total * w[i];
    final int share = exact ~/ weightSum;
    parts[i] = share;
    remainders[i] = exact - share * weightSum;
    distributed += share;
  }

  int leftover = total - distributed;
  final List<int> order = List<int>.generate(n, (int i) => i)
    ..sort((int a, int b) {
      final int cmp = remainders[b].compareTo(remainders[a]);
      return cmp != 0 ? cmp : a.compareTo(b);
    });

  for (int i = 0; leftover > 0; i = (i + 1) % n) {
    parts[order[i]] += 1;
    leftover -= 1;
  }

  return parts.map((int p) => p * sign).toList(growable: false);
}
