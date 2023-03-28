import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:help_a_paw/src/models/users.dart';
import '../controllers/user_controller.dart';

class FirebaseAuthentication {
  final _auth = FirebaseAuth.instance;
  final GoogleSignIn googleSignIn = GoogleSignIn();
  CollectionReference users = FirebaseFirestore.instance.collection('users');

  /* User Register Event**/
  Future register(person) async {
    try {
      final newUser = await _auth.createUserWithEmailAndPassword(
          email: person.email, password: person.password);
      User? user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
      Map<String, dynamic> userdetails = {
        'uid': user!.uid,
        'name': person.name,
        'email': user.email
      };
      UserDetails details = UserDetails.fromJson(userdetails);
      await addUser(details);
      return newUser;
    } catch (e) {
      return Future.error(e.toString());
    }
  }

  /* User Login Event **/
  Future<dynamic> login(email, password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      UserController().setUserPrefs(credential.user);
      return credential;
    } on FirebaseAuthException catch (e) {
      return Future.error(e);
    }
  }

  /* User Google Login/Register Event **/
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
        Map<String, dynamic> userdetails = {
          'uid': user!.uid,
          'name': user.displayName,
          'email': user.email
        };
        UserDetails details = UserDetails.fromJson(userdetails);
        await addUser(details);
      } on FirebaseAuthException catch (e) {
        return Future.error(e);
      }
    }
    return user;
  }

  /* Store User Details in Firestore **/
  Future<void> addUser(UserDetails user) {
    return users
        .doc(user.uid)
        .set({'name': user.name, 'email': user.email, 'uid': user.uid})
        .then((value) => "User Added")
        .catchError((error) => error);
  }

  /* User Logout Event **/
  Future<void> logOut() async {
    return await FirebaseAuth.instance.signOut();
  }
}
