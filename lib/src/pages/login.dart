import 'package:flutter/material.dart';
import 'package:help_a_paw/src/utils/firebase_auth.dart';
import 'package:social_login_buttons/social_login_buttons.dart';
import '../../utility/app_router_routes.dart';
import '../showdialogs/message.dart';
import '../showdialogs/show_progress.dart';
import '../styles/colors.dart';
import '../utils/user_validation.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late String email;
  late String password;
  UserValidation userValidation = UserValidation();
  FirebaseAuthentication auth = FirebaseAuthentication();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  _validateAndSave() async {
    // validate login form
    if (_formKey.currentState!.validate()) {
      _formKey.currentState?.save();
      showProgressDialog(context, 'Please wait', true);
      auth.login(email, password).then((value) async {
        if (value != null && !value.user.emailVerified) {
          showProgressDialog(context, '', false);
          await dialogWithMessageAndCustomButton(
            context,
            'Error',
            'A confirmation link has been sent on your email. Please click it to complete your email verification',
            "OK",
            leftBtnMessage: '',
          );
        } else {
          showProgressDialog(context, '', false);
          Navigator.of(context)
              .pushNamedAndRemoveUntil(AppRoutes.homeScreen, (route) => false);
        }
      }).catchError((e) {
        showProgressDialog(context, '', false);
        dialogWithMessageAndCustomButton(context, 'Error', e.message, "OK",
            leftBtnMessage: 'CONTACT SUPPORT');
      });
    } else {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WillPopScope(
        onWillPop: () async {
          return true;
        },
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(22.0),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Center(
                        child: Image(
                          height: 100,
                          image: AssetImage("assets/images/logo.jpg"),
                        ),
                      ),
                      TextFormField(
                        onSaved: (value) => email = value!,
                        validator: userValidation.validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          floatingLabelBehavior: FloatingLabelBehavior.auto,
                        ),
                      ),
                      TextFormField(
                        onSaved: (value) => password = value!,
                        validator: userValidation.validatePassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: "Password",
                        ),
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          child: const Text(
                            "LOGIN",
                          ),
                          onPressed: () => _validateAndSave(),
                        ),
                      ),
                      const SizedBox(
                        height: 20,
                      ),
                      const Text("No account yet?"),
                      TextButton(
                        child: const Text(
                          "REGISTER",
                          style: TextStyle(color: primaryColor),
                        ),
                        onPressed: () {
                          Navigator.of(context)
                              .pushNamed(AppRoutes.registerRoute);
                        },
                      ),
                      const SizedBox(
                        height: 20,
                      ),
                      const Text("or"),
                      SocialLoginButton(
                        height: 30,
                        fontSize: 12,
                        imageWidth: 17,
                        backgroundColor: Colors.black,
                        textColor: Colors.grey,
                        width: 130,
                        text: 'Sign In',
                        buttonType: SocialLoginButtonType.google,
                        onPressed: () {
                          showProgressDialog(context, 'Please wait', true);
                          auth.signInWithGoogle().then((value) async {
                            if (value != null) {
                              showProgressDialog(context, '', false);
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                  AppRoutes.homeScreen, (route) => false);
                            } else {
                              showProgressDialog(context, '', false);
                            }
                          }).catchError((e) {
                            showProgressDialog(context, '', false);
                            dialogWithMessageAndCustomButton(
                                context, 'Error', e.message, "OK",
                                leftBtnMessage: 'CONTACT SUPPORT');
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
