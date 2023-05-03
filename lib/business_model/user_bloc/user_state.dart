part of 'user_bloc.dart';

abstract class UserState extends Equatable {
  const UserState();
}

class UserLoadingState extends UserState {


  @override
  List<Object> get props => [];
}
class UserLoggedState extends UserState {

  UserLoggedState({required this.userDetails});
  UserDetails userDetails;
  @override
  List<Object> get props => [userDetails];
}
class UserNotLoggedState extends UserState {


  @override
  List<Object> get props => [];
}
