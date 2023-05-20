import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:help_a_paw/utility/app_router.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'firebase_options.dart';

bool shouldUseFirebaseEmulator = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: await getApplicationDocumentsDirectory(),
  );

  if (shouldUseFirebaseEmulator) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }
  runApp(MyApp(
    appRouter: AppRouter(),
  ));
}
