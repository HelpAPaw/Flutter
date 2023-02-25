class Users {
  String? email;
  String? uid;
  String? name;
  String? password;
  String? phoneNumber;

  Users(
      {this.email,
        this.uid,
        this.name,
        this.password,
        this.phoneNumber});

  factory Users.fromJson(Map<dynamic, dynamic> json) => Users(
      email: json['email'],
      uid: json['uid'],
      name: json['name'],
      password: json['password'],
      phoneNumber: json['phoneNumber']);
}
