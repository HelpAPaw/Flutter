import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

// User Management Configuration
class UserConfig {
  final String contactNumber;
  final String credential;
  final String emailAddress;
  final String name;
  final String newPassword;
  final String password;
  final String profilePhoto;
  final String provider;
  final String uid;

  const UserConfig({
    required this.contactNumber,
    required this.credential,
    required this.emailAddress,
    required this.name,
    required this.newPassword,
    required this.password,
    required this.profilePhoto,
    required this.provider,
    required this.uid,
  });

Future<UserConfig> manageUsers() async {
  await FirebaseAuth.instance.setLanguageCode("en");
  await FirebaseAuth.instance.sendPasswordResetEmail(email: emailAddress);
  await FirebaseAuth.instance.signOut();
  final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
  final user = userCredential.user;
  await user?.delete();
  await user?.reauthenticateWithCredential(credential);
  await user?.sendEmailVerification();
  await user?.updateDisplayName(name);
  await user?.updateEmail(emailAddress);
  await user?.updatePassword(newPassword);
  await user?.updatePhotoURL(profilePhoto);
  FirebaseAuth.instance.authStateChanges().listen((User? user) {
    if (user == null) {
      throw Exception('User is currently signed out!');
    } else {
      throw Exception('User is signed in!');
    }
  });
  FirebaseAuth.instance.idTokenChanges().listen((User? user) {
    if (user == null) {
      throw Exception('User is currently signed out!');
    } else {
      throw Exception('User is signed in!');
    }
  });
  FirebaseAuth.instance.userChanges().listen((User? user) {
    if (user == null) {
      throw Exception('User is currently signed out!');
    } else {
      throw Exception('User is signed in!');
    }
  });
  if (FirebaseAuth.instance.currentUser != null) {
    throw Exception(FirebaseAuth.instance.currentUser?.uid);
  }
  if (user != null) {
    for (final providerProfile in user.providerData) {
      final contactNumber = providerProfile.phoneNumber;
      final emailAddress = providerProfile.email;
      final name = providerProfile.displayName;
      final profilePhoto = providerProfile.photoURL;
      final provider = providerProfile.providerId;
      final uid = providerProfile.uid;
    }
  }
  try {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailAddress,
        password: password
    );
  } on FirebaseAuthException catch (credentialError) {
    if (credentialError.code == 'user-not-found') {
      throw Exception('No user found for that email.');
    } else if (credentialError.code == 'wrong-password') {
      throw Exception('Wrong password provided for that user.');
    }
  }
  throw Exception(user?.uid);
}}