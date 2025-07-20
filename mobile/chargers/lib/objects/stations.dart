class ChargingStation {
   int id;
   String name;
   String address;
   String latitude;
   String longitude;
   String connectorType;
   String currentType;
   double power;
  String status;
   String photoUrl;
   int tariffId;
   int? reservedBy;
   Map<String, double> pricing;

  ChargingStation({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.connectorType,
    required this.currentType,
    required this.power,
    required this.status,
    required this.photoUrl,
    required this.tariffId,
    this.reservedBy,
    required this.pricing,
  });

  factory ChargingStation.fromMap(Map<String, dynamic> map) {
    // Вспомогательная функция для преобразования в double
    double _parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    // Вспомогательная функция для преобразования в строку
    String _parseString(dynamic value) {
      return value?.toString() ?? '';
    }

    Map<String, double> _parsePricing(dynamic pricing) {
      if (pricing is Map) {
        return pricing.map<String, double>((key, value) {
          return MapEntry(
            key?.toString() ?? '',
            _parseDouble(value),
          );
        });
      }
      return {'peak': 5.50, 'off_peak': 3.20}; // Значения по умолчанию
    }

    return ChargingStation(
      id: map['id'],
      name: _parseString(map['name']),
      address: _parseString(map['address']),
      latitude: _parseString(map['latitude']),
      longitude: _parseString(map['longitude']),
      connectorType: _parseString(map['connector_type']),
      currentType: _parseString(map['current_type']),
      power: _parseDouble(map['power']),
      status: _parseString(map['status']),
      photoUrl: _parseString(map['photo_url']),
      tariffId: map['tariff_id'],
      pricing: _parsePricing(map['pricing']),
      reservedBy: map['reserved_by']
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'connector_type': connectorType,
      'current_type': currentType,
      'power': power,
      'status': status,
      'photo_url': photoUrl,
      'tariff_id': tariffId,
      'pricing': pricing,
      'reserved_by': reservedBy
    };
  }
}