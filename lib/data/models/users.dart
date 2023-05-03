class UserDetails {
  String? email;
  String? uid;
  String? name;
  String? password;
  String? phoneNumber;

  UserDetails(
      {this.email, this.uid, this.name, this.password, this.phoneNumber});

  factory UserDetails.fromJson(Map<String, dynamic> json) => UserDetails(
      email: json['email'],
      uid: json['uid'],
      name: json['name'],
      password: json['password'],
      phoneNumber: json['phoneNumber']);
}
