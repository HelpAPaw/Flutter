import 'package:flutter/material.dart';
import 'package:help_a_paw/src/pages/login.dart';
import 'package:help_a_paw/src/utils/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/users.dart';
import '../services/constants.dart' as global;
import '../showdialogs/message.dart';
import '../showdialogs/show_progress.dart';
import '../utils/user_validation.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final String whyTitleMessage = "Why do you want my phone number?";
  final String whyMessage =
      "Entering you phone number is not required for registration. However, we strongly encourage you to fill it so you can be quickly reached if a valunteer needs information about a signal that you submitted.";
  final _formKey = GlobalKey<FormState>();
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController name = TextEditingController();
  final TextEditingController confirmPassword = TextEditingController();
  final TextEditingController phoneNumber = TextEditingController();
  FirebaseAuthentication auth = FirebaseAuthentication();
  UserValidation userValidation = UserValidation();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  _validateAndSave() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState?.save();
      showProgressDialog(context, 'Please wait', true);
      UserDetails user = UserDetails()
        ..email = email.value.text
        ..name = name.value.text
        ..phoneNumber = phoneNumber.value.text
        ..password = password.value.text;
      auth.register(user).then((value) async {
        if (value != null) {
          showProgressDialog(context, '', false);
          await dialogWithMessageAndCustomButton(
            context,
            'Success',
            'A confirmation link has been sent on your email. Please click it to complete your registration',
            "OK",
            leftBtnMessage: '',
          );
          SharedPreferences prefs = await SharedPreferences.getInstance();
          prefs.setBool(global.loggedIn, true);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => LoginPage(),
                  settings: const RouteSettings(name: global.loginRoute)));
        } else {
          showProgressDialog(context, '', false);
        }
      }).catchError((e) {
        showProgressDialog(context, '', false);
        dialogWithMessageAndCustomButton(context, 'Error', e, "OK",
            leftBtnMessage: 'CONTACT SUPPORT');
      });
    } else {}
  }

  String? validateConfirmPassword(value) {
    if (value.length == 0) return 'Password cannot be blank';
    if (password.value.text != null && password.value.text != value) {
      return 'The two entered passwords are not same';
    } else {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                children: <Widget>[
                  const Center(
                    child: Image(
                      image: AssetImage("assets/images/logo.jpg"),
                      height: 100,
                    ),
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  TextFormField(
                    controller: email,
                    validator: userValidation.validateEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: "Email",
                    ),
                  ),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    validator: userValidation.validatePassword,
                    decoration: const InputDecoration(
                      labelText: "Password",
                    ),
                  ),
                  TextFormField(
                    controller: confirmPassword,
                    obscureText: true,
                    validator: validateConfirmPassword,
                    decoration: const InputDecoration(
                      labelText: "Confirm Password",
                    ),
                  ),
                  TextFormField(
                    controller: name,
                    validator: userValidation.validateName,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      labelText: "Name",
                    ),
                  ),
                  TextFormField(
                    controller: phoneNumber,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: "Phone Number",
                    ),
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      GestureDetector(
                        onTap: () {
                          dialogWithMessageAndCustomButton(
                              context, whyTitleMessage, whyMessage, "I SEE",
                              leftBtnMessage: '');
                        },
                        child: Text(
                          "Why?",
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ButtonStyle(
                          backgroundColor:
                              MaterialStateProperty.all<Color>(Colors.orange)),
                      onPressed: () => _validateAndSave(),
                      child: const Text(
                        "REGISTER",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  const Text("Already a member?"),
                  TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const LoginPage(),
                                settings: const RouteSettings(
                                    name: global.loginRoute)));
                      },
                      child: const Text(
                        "LOGIN",
                        style: TextStyle(color: Colors.orange),
                      ))
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
