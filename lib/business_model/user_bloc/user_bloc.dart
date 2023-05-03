import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../data/models/users.dart';

part 'user_event.dart';
part 'user_state.dart';

class UserBloc extends Bloc<UserEvent, UserState> {
  UserBloc() : super(UserNotLoggedState()) {

    on<UserEvent>((event, emit) {

    });

  }
}
