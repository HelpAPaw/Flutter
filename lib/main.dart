import 'package:easy_localization/easy_localization.dart';
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
  await EasyLocalization.ensureInitialized();

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: await getApplicationDocumentsDirectory(),
  );

  if (shouldUseFirebaseEmulator) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }
  runApp(
    EasyLocalization(
        supportedLocales: const [
          Locale('en', ''),
          Locale('bg', 'BG'),
        ],
        path: 'assets/localization',
        fallbackLocale: const Locale('en', ''),
        child: MyApp(
          appRouter: AppRouter(),
        )),
  );
}
