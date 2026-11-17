import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import 'domain/repositories/accounting_repository.dart';
import 'presentation/cubit/journal_cubit.dart';
import 'presentation/cubit/reports_cubit.dart';
import 'presentation/pages/journal_page.dart';
import 'presentation/pages/reports_page.dart';

class AccountingRoutes {
  const AccountingRoutes._();

  static const String journalPath = '/journal';
  static const String reportsPath = '/reports';

  static Widget journal() => BlocProvider<JournalCubit>(
        create: (_) => JournalCubit(sl<AccountingRepository>())..load(),
        child: const JournalPage(),
      );

  static Widget reports() => BlocProvider<ReportsCubit>(
        create: (_) => ReportsCubit(sl<AccountingRepository>())..load(),
        child: const ReportsPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        journalPath: (_) => journal(),
        reportsPath: (_) => reports(),
      };
}
