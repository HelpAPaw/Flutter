import 'package:firebase_auth/firebase_auth.dart';
import '../controllers/user_controller.dart';

class FirebaseAuthentication {
  final _auth = FirebaseAuth.instance;

  Future register(person) async {
    try {
      final newUser = await _auth.createUserWithEmailAndPassword(
          email: person.email, password: person.password);
      User? user = _auth.currentUser;
      if (user!= null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
      return newUser;
    } catch (e) {
      return Future.error(e.toString());
    }
  }

  Future<dynamic> login(email, password) async {
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password
      );
      UserController().setUserPrefs();
      return credential;
    } on FirebaseAuthException catch (e) {
      return Future.error(e);
    }
  }
}
