
class AppFailure implements Exception {
  const AppFailure(
    this.message, {
    this.kind = FailureKind.unexpected,
    this.cause,
  });

  const AppFailure.validation(this.message)
      : kind = FailureKind.validation,
        cause = null;

  const AppFailure.notFound(this.message)
      : kind = FailureKind.notFound,
        cause = null;

  const AppFailure.conflict(this.message)
      : kind = FailureKind.conflict,
        cause = null;

  const AppFailure.database(this.message, {this.cause})
      : kind = FailureKind.database;

  const AppFailure.permission(this.message)
      : kind = FailureKind.permission,
        cause = null;

  final String message;
  final FailureKind kind;
  final Object? cause;

  bool get isValidation => kind == FailureKind.validation;

  @override
  String toString() => message;
}

enum FailureKind {
  validation,
  notFound,
  conflict,
  database,
  permission,
  unexpected,
}
