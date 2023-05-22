part of 'user_bloc.dart';

abstract class UserState extends Equatable {
  const UserState();

  @override
  List<Object> get props => [];
}

class UserInitial extends UserState {}

class UserLoading extends UserState {}

class UserLogged extends UserState {
  const UserLogged({required this.userDetails});
  final UserDetails userDetails;

  @override
  List<Object> get props => [userDetails];
}

class UserNotLogged extends UserState {}

