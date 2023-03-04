class User {
  String? email;
  String? uid;
  String? name;
  String? password;
  String? phoneNumber;

  User({this.email, this.uid, this.name, this.password, this.phoneNumber});

  factory User.fromJson(Map<dynamic, dynamic> json) => User(
      email: json['email'],
      uid: json['uid'],
      name: json['name'],
      password: json['password'],
      phoneNumber: json['phoneNumber']);
}
