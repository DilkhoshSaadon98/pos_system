import 'dart:async' as async;

import 'exceptions.dart';
import 'failures.dart';


class Failures {
  const Failures._();

  static Failure from(Object error) {
    if (error is Failure) return error;

    if (error is AppFailure) {
      return switch (error.kind) {
        FailureKind.validation => ValidationFailure(detail: error.message),
        FailureKind.notFound => NotFoundFailure(detail: error.message),
        FailureKind.conflict => ConflictFailure(detail: error.message),
        FailureKind.database => DatabaseFailure(detail: error.message),
        FailureKind.permission => PermissionFailure(detail: error.message),
        FailureKind.unexpected => UnexpectedFailure(detail: error.message),
      };
    }

    if (error is async.TimeoutException) {
      return const DatabaseFailure(
        detail: 'The database did not answer in time. Try again.',
      );
    }

    final String text = error.toString();
    final String lower = text.toLowerCase();

    if (lower.contains('unique constraint failed')) {
      return ConflictFailure(detail: _uniqueMessage(text));
    }
    if (lower.contains('foreign key constraint failed')) {
      return const ConflictFailure(
        detail: 'Something else still refers to this record, so it cannot be '
            'removed. Hide it instead.',
      );
    }
    if (lower.contains('check constraint failed')) {
      return const ValidationFailure(
        detail: 'One of the values is outside what this field allows.',
      );
    }
    if (lower.contains('database is locked') || lower.contains('busy')) {
      return const DatabaseFailure(
        detail: 'The database is busy. Try again in a moment.',
      );
    }
    if (lower.contains('sqlite') || lower.contains('databaseexception')) {
      return DatabaseFailure(detail: text);
    }

    return UnexpectedFailure(detail: text);
  }


  static String _uniqueMessage(String raw) {
    final Match? m =
        RegExp(r'failed:\s*([A-Za-z_]+)\.([A-Za-z_]+)').firstMatch(raw);
    if (m == null) return 'That value is already used by another record.';

    return switch ('${m.group(1)}.${m.group(2)}') {
      'item_units.barcode' => 'That barcode already belongs to another item.',
      'items.sku' => 'That item code is already in use.',
      'units.name' => 'A unit with that name already exists.',
      'users.username' => 'That username is taken.',
      'accounts.code' => 'An account already uses that code.',
      'accounts.system_key' =>
        'Another account is already the one the system uses for that role.',
      'parties.code' => 'That customer code is already in use.',
      _ => 'That value is already used by another record.',
    };
  }
}
