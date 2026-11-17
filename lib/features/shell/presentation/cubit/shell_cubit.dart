import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/classes/enums.dart';

class NavEntry {
  const NavEntry({
    required this.id,
    required this.labelKey,
    required this.icon,
    required this.activeIcon,
    required this.builder,
    required this.groupKey,
    this.roles = UserRole.values,
  });

  final String id;
  final String labelKey;
  final IconData icon;
  final IconData activeIcon;


  final Widget Function() builder;

  final String groupKey;


  final List<UserRole> roles;

  bool allows(UserRole role) => roles.contains(role);
}

class ShellState {
  const ShellState({
    this.index = 0,
    this.railExpanded = true,
  });

  final int index;
  final bool railExpanded;

  ShellState copyWith({int? index, bool? railExpanded}) => ShellState(
        index: index ?? this.index,
        railExpanded: railExpanded ?? this.railExpanded,
      );
}


class ShellCubit extends Cubit<ShellState> {
  ShellCubit() : super(const ShellState());

  void go(int index) => emit(state.copyWith(index: index));


  void goTo(String id, List<NavEntry> entries) {
    final int index = entries.indexWhere((NavEntry e) => e.id == id);
    if (index >= 0) emit(state.copyWith(index: index));
  }

  void toggleRail() => emit(state.copyWith(railExpanded: !state.railExpanded));
}
