import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/classes/enums.dart';
import '../../core/di/injector.dart';
import 'domain/repositories/parties_repository.dart';
import 'presentation/cubit/parties_cubit.dart';
import 'presentation/pages/parties_page.dart';

/// One screen, two doors. The cubit is told which side of the ledger it is
/// showing when it is built, so the page itself never has to ask.
class PartiesRoutes {
  const PartiesRoutes._();

  static const String customersPath = '/customers';
  static const String suppliersPath = '/suppliers';

  static Widget customers() => _page(PartyKind.customer);

  static Widget suppliers() => _page(PartyKind.supplier);

  static Widget _page(PartyKind kind) => BlocProvider<PartiesCubit>(
        key: ValueKey<PartyKind>(kind),
        create: (_) => PartiesCubit(sl<PartiesRepository>(), kind)..load(),
        child: const PartiesPage(),
      );

  static Map<String, WidgetBuilder> routes() => <String, WidgetBuilder>{
        customersPath: (_) => customers(),
        suppliersPath: (_) => suppliers(),
      };
}
