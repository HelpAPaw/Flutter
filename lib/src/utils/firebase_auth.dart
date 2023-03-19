import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../controllers/user_controller.dart';

class FirebaseAuthentication {
  final _auth = FirebaseAuth.instance;
  final GoogleSignIn googleSignIn = GoogleSignIn();

  Future register(person) async {
    try {
      final newUser = await _auth.createUserWithEmailAndPassword(
          email: person.email, password: person.password);
      User? user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
      return newUser;
    } catch (e) {
      return Future.error(e.toString());
    }
  }

  Future<dynamic> login(email, password) async {
    try {
      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      UserController().setUserPrefs();
      return credential;
    } on FirebaseAuthException catch (e) {
      return Future.error(e);
    }
  }

  Future<User?> signInWithGoogle() async {
    User? user;

    final GoogleSignIn googleSignIn = GoogleSignIn();

    final GoogleSignInAccount? googleSignInAccount =
        await googleSignIn.signIn();

    if (googleSignInAccount != null) {
      final GoogleSignInAuthentication googleSignInAuthentication =
          await googleSignInAccount.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleSignInAuthentication.accessToken,
        idToken: googleSignInAuthentication.idToken,
      );

      try {
        final UserCredential userCredential =
            await _auth.signInWithCredential(credential);

        user = userCredential.user;
      } on FirebaseAuthException catch (e) {
        return Future.error(e);
      }
    }
    return user;
  }
}
