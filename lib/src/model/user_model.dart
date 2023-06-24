import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

// User Management Configuration
class UserModel {
  final String contactNumber;
  final String emailAddress;
  final String name;
  final String profilePhoto;
  final String provider;
  final String uid;

  const UserModel({
    required this.contactNumber,
    required this.emailAddress,
    required this.name,
    required this.profilePhoto,
    required this.provider,
    required this.uid,
  });

Future<UserModel> manageUsers() async {
  await FirebaseAuth.instance.setLanguageCode("en");
  await FirebaseAuth.instance.sendPasswordResetEmail(email: emailAddress);
  final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
  final user = userCredential.user;
  await user?.reauthenticateWithCredential(credential);
  await user?.sendEmailVerification();
  await user?.updateDisplayName(name);
  await user?.updateEmail(emailAddress);
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
  throw Exception(user?.uid);
}}