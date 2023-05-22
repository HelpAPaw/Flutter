import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'signal_event.dart';
part 'signal_state.dart';

class SignalBloc extends Bloc<SignalEvent, SignalState> {
  SignalBloc() : super(SignalInitial()) {
    on<SignalEvent>((event, emit) {
      // TODO: implement event handler
    });
  }
}
