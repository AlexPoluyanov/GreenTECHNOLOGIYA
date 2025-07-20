import 'package:yandex_maps_mapkit/mapkit.dart';

final class GeometryProvider {
  static final _generatedList = List.generate(400, (i) => i + 200.0);

  static const startPosition = CameraPosition(
    Point(latitude: 59.957270, longitude: 30.308176),
    zoom: 14.0,
    azimuth: 0.0,
    tilt: 0.0,
  );

  static List<Point> clusterizedPoints = [
    (59.958632, 30.303482),
    (59.935535, 30.326926),
    (59.938961, 30.328576),
    (59.938152, 30.336384),
    (59.934600, 30.335049),
    (59.938386, 30.329092),
    (59.938495, 30.330557),
    (59.938854, 30.332325),
    (59.937930, 30.333767),
    (59.937766, 30.335208),
    (59.938203, 30.334316),
    (59.938607, 30.337340),
    (59.937988, 30.337596),
    (59.938168, 30.338533),
    (59.938780, 30.339794),
    (59.939095, 30.338655),
    (59.939815, 30.337967),
    (59.939365, 30.340293),
    (59.935220, 30.333730),
    (59.935792, 30.335223),
    (59.935814, 30.332945),
  ].map((point) => Point(latitude: point.$1, longitude: point.$2)).toList();
}
