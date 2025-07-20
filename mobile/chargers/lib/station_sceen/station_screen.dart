import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

import '../objects/stations.dart';

class ChargeSession {
  final String stationId;
  final String stationName;
  final DateTime startTime;
  final DateTime endTime;
  final double powerConsumed;
  final double totalCost;

  ChargeSession({
    required this.stationId,
    required this.stationName,
    required this.startTime,
    required this.endTime,
    required this.powerConsumed,
    required this.totalCost,
  });

  Map<String, dynamic> toMap() {
    return {
      'stationId': stationId,
      'stationName': stationName,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'powerConsumed': powerConsumed,
      'totalCost': totalCost,
    };
  }

  factory ChargeSession.fromMap(Map<String, dynamic> map) {
    return ChargeSession(
      stationId: map['stationId'],
      stationName: map['stationName'],
      startTime: DateTime.parse(map['startTime']),
      endTime: DateTime.parse(map['endTime']),
      powerConsumed: map['powerConsumed'],
      totalCost: map['totalCost'],
    );
  }
}

class StationsScreen extends StatefulWidget {
  final int? selectedStationId;
  const StationsScreen({super.key, this.selectedStationId});

  @override
  State<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends State<StationsScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _textController = TextEditingController();

  bool _isFlashOn = false;
  String? _lastScannedCode;
  bool _showScanResult = false;
  late String _currentScreen = 'scan';
  ChargingStation? _currentStation;
  ChargeSession? _activeSession;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectedStationId != null) {
      _textController.text = widget.selectedStationId.toString();
    }
    _loadLastData();
  }

  Future<void> _loadLastData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();

      // Always reset to scan screen when coming back, unless there's an active session
      _currentScreen = 'scan';

      // Load active session if exists
      final sessionJson = prefs.getString('active_session');
      if (sessionJson != null) {
        _activeSession = ChargeSession.fromMap(json.decode(sessionJson));
      }

      // Load station only if there's an active session
      if (_activeSession != null) {
        final stationJson = prefs.getString('last_station');
        if (stationJson != null) {
          _currentStation = ChargingStation.fromMap(json.decode(stationJson));
          _currentScreen = 'charging';
        }
      }

      // If selectedStationId is provided, use it (but still stay on scan screen)
      if (widget.selectedStationId != null) {
        _textController.text = widget.selectedStationId.toString();
      } else {
        _textController.clear();
      }

      setState(() {
        // Only override to charging screen if we have both session and station
        if (_activeSession != null && _currentStation != null) {
          _currentScreen = 'charging';
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLastData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_screen', _currentScreen);

    if (_currentStation != null) {
      await prefs.setString(
        'last_station',
        json.encode(_currentStation!.toMap()),
      );
    } else {
      await prefs.remove('last_station');
    }

    if (_activeSession != null) {
      await prefs.setString(
        'active_session',
        json.encode(_activeSession!.toMap()),
      );
    } else {
      await prefs.remove('active_session');
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _textController.clear(); // Clear the text field
    _saveLastData();
    super.dispose();
  }

  void _handleScanned(String id) async {
    setState(() {
      _isLoading = true;
      _lastScannedCode = id;
      _showScanResult = true;
    });

    try {
      final ids = int.tryParse(id);
      if (ids == null) {
        throw Exception('Invalid station ID format');
      }

      final response = await http.get(
        Uri.parse('http://192.168.31.215:5000/api/stations/$ids'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final stationData = json.decode(response.body);
        if (stationData['status'] == 'free' ||
            stationData['status'] == 'reserved') {
          // Helper function to parse double from either string or num
          double parsePower(dynamic powerValue) {
            if (powerValue is num) return powerValue.toDouble();
            if (powerValue is String) return double.tryParse(powerValue) ?? 0.0;
            return 0.0;
          }

          setState(() {
            _currentStation = ChargingStation(
              id: stationData['id'] ?? id,
              name: stationData['name']?.toString() ?? 'Неизвестная станция',
              address: stationData['address']?.toString() ?? 'Адрес не указан',
              latitude: stationData['latitude']?.toString() ?? '0',
              longitude: stationData['longitude']?.toString() ?? '0',
              connectorType:
                  stationData['connector_type']?.toString() ?? 'Type 2',
              currentType: stationData['current_type']?.toString() ?? 'AC',
              power: parsePower(stationData['power']),
              status: stationData['status']?.toString() ?? 'active',
              photoUrl:
                  stationData['photo_url']?.toString() ??
                  'https://example.com/default.jpg',
              tariffId:
                  stationData['tariff_id'] is num
                      ? (stationData['tariff_id'] as num).toInt()
                      : 1,
              reservedBy: stationData['reserved_by'],
              pricing:
                  stationData['pricing'] is Map
                      ? Map<String, double>.from(
                        (stationData['pricing'] as Map).map(
                          (k, v) => MapEntry(
                            k.toString(),
                            (v is num
                                ? v.toDouble()
                                : double.tryParse(v.toString()) ?? 0.0),
                          ),
                        ),
                      )
                      : {
                        '06:00-09:00': 11.5,
                        '09:00-17:00': 12.0,
                        '17:00-22:00': 15.0,
                        '22:00-06:00': 10.0,
                      },
            );
            _currentScreen = 'start_charge';
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Станция ${stationData['name'] ?? id} занята',
                style: TextStyle(color: Colors.black),
              ),
              backgroundColor: Colors.yellow,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ошибка получения данных станции: ${response.statusCode}',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ошибка подключения: ${e.toString()}',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _showScanResult = false;
      });
      _saveLastData();
    }
  }

  Widget _getCurrentScreen() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D7CFF)),
        ),
      );
    }

    if (_currentStation == null && _currentScreen != 'scan') {
      return _buildScannerScreen();
    }

    switch (_currentScreen) {
      case 'start_charge':
        return StartChargeScreen(
          textController: _textController,
          station: _currentStation!,
          onBack: () {
            _saveLastData();
            setState(() => _currentScreen = 'scan');
          },
          onChargeStarted: () async {
            setState(() => _isLoading = true);
            try {
              await _saveLastData();
              setState(() {
                _activeSession = ChargeSession(
                  stationId: _currentStation!.id.toString(),
                  stationName: _currentStation!.name,
                  startTime: DateTime.now(),
                  endTime: DateTime.now(),
                  powerConsumed: 0.0,
                  totalCost: 0.0,
                );
                _currentScreen = 'charging';
              });
              _saveLastData();
            } finally {
              setState(() => _isLoading = false);
            }
          },
        );

      case 'charging':
        return ChargingScreen(
          station: _currentStation!,
          initialSession: _activeSession,
          onBack: () {
            _saveLastData();
            setState(() => _currentScreen = 'scan');
          },
          onStopCharge: (session) async {
            setState(() => _isLoading = true);
            try {
              await _saveLastData();
              setState(() => _activeSession = null);

              final shouldClear = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => ReceiptScreen(session: session),
                ),
              );

              if (shouldClear == true) {
                _textController.clear();
                setState(() {
                  _currentScreen = 'scan';
                  _currentStation = null;
                  _lastScannedCode = null;
                });
              }
            } finally {
              setState(() => _isLoading = false);
            }
          },
        );
      default:
        return _buildScannerScreen();
    }
  }

  Widget _buildScannerScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Станция', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            color: Colors.white,
            onPressed: () {
              setState(() => _isFlashOn = !_isFlashOn);
              _scannerController.toggleTorch();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            fit: BoxFit.cover,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                final code = barcodes.first.rawValue!;
                if (code != _lastScannedCode) {
                  _handleScanned(code);
                }
              }
            },
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromRGBO(0, 0, 0, 0.7),
                  Colors.transparent,
                  Colors.transparent,
                  Color.fromRGBO(0, 0, 0, 0.7),
                ],
                stops: const [0.0, 0.2, 0.8, 1.0],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_showScanResult)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_lastScannedCode',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color:
                          _showScanResult
                              ? Colors.green
                              : Color.fromRGBO(255, 255, 255, 0.5),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(255, 255, 255, 0.9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.2),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _textController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        hintText: 'Введите номер',
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_textController.text.isNotEmpty) {
                          _handleScanned(_textController.text);
                          setState(() => _currentScreen = 'start_charge');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Отправить',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          _getCurrentScreen(),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D7CFF)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StartChargeScreen extends StatefulWidget {
  final TextEditingController textController;
  final ChargingStation station;
  final VoidCallback onBack;
  final VoidCallback onChargeStarted;

  const StartChargeScreen({
    super.key,
    required this.station,
    required this.onBack,
    required this.textController,
    required this.onChargeStarted,
  });

  @override
  State<StartChargeScreen> createState() => _StartChargeScreenState();
}

class _StartChargeScreenState extends State<StartChargeScreen> {
  bool _isLoading = false;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserId = prefs.getInt('userId');
    });
  }

  Future<void> _reserveStation() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('userToken');

      if (token == null || _currentUserId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ошибка авторизации')));
        return;
      }

      final response = await http.post(
        Uri.parse(
          'http://192.168.31.215:5000/api/stations/${widget.station.id}/reserve',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Станция успешно зарезервирована!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        setState(() {
          widget.station.status = 'reserved';
          widget.station.reservedBy = _currentUserId;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${responseData['error']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка соединения: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelReservation() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('userToken');

      if (token == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ошибка авторизации')));
        return;
      }

      final response = await http.post(
        Uri.parse(
          'http://192.168.31.215:5000/api/stations/${widget.station.id}/cancel',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Бронь успешно отменена!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        setState(() {
          widget.station.status = 'free';
          widget.station.reservedBy = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${responseData['error']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка соединения: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildInfoColumn(
    IconData icon,
    String name,
    Color color,
    String text,
  ) {
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

  void _handleChargeStart() {
    if (widget.station.status == 'free' ||
        (widget.station.status == 'reserved' &&
            widget.station.reservedBy == _currentUserId)) {
      widget.onChargeStarted();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Невозможно начать зарядку: станция занята или забронирована другим пользователем',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canReserve = widget.station.status == 'free';
    final canCancel =
        widget.station.status == 'reserved' &&
        widget.station.reservedBy == _currentUserId;
    final canStartCharge =
        widget.station.status == 'free' ||
        (widget.station.status == 'reserved' &&
            widget.station.reservedBy == _currentUserId);

    // print('------------------$canCancel ${widget.station.reservedBy} $_currentUserId');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D7CFF),
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
          onPressed: () {
            widget.onBack();
            widget.textController.clear();
            // Clear any entered station ID when going back
          },
        ),
        title: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.station.name),
              Text(
                'ID: ${widget.station.id}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            color: const Color(0xFF0D7CFF),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: MediaQuery.of(context).size.height / 4,
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromRGBO(0, 0, 0, 0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
                image: DecorationImage(
                  image: NetworkImage(widget.station.photoUrl),
                  fit: BoxFit.cover,
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
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromRGBO(0, 0, 0, 0.1),
                    blurRadius: 5,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    child: const Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Тарификация',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  ...widget.station.pricing.entries.map(
                    (e) => Column(
                      children: [
                        Divider(height: 1, color: Colors.grey[100]),
                        _buildTimePriceRow(e.key, '${e.value}₽ за кВт/ч'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                if (canReserve || canCancel)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(
                        top: 16,
                        left: 16,
                        right: 8,
                        bottom: 16,
                      ),
                      child: ElevatedButton(
                        onPressed:
                            _isLoading
                                ? null
                                : canCancel
                                ? _cancelReservation
                                : _reserveStation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.station.status == 'free'
                              ?  Colors.green
                              : widget.station.reservedBy == _currentUserId
                              ? Colors.orange
                              : Colors.grey,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child:
                            _isLoading
                                ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                                : Text(
                                  canCancel
                                      ? 'Отменить бронь'
                                      : 'Забронировать',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(
                      top: 16,
                      left: 8,
                      right: 16,
                      bottom: 16,
                    ),
                    child: ElevatedButton(
                      onPressed: canStartCharge ? _handleChargeStart : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            canStartCharge
                                ? const Color(0xFF0D7CFF)
                                : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Начать зарядку',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChargingScreen extends StatefulWidget {
  final ChargingStation station;
  final ChargeSession? initialSession;
  final VoidCallback onBack;
  final Function(ChargeSession) onStopCharge;

  const ChargingScreen({
    super.key,
    required this.station,
    this.initialSession,
    required this.onBack,
    required this.onStopCharge,
  });

  @override
  State<ChargingScreen> createState() => _ChargingScreenState();
}

class _ChargingScreenState extends State<ChargingScreen> {
  late Timer _timer;
  late DateTime _startTime;
  Duration _elapsedTime = Duration.zero;
  double _powerConsumed = 0.0;
  double _currentRate = 0.0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  void _initSession() {
    // Восстанавливаем состояние из initialSession, если оно есть
    if (widget.initialSession != null) {
      _startTime = widget.initialSession!.startTime;
      _powerConsumed = widget.initialSession!.powerConsumed;
      _elapsedTime = widget.initialSession!.endTime.difference(_startTime);
    } else {
      _startTime = DateTime.now();
    }

    _currentRate = _getCurrentRate();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedTime = DateTime.now().difference(_startTime);
        _currentRate = _getCurrentRate();
        _powerConsumed = widget.station.power * _elapsedTime.inSeconds / 3600;
      });
    });
  }

  // Метод для определения текущего тарифа
  double _getCurrentRate() {
    final now = DateTime.now();
    final hour = now.hour;
    final timeString = now.toString();

    // Определяем текущий временной интервал
    String currentInterval;
    if (hour >= 6 && hour < 9) {
      currentInterval = '06:00-09:00';
    } else if (hour >= 9 && hour < 17) {
      currentInterval = '09:00-17:00';
    } else if (hour >= 17 && hour < 22) {
      currentInterval = '17:00-22:00';
    } else {
      currentInterval = '22:00-06:00';
    }

    // Возвращаем соответствующий тариф
    return widget.station.pricing[currentInterval] ??
        widget.station.pricing.values.first;
  }

  double _calculateTotalCost() {
    // Стоимость = мощность * тариф
    return _powerConsumed * _currentRate;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Widget _buildInfoColumn(IconData icon, String text, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final totalCost = _calculateTotalCost();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Color(0xFF0D7CFF),
        leading: IconButton(
          icon: Container(
            decoration: BoxDecoration(
              color: Color(0xFF0D7CFF),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          onPressed: widget.onBack,
        ),
        title: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.station.name,
                style: const TextStyle(color: Colors.white),
              ),
              Text(
                'ID: ${widget.station.id}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            color: Colors.white,
            onPressed: () {},
          ),
        ],
      ),
      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            radius: 2.8,
            center: Alignment.topCenter,
            colors: [Color(0xFF0D7CFF), Color(0xFFFFFFFF)],
            stops: [0.4, 0.5],
          ),
        ),
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
                    imageUrl: widget.station.photoUrl,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildInfoColumn(
                        Icons.ev_station,
                        widget.station.connectorType,
                        Colors.white,
                      ),
                      _buildInfoColumn(
                        Icons.bolt,
                        '${widget.station.power} кВт',
                        Colors.white,
                      ),
                      _buildInfoColumn(
                        Icons.attach_money,
                        '${_currentRate.toStringAsFixed(2)} ₽/кВт·ч',
                        Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.1),
                      blurRadius: 5,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Прошло времени',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDuration(_elapsedTime),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Получено энергии',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_powerConsumed.toStringAsFixed(2)} кВт·ч',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Текущий тариф',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            '${_currentRate.toStringAsFixed(2)} ₽/кВт·ч',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Общая стоимость',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            '${totalCost.toStringAsFixed(2)} ₽',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0D7CFF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () {
                    widget.onStopCharge(
                      ChargeSession(
                        stationId: widget.station.id.toString(),
                        stationName: widget.station.name,
                        startTime: _startTime,
                        endTime: DateTime.now(),
                        powerConsumed: _powerConsumed,
                        totalCost: totalCost,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Остановить зарядку',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF0D7CFF),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReceiptScreen extends StatelessWidget {
  final ChargeSession session;
  final Color primaryColor = Color(0xFF0D7CFF); // Синий цвет как основной

  ReceiptScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: primaryColor.withOpacity(0.7),
          title: Text(
            'Детали транзакции',
            style: TextStyle(color: Colors.white),
          ),
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        body: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 2.8,
              colors: [primaryColor.withOpacity(0.7), Color(0xFFFFFFFF)],
              stops: [0.4, 0.5],
            ),
          ),
          child: ClipPath(
            clipper: JaggedClipper(),
            child: Container(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              margin: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Транзакция',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Center(
                      child: Text(
                        'ID: ${session.hashCode.toRadixString(16).padLeft(8, '0')}',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    Divider(height: 32, color: primaryColor),

                    Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Зарядка',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),

                    _buildDetailRow('Станция:', session.stationName),
                    _buildDetailRow('ID станции:', session.stationId),
                    _buildDetailRow(
                      'Дата:',
                      '${session.endTime.day.toString().padLeft(2, '0')}.${session.endTime.month.toString().padLeft(2, '0')}.${session.endTime.year}',
                    ),
                    _buildDetailRow(
                      'Время:',
                      '${session.endTime.hour.toString().padLeft(2, '0')}:${session.endTime.minute.toString().padLeft(2, '0')}',
                    ),
                    _buildDetailRow(
                      'Длительность:',
                      _formatDuration(
                        session.endTime.difference(session.startTime),
                      ),
                    ),
                    _buildDetailRow(
                      'Потреблено энергии:',
                      '${session.powerConsumed.toStringAsFixed(2)} кВт·ч',
                    ),
                    _buildDetailRow('Комиссия:', '0.00 ₽'),
                    _buildDetailRow('Налог:', '0.00 ₽'),
                    _buildDetailRow('Адрес:', 'Онлайн'),

                    Divider(height: 32, color: primaryColor),

                    Center(
                      child: Text(
                        'Итоговая сумма:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        '${session.totalCost.toStringAsFixed(2)} ₽',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    Center(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            true,
                          ); // Возвращаем true как флаг очистки
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          'Готово',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}

class ChargeSessionManager {
  static final ChargeSessionManager _instance =
      ChargeSessionManager._internal();
  factory ChargeSessionManager() => _instance;
  ChargeSessionManager._internal();

  ChargeSession? _currentSession;
  ChargingStation? _currentStation;
  DateTime? _lastUpdateTime;

  ChargeSession? get currentSession => _currentSession;
  ChargingStation? get currentStation => _currentStation;

  void startNewSession(ChargingStation station) {
    _currentStation = station;
    _currentSession = ChargeSession(
      stationId: station.id.toString(),
      stationName: station.name,
      startTime: DateTime.now(),
      endTime: DateTime.now(),
      powerConsumed: 0,
      totalCost: 0,
    );
    _lastUpdateTime = DateTime.now();
    _saveToPrefs();
  }

  void updateSession() {
    if (_currentSession == null || _currentStation == null) return;

    final now = DateTime.now();
    final elapsedSeconds = now.difference(_lastUpdateTime!).inSeconds;
    final power = _currentStation!.power * elapsedSeconds / 3600;
    final rate = _getCurrentRate(now);
    final cost = power * rate;

    _currentSession = ChargeSession(
      stationId: _currentSession!.stationId,
      stationName: _currentSession!.stationName,
      startTime: _currentSession!.startTime,
      endTime: now,
      powerConsumed: _currentSession!.powerConsumed + power,
      totalCost: _currentSession!.totalCost + cost,
    );
    _lastUpdateTime = now;
    _saveToPrefs();
  }

  void stopSession() {
    updateSession();
    _currentSession = null;
    _currentStation = null;
    _lastUpdateTime = null;
    _saveToPrefs();
  }

  double _getCurrentRate(DateTime time) {
    final hour = time.hour;
    final pricing = _currentStation!.pricing;

    if (hour >= 6 && hour < 9) return pricing['06:00-09:00']!;
    if (hour >= 9 && hour < 17) return pricing['09:00-17:00']!;
    if (hour >= 17 && hour < 22) return pricing['17:00-22:00']!;
    return pricing['22:00-06:00']!;
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentSession != null && _currentStation != null) {
      await prefs.setString(
        'current_session',
        json.encode(_currentSession!.toMap()),
      );
      await prefs.setString('last_update', _lastUpdateTime!.toIso8601String());
    } else {
      await prefs.remove('current_session');
      await prefs.remove('current_station');
      await prefs.remove('last_update');
    }
  }

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionJson = prefs.getString('current_session');
    final stationJson = prefs.getString('current_station');
    final lastUpdate = prefs.getString('last_update');

    if (sessionJson != null && stationJson != null && lastUpdate != null) {
      _currentSession = ChargeSession.fromMap(json.decode(sessionJson));
      _currentStation = ChargingStation.fromMap(json.decode(stationJson));
      _lastUpdateTime = DateTime.parse(lastUpdate);

      // Обновляем сессию с учетом времени, прошедшего с последнего сохранения
      final now = DateTime.now();
      final elapsedSeconds = now.difference(_lastUpdateTime!).inSeconds;
      if (elapsedSeconds > 0) {
        updateSession();
      }
    }
  }
}

class JaggedClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final Path path = Path();
    const double radius = 8;
    const int count = 15;
    final double step = size.width / count;

    // Верхняя кривая
    path.moveTo(0, 0);
    for (int i = 0; i < count; i++) {
      final double x = step * (i + 1);
      if (i % 2 == 0) {
        path.arcToPoint(
          Offset(x, 0),
          radius: Radius.circular(radius),
          clockwise: false,
        );
      } else {
        path.lineTo(x, 0);
      }
    }

    // Правый край
    path.lineTo(size.width, size.height);

    // Нижняя кривая (в обратном порядке, зеркально)
    for (int i = count; i > 0; i--) {
      final double x = step * (i - 1);
      if ((i - 1) % 2 == 0) {
        path.arcToPoint(
          Offset(x, size.height),
          radius: Radius.circular(radius),
          clockwise: false,
        );
      } else {
        path.lineTo(x, size.height);
      }
    }

    // Левый край
    path.lineTo(0, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
