class ProfileModel {
  String _userName;
  int _age;
  String _email;

  ProfileModel({required this._userName, required this._age, required this._email});


  String get userName => _userName;

  set userName(String value) {
    _userName = value;
  }

  String get email => _email;

  set email(String value) {
    _email = value;
  }

  int get age => _age;

  set age(int value) {
    _age = value;
  }

}