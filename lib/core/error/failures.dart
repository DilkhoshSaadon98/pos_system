import 'package:equatable/equatable.dart';
//? Every error the app raises **on purpose**.
sealed class Failure extends Equatable {
  const Failure({required this.detail});

  //? A sentence that can be shown to a cashier as-is.
  final String detail;

  @override
  List<Object?> get props => <Object?>[detail, runtimeType];

  @override
  String toString() => '$runtimeType: $detail';
}

//? The user typed something the system cannot accept.
class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.detail,
    this.errors = const <String, String>{},
  });

  //? Field name → message, when the problem can be pinned to a specific input.
  final Map<String, String> errors;

  @override
  List<Object?> get props => <Object?>[detail, errors];
}

//? The row is gone — deleted on another till, or never existed.
class NotFoundFailure extends Failure {
  const NotFoundFailure({required super.detail});
}

//? The write would break something that already exists: a duplicate barcode, a
//? category that still has items in it.
class ConflictFailure extends Failure {
  const ConflictFailure({required super.detail});
}

//? SQLite refused the statement — a constraint, a locked file, a corrupt page.
class DatabaseFailure extends Failure {
  const DatabaseFailure({required super.detail});
}

//? The signed-in user's role does not allow this.
class PermissionFailure extends Failure {
  const PermissionFailure({required super.detail});
}

//? Anything we did not anticipate. Always carries the original text, because a
//? message a developer can search for beats a polite one that says nothing.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure({required super.detail});
}
