import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:yandex_maps_mapkit/mapkit.dart' as mapkit;

import '../../objects/stations.dart';

class ChargingStationScreen extends StatefulWidget {
  final ChargingStation station;
  final VoidCallback onBack;

  const ChargingStationScreen({
    required this.station,
    required this.onBack,
    Key? key,
  }) : super(key: key);

  @override
  State<ChargingStationScreen> createState() => _ChargingStationScreenState();
}

class _ChargingStationScreenState extends State<ChargingStationScreen> {
  late ChargingStation station;
  int? currentUserId;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    station = widget.station;
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserId = prefs.getInt('userId');
    });
  }

  Widget _buildInfoColumn(IconData icon, String name, Color color, String text) {
    if (name == 'Статус') {
      switch (text) {
        case 'free':
          text = 'Свободна';
          color = Colors.green;
        case 'busy':
          text = 'Занята';
          color = Colors.red;
        case 'reserved':
          text = 'Забронирована';
          color = Colors.orange;
        default:
          text = text;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 10),
        Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildTariffRow(String time, String price) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(time, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            price,
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _reserveStation() async {
    setState(() {
      isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('userToken');

      if (token == null || currentUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка авторизации')),
        );
        return;
      }

      final response = await http.post(
        Uri.parse('http://192.168.31.215:5000/api/stations/${station.id}/reserve'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Станция успешно забронирована!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green,duration: Duration(seconds: 2),),
        );

        setState(() {
          station.status = 'reserved';
          station.reservedBy = currentUserId;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${responseData['error']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка соединения: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _cancelReservation() async {
    setState(() {
      isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('userToken');

      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка авторизации')),
        );
        return;
      }

      final response = await http.post(
        Uri.parse('http://192.168.31.215:5000/api/stations/${station.id}/cancel'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Бронь успешно отменена!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green,duration: Duration(seconds: 2),),
        );

        setState(() {
          station.status = 'free';
          station.reservedBy = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${responseData['error']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка соединения: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Widget _buildTimePriceRow(String time, String price) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(time),
          Text(price, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0D7CFF),
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          onPressed: widget.onBack,
        ),
        title: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text(station.name, textAlign: TextAlign.center), Text(
                'ID: ${station.id}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),],

          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    height: MediaQuery.of(context).size.height / 4,
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: station.photoUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[200],
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: FittedBox(
                            child: Icon(Icons.ev_station, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          // Блок с разъемом
                          Expanded(
                            child: _buildInfoColumn(
                              Icons.ev_station,
                              'Разъем',
                              const Color(0xFF0D7CFF),
                              widget.station.connectorType,
                            ),
                          ),

                          // Вертикальный разделитель
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.grey.withOpacity(0.3),
                          ),

                          // Блок с мощностью
                          Expanded(
                            child: _buildInfoColumn(
                              Icons.bolt,
                              'Мощность',
                              Colors.amber,
                              '${widget.station.power} кВт',
                            ),
                          ),

                          // Вертикальный разделитель
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.grey.withOpacity(0.3),
                          ),

                          // Блок со статусом
                          Expanded(
                            child: _buildInfoColumn(
                              Icons.check_circle,
                              'Статус',
                              Colors.green,
                              widget.station.status,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.1),
                          blurRadius: 5,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Тарификация',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ...station.pricing.entries.map(
                              (e) => Column(
                            children: [
                              Divider(height: 1, color: Colors.grey[100]),
                              _buildTimePriceRow(e.key, '${e.value}₽ за кВт/ч'),
                            ],
                          ),
                        ),
                        _buildTariffRow('Парковка после зарядки', '10 руб/мин'),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.1),
                          blurRadius: 5,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Координаты',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Divider(height: 1, color: Colors.grey[200]),
                        _buildStationRow(
                          'Адрес',
                          station.address,
                        ),
                        Divider(height: 1, color: Colors.grey[200]),
                        _buildStationRow('Широта', station.latitude.toString()),
                        Divider(height: 1, color: Colors.grey[200]),
                        _buildStationRow(
                          'Долгота',
                          station.longitude.toString(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () {
                      if (station.status == 'free') {
                        _reserveStation();
                      } else if (station.status == 'reserved' &&
                          station.reservedBy == currentUserId) {
                        _cancelReservation();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Станция уже зарезервирована другим пользователем', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red,duration: Duration(seconds: 2),),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: station.status == 'free'
                          ?  Colors.green
                          : station.reservedBy == currentUserId
                          ? Colors.orange
                          : Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                      station.status == 'free'
                          ? 'Зарезервировать'
                          : station.reservedBy == currentUserId
                          ? 'Отменить бронь'
                          : 'Занята',
                      style: const TextStyle(
                          fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Построение маршрута')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D7CFF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Начать зарядку',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}