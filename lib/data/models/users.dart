import 'dart:convert';

class Users{
  final String id;
  String userName;

  Users({required this.id, required this.userName});

  factory Users.fromJSON({required Map<String, dynamic> json}){
    if((json['id'] == null && json['id'] is String)|| (json['user_name'] == null && json['user_name'] is String)){
      return Users(id: '', userName: '');
    }else{
      return Users(id: json['id'], userName: json['user_name']);
    }
  }

  Map<String, dynamic> toJSON() => {
    'id' : id,
    'user_name' : userName
  };

  @override
  String toString() {
    // TODO: implement toString
    return super.toString();
  }

}