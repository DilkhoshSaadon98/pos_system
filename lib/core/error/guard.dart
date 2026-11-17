import 'package:dartz/dartz.dart';

import 'failure_mapper.dart';
import 'failures.dart';

//? A unit value, for when a function returns nothing but we want to use `Result`.
typedef Result<T> = Either<Failure, T>;

//? Runs [action] and turns anything it throws into a [Failure].
Future<Result<T>> guard<T>(Future<T> Function() action) async {
  try {
    return Right<Failure, T>(await action());
  } catch (error) {
    return Left<Failure, T>(Failures.from(error));
  }
}

//? [guard] for an action with no return value.
Future<Result<Unit>> guardVoid(Future<void> Function() action) =>
    guard<Unit>(() async {
      await action();
      return unit;
    });

extension ResultX<T> on Result<T> {
  T? get valueOrNull => fold((Failure _) => null, (T value) => value);

  Failure? get failureOrNull => fold((Failure f) => f, (T _) => null);

  bool get failed => isLeft();
  bool get succeeded => isRight();
  T valueOr(T fallback) => fold((Failure _) => fallback, (T value) => value);
}

//? The first thing that went wrong in a batch of parallel loads.
Failure? firstFailure(List<Result<Object?>> results) {
  for (final Result<Object?> r in results) {
    final Failure? f = r.failureOrNull;
    if (f != null) return f;
  }
  return null;
}
