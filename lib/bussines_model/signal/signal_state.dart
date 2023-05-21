part of 'signal_bloc.dart';

abstract class SignalState extends Equatable {
  const SignalState();
  
  @override
  List<Object> get props => [];
}

class SignalInitial extends SignalState {}
