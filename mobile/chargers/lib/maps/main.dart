import 'dart:math' as math;

import 'package:chargers/maps/common/listeners/map_object_tap_listener.dart';
import 'package:chargers/maps/common/listeners/map_size_changed_listener.dart';
import 'package:chargers/maps/common/map/flutter_map_widget.dart';
import 'package:chargers/maps/common/utils/extension_utils.dart';
import 'package:chargers/maps/common/utils/snackbar.dart';
import 'package:chargers/maps/data/geometry_provider.dart';
import 'package:chargers/maps/listeners/cluster_listener.dart';
import 'package:chargers/maps/listeners/cluster_tap_listener.dart';
import 'package:chargers/maps/services/station_service.dart';
import 'package:chargers/maps/widgets/charging_station_screen.dart';
import 'package:chargers/maps/widgets/cluster_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';

import 'package:yandex_maps_mapkit/image.dart' as image_provider;
import 'package:yandex_maps_mapkit/init.dart' as init;
import 'package:yandex_maps_mapkit/mapkit.dart' as mapkit;
import 'package:yandex_maps_mapkit/ui_view.dart';
import 'package:flutter/services.dart';

import '../objects/stations.dart';




class MapkitFlutterApp extends StatefulWidget {
  const MapkitFlutterApp({super.key});

  @override
  State<MapkitFlutterApp> createState() => _MapkitFlutterAppState();
}

class _MapkitFlutterAppState extends State<MapkitFlutterApp> {


  static const _clusterRadius = 60.0;
  static const _clusterMinZoom = 15;
  final StationService _stationService = StationService();
  List<ChargingStation> _stations = [];
  mapkit.PlacemarkMapObject? _userLocationPlacemark;
  bool _isLocationLoading = false;

  final _indexToPlacemarkType = <int, PlacemarkType>{};

  final _placemarkTypeToImageProvider =
      <PlacemarkType, image_provider.ImageProvider>{
    PlacemarkType.green: image_provider.ImageProvider.fromImageProvider(
      const AssetImage("assets/station_green.png"),
    ),
    PlacemarkType.yellow: image_provider.ImageProvider.fromImageProvider(
      const AssetImage("assets/station_yellow.png"),
    ),
    PlacemarkType.blue: image_provider.ImageProvider.fromImageProvider(
      const AssetImage("assets/station_blue.png"),
    ),
  };

  late final mapkit.MapObjectCollection _mapObjectCollection;
  late final mapkit.ClusterizedPlacemarkCollection _clusterizedCollection;

  late final _mapWindowSizeChangedListener = MapSizeChangedListenerImpl(
    onMapWindowSizeChange: (_, __, ___) => _updateFocusRect(),
  );

  late final _placemarkTapListener = MapObjectTapListenerImpl(
    onMapObjectTapped: (mapObject, _) {
      final placemark = mapObject.castOrNull<mapkit.PlacemarkMapObject>();
      if (placemark != null) {
        final index = placemark.userData as int;
        if (index >= 0 && index < _stations.length) {
          final station = _stations[index];
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChargingStationScreen(
                station: station,
                onBack: () => Navigator.pop(context),
              ),
            ),
          );
        }
      }
      return true;
    },
  );
  late final _clusterTapListener = ClusterTapListenerImpl(
    onClusterTapCallback: (cluster) {
      showSnackBar(context, "Clicked the ClusterTapListenerImpl");
      return true;
    },
  );

  late final _clusterListener = ClusterListenerImpl(
    onClusterAddedCallback: (cluster) {
      final placemarkTypes = cluster.placemarks
          .map((item) => _indexToPlacemarkType[item.userData])
          .whereType<PlacemarkType>()
          .toList();

      // Sets each cluster appearance using the custom view
      // that shows a cluster's pins
      cluster.appearance
        ..setView(
          ViewProvider(
            builder: () => ClusterWidget(placemarkTypes: placemarkTypes),
          ),
        )
        ..zIndex = 100.0;

      cluster.addClusterTapListener(_clusterTapListener);
    },
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 500), () {
      _loadStations();
    });
  }

  Future<void> _loadStations() async {
    try {
      final stations = await _stationService.getStations();
      if (stations.isEmpty) {
        showSnackBar(context, "Не найдено ни одной станции");
        return;
      }

      setState(() {
        _stations = stations;
      });

      if (_clusterizedCollection != null) {
        _updateClusterizedPlacemarks();
      }
    } catch (e) {

      debugPrint("Ошибка загрузки станций: $e");
    }
  }

  void _updateClusterizedPlacemarks() {
    if (_clusterizedCollection == null) return;

    _clusterizedCollection.clear();
    _indexToPlacemarkType.clear();

    for (final (index, station) in _stations.indexed) {
      final type = _getPlacemarkTypeForStation(station);
      final imageProvider = _placemarkTypeToImageProvider[type];

      if (imageProvider != null) {
        final point = mapkit.Point(
          latitude: double.parse(station.latitude),
          longitude: double.parse(station.longitude),
        );

        _clusterizedCollection.addPlacemark()
          ..geometry = point
          ..userData = index
          ..setIcon(imageProvider)
          ..setIconStyle(
            const mapkit.IconStyle(
              anchor: math.Point(0.5, 1.0),
              scale: 2.8,
            ),
          )
          ..draggable = true
          ..addTapListener(_placemarkTapListener);

        _indexToPlacemarkType[index] = type;
      }
    }

    // Не забываем вызвать clusterPlacemarks!
    _clusterizedCollection.clusterPlacemarks(
      clusterRadius: _clusterRadius,
      minZoom: _clusterMinZoom,
    );
  }

  PlacemarkType _getPlacemarkTypeForStation(ChargingStation station) {
    // Логика определения типа маркера на основе данных станции
    switch (station.status.toLowerCase()) {
      case 'free':
        return station.power > 50 ? PlacemarkType.blue : PlacemarkType.green;
      case 'busy':
        return PlacemarkType.yellow;
      case 'reserved':
        return PlacemarkType.yellow;
      default:
        return PlacemarkType.green;
    }
  }

  mapkit.MapWindow? _mapWindow;


  Future<void> _centerOnMyLocation() async {
    if (_isLocationLoading) return;

    setState(() => _isLocationLoading = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        showSnackBar(context, "Пожалуйста, включите геолокацию");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          showSnackBar(context, "Доступ к геолокации запрещен");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        showSnackBar(context, "Доступ к геолокации запрещен навсегда");
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      // Обновляем или создаем маркер местоположения
      final point = mapkit.Point(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (_userLocationPlacemark == null) {
        _userLocationPlacemark = _mapObjectCollection.addPlacemark()
          ..geometry = point
          ..setIcon(
            image_provider.ImageProvider.fromImageProvider(
              const AssetImage("assets/user.png"), // Ваш файл с синей точкой
            ),
          )
          ..setIconStyle(
            const mapkit.IconStyle(
              anchor: math.Point(0.5, 0.5),
              scale: 0.1,
              zIndex: 1000,
            ),
          );
      } else {
        _userLocationPlacemark!.geometry = point;
      }

      // Центрируем карту на местоположении
      _mapWindow?.map.moveWithAnimation(
        mapkit.CameraPosition(
          point,
          zoom: 15.0,
          azimuth: 0.0,
          tilt: 0.0,
        ),
        const mapkit.Animation(mapkit.AnimationType.Smooth, duration: 0.5),
      );

    } on PlatformException catch (e) {
      showSnackBar(context, "Ошибка получения локации: ${e.message}");
    } catch (e) {
      showSnackBar(context, "Ошибка: $e");
    } finally {
      setState(() => _isLocationLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            FlutterMapWidget(onMapCreated: _createMapObjects),
            Positioned(
              top: 10,
              right: 10,
              child: FloatingActionButton(
                onPressed: _centerOnMyLocation,
                mini: true,
                backgroundColor: Theme.of(context).primaryColor,
                child: const Icon(Icons.my_location),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createMapObjects(mapkit.MapWindow mapWindow) {
    _mapWindow = mapWindow;

    mapWindow.addSizeChangedListener(_mapWindowSizeChangedListener);

    // Используем первую станцию как стартовую позицию или дефолтную
    final startPoint = _stations.isNotEmpty
        ? mapkit.Point(
      latitude: 59.924377,
      longitude: 30.307961,
    )
        : GeometryProvider.startPosition.target;

    mapWindow.map.move(mapkit.CameraPosition(
      startPoint,
      zoom: 11.0,
      azimuth: 0.0,
      tilt: 0.0,
    ));

    _mapObjectCollection = mapWindow.map.mapObjects.addCollection();
    _clusterizedCollection = _mapObjectCollection
        .addClusterizedPlacemarkCollection(_clusterListener);

    _updateClusterizedPlacemarks(); // Используем этот метод вместо _addClusterizedPlacemarks
  }



  void _addClusterizedPlacemarks(
    mapkit.ClusterizedPlacemarkCollection clusterizedCollection,
  ) {
    for (final (index, point) in GeometryProvider.clusterizedPoints.indexed) {
      final type = PlacemarkType.values.random();
      final imageProvider = _placemarkTypeToImageProvider[type];

      if (imageProvider != null) {
        clusterizedCollection.addPlacemark()
          ..geometry = point
          ..userData = index
          ..setIcon(imageProvider)
          ..setIconStyle(
            const mapkit.IconStyle(
              anchor: math.Point(0.5, 1.0),
              scale: 2.8,
              zIndex: 100,
              rotationType: mapkit.RotationType.NoRotation,
            ),
          )
          // If we want to make placemarks draggable, we should call
          // clusterizedCollection.clusterPlacemarks on onMapObjectDragEnd
          ..draggable = true
          ..addTapListener(_placemarkTapListener);

        _indexToPlacemarkType[index] = type;
      }
    }

    clusterizedCollection.clusterPlacemarks(
      clusterRadius: _clusterRadius,
      minZoom: _clusterMinZoom,
    );
  }

  void _updateFocusRect() {
    const horizontalMargin = 0.0;
    const verticalMargin = 0.0;

    _mapWindow?.let((it) {
      it.focusRect = mapkit.ScreenRect(
        const mapkit.ScreenPoint(
          x: horizontalMargin,
          y: verticalMargin,
        ),
        mapkit.ScreenPoint(
          x: it.width() - horizontalMargin,
          y: it.height() - verticalMargin,
        ),
      );
    });
  }
}
