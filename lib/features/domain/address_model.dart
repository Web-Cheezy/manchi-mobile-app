

class NigerianState {
  final String state;
  final String alias;
  final List<String> lgas;

  NigerianState({
    required this.state,
    required this.alias,
    required this.lgas,
  });

  factory NigerianState.fromJson(Map<String, dynamic> json) {
    return NigerianState(
      state: json['state'],
      alias: json['alias'],
      lgas: List<String>.from(json['lgas']),
    );
  }
}

class UserAddress {
  final String? id;
  final String state;
  final String lga;
  final String area;
  final String street;
  final String houseNumber;
  final bool isDefault;

  UserAddress({
    this.id,
    required this.state,
    required this.lga,
    required this.area,
    required this.street,
    required this.houseNumber,
    this.isDefault = false,
  });

  String get fullAddress => '$houseNumber, $street, $area, $lga, $state State';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'state': state,
      'lga': lga,
      'area': area,
      'street': street,
      'houseNumber': houseNumber, // camelCase
      'house_number': houseNumber, // snake_case
      'isDefault': isDefault, // camelCase
      'is_default': isDefault, // snake_case
    };
  }

  factory UserAddress.fromMap(Map<String, dynamic> map) {
    return UserAddress(
      id: map['id'],
      state: map['state'],
      lga: map['lga'],
      area: map['area'],
      street: map['street'],
      houseNumber: map['houseNumber'] ?? map['house_number'],
      isDefault: map['isDefault'] ?? map['is_default'] ?? false,
    );
  }
}
