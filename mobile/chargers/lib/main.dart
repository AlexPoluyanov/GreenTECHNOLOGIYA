import 'dart:convert';
import 'package:chargers/auth_screen/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:chargers/maps/main.dart';
import 'package:chargers/profile_screen/profile_screen.dart';
import 'package:chargers/station_sceen/station_screen.dart';
import 'package:chargers/stations_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_maps_mapkit/init.dart' as init;
import 'package:fluttertoast/fluttertoast.dart';
import 'objects/stations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  init.initMapkit(apiKey: "11111", locale: 'ru_RU');
  runApp(const EVApp());
}

class EVApp extends StatelessWidget {
  const EVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      color: Colors.white,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        colorScheme: ColorScheme.light(
          primary: Color(0xFF0D7CFF),
          onPrimary: Colors.white,
          background: Colors.white,
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  int? _selectedStationId;
  List<Widget> get _screens => [
    const MainScreen(),
    StationsScreen(selectedStationId: _selectedStationId),
    const ProfileScreen(),
  ];

  void _selectStationAndChangeTab(int stationId) {
    setState(() {
      _selectedStationId = stationId;
      _selectedIndex = 1; // Переключаем на вкладку StationsScreen
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Color(0xFF0D7CFF),
        backgroundColor: Colors.white,
        onTap: (index) {
          setState(() => _selectedIndex = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Карта'),
          BottomNavigationBarItem(icon: Icon(Icons.flash_on), label: 'Станция'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Аккаунт'),
        ],
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  List<ChargingStation> _allStations = [];
  List<ChargingStation> _filteredStations = [];

  double _minPower = 3;
  double _maxPower = 400;
  final List<String> _selectedACTypes = [];
  final List<String> _selectedDCTypes = [];

  double _userBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadUserBalance();
    _searchController.addListener(_updateSearchQuery);
    _fetchStations();
  }

  Future<void> _loadUserBalance() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userBalance = prefs.getDouble('userBalance') ?? 0.0;
    });
  }

  void _updateSearchQuery() {
    setState(() {
      _searchQuery = _searchController.text;
      _filterStations();
    });
  }

  Future<void> _fetchStations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Исправленный URL с указанием протокола http
      final response = await http.get(
        Uri.parse('http://192.168.31.215:5000/api/stations'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is Map && responseData.containsKey('stations')) {
          final List<dynamic> stationsData = responseData['stations'];
          setState(() {
            _allStations = stationsData.map((station) {
              // Добавляем дефолтные тарифы, если их нет в ответе
              station['pricing'] = station['pricing'] ?? {
                'peak': 5.50,
                'off_peak': 3.20,
              };
              return ChargingStation.fromMap(station);
            }).toList();
            _filterStations();
            _isLoading = false;
          });
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception(
            'Failed to load stations. Status code: ${response.statusCode}');
      }
    } catch (e) {
      Fluttertoast.showToast(
          msg: "Не удалось загрузить данные станций",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0
      );

      setState(() {
        _isLoading = false;
      });
      _loadDemoStations();
    }
  }

  void _loadDemoStations() {
    final demoStations = [
      {
        'id': 1,
        'name': 'Tesla Supercharger V3',
        'address': 'Караванная ул., 1\nСанкт-Петербург',
        'latitude': '59.9311',
        'longitude': '30.3609',
        'connector_type': 'Type 2',
        'current_type': 'AC',
        'power': 250.0,
        'status': 'active',
        'photo_url': 'https://www.galleryk.ru/upload/iblock/29c/img_2864.jpg',
        'tariff_id': 1,
        'pricing': {'peak': 5.50, 'off_peak': 3.20},
      },
      {
        'id': 2,
        'name': 'IONITY Premium',
        'address': 'Пулковское ш., 25\nСанкт-Петербург',
        'latitude': '59.8003',
        'longitude': '30.3178',
        'connector_type': 'CSS Combo 2',
        'current_type': 'DC',
        'power': 350.0,
        'status': 'active',
        'photo_url': '', //''https://avatars.mds.yandex.net/get-altay/14110197/2a000001941ef50534d203d7c2307491be25/L_height',
        'tariff_id': 2,
        'pricing': {'peak': 7.80, 'off_peak': 5.50},
      },
    ];

    setState(() {
      _allStations = demoStations
          .map((station) => ChargingStation.fromMap(station))
          .toList();
      _filterStations();
    });
  }

  void _filterStations() {
    _filteredStations = _allStations.where((station) {
      final searchMatch = _searchQuery.isEmpty ||
          station.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          station.address.toLowerCase().contains(_searchQuery.toLowerCase());

      final powerMatch = station.power >= _minPower && station.power <= _maxPower;

      bool typeMatch = true;
      if (_selectedACTypes.isNotEmpty && station.currentType == 'AC') {
        typeMatch = _selectedACTypes.contains(station.connectorType);
      } else if (_selectedDCTypes.isNotEmpty && station.currentType == 'DC') {
        typeMatch = _selectedDCTypes.contains(station.connectorType);
      }

      return searchMatch && powerMatch && typeMatch;
    }).toList();
  }



  void _showFilterDialog(BuildContext context) {
    double tempMinPower = _minPower;
    double tempMaxPower = _maxPower;
    List<String> tempSelectedAC = List.from(_selectedACTypes);
    List<String> tempSelectedDC = List.from(_selectedDCTypes);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      'Фильтры',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Ползунок мощности
                  const Text(
                    'Диапазон мощности (кВт):',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  RangeSlider(
                    activeColor: Color(0xFF0D7CFF),
                    inactiveColor: Colors.grey,
                    values: RangeValues(tempMinPower, tempMaxPower),
                    min: 3,
                    max: 400,
                    divisions: 10,
                    labels: RangeLabels(
                      '${tempMinPower.round()} кВт',
                      '${tempMaxPower.round()} кВт',
                    ),
                    onChanged: (RangeValues values) {
                      setModalState(() {
                        tempMinPower = values.start;
                        tempMaxPower = values.end;
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${tempMinPower.round()} кВт'),
                      Text('${tempMaxPower.round()} кВт'),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Разъемы переменного тока
                  const Text(
                    'Типы разъемов (AC):',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['Type 1', 'Type 2', 'GB/T'].map((type) {
                      bool isSelected = tempSelectedAC.contains(type);
                      return FilterChip(
                        label: Text(type),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            if (selected) {
                              tempSelectedAC.add(type);
                            } else {
                              tempSelectedAC.remove(type);
                            }
                          });
                        },
                        selectedColor: const Color(0xFF0D7CFF),
                        backgroundColor: Colors.grey.shade200,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Разъемы постоянного тока
                  const Text(
                    'Типы разъемов (DC):',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['CSS Combo 1', 'CSS Combo 2', 'CHAdeMO', 'GB/T'].map((type) {
                      bool isSelected = tempSelectedDC.contains(type);
                      return FilterChip(
                        label: Text(type),
                        selected: isSelected,
                        onSelected: (selected) {
                          setModalState(() {
                            if (selected) {
                              tempSelectedDC.add(type);
                            } else {
                              tempSelectedDC.remove(type);
                            }
                          });
                        },
                        selectedColor: const Color(0xFF0D7CFF),
                        backgroundColor: Colors.grey.shade200,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),

                  // Кнопки действий
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: Colors.grey),
                          ),
                          onPressed: () {
                            setModalState(() {
                              tempMinPower = 3;
                              tempMaxPower = 400;
                              tempSelectedAC.clear();
                              tempSelectedDC.clear();
                            });
                          },
                          child: const Text(
                            'Сбросить',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF000000),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D7CFF),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: () {
                            setState(() {
                              _minPower = tempMinPower;
                              _maxPower = tempMaxPower;
                              _selectedACTypes
                                ..clear()
                                ..addAll(tempSelectedAC);
                              _selectedDCTypes
                                ..clear()
                                ..addAll(tempSelectedDC);
                              _filterStations();
                            });
                            Navigator.pop(context);
                          },
                          child: const Text(
                            'Применить',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    cursorColor: const Color(0xFF0D7CFF),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xFF0D7CFF),
                          width: 2,
                        ),
                      ),
                      hintText: 'Поиск',
                      hintStyle: const TextStyle(
                        fontSize: 18,
                        color: Color(0xFF616161),
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFF616161),
                      ),
                    ),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D7CFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.tune, color: Colors.white),
                    onPressed: () => _showFilterDialog(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(initialScreen: 'balance'),
                  ),
                );
              },
              child: Text(
                'Баланс: $_userBalance ₽',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF616161),
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        toolbarHeight: 100,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapkitFlutterApp(),
          ),

          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0D7CFF),
              ),
            )
          else if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchStations,
                      child: const Text('Повторить попытку'),
                    ),
                  ],
                ),
              ),
            )
          else
            DraggableScrollableSheet(
              initialChildSize: 0.45,
              minChildSize: 0.05,
              maxChildSize: 1,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26)],
                  ),
                  child: _filteredStations.isEmpty
                      ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          textAlign: TextAlign.center,
                          'Станций с заданными параметрами не найдено',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  )
                      : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Center(
                        child: Icon(
                          Icons.drag_handle,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ближайшие станции',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._filteredStations.map(
                            (station) => StationCard(
                          id: station.id.toString(),
                          name: station.name,
                          address: station.address,
                          latitude: station.latitude,
                          longitude: station.longitude,
                          connectorType: station.connectorType,
                          currentType: station.currentType,
                          power: station.power,
                          status: station.status,
                          photoUrl: station.photoUrl,
                          tariffId: station.tariffId,
                          onRoutePressed: (stationId) {
                            final homePageState = context.findAncestorStateOfType<_HomePageState>();
                            homePageState?._selectStationAndChangeTab(stationId);
                          },

                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

