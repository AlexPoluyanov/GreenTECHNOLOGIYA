import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../objects/stations.dart';

class StationService {
  static const String baseUrl = 'http://192.168.31.215:5000/api';

  Future<List<ChargingStation>> getStations({
    String? connectorType,
    String? currentType,
    double? minPower,
    String? status,
  }) async {
    final queryParams = <String, String>{};

    if (connectorType != null) queryParams['connector_type'] = connectorType;
    if (currentType != null) queryParams['current_type'] = currentType;
    if (minPower != null) queryParams['min_power'] = minPower.toString();
    if (status != null) queryParams['status'] = status;

    final uri = Uri.parse('$baseUrl/stations').replace(queryParameters: queryParams);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final stations = (data['stations'] as List)
          .map((stationJson) => ChargingStation.fromMap(stationJson))
          .toList();
      return stations;
    } else {
      throw Exception('Failed to load stations: ${response.statusCode}');
    }
  }
}