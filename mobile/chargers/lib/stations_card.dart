import 'package:chargers/station_sceen/station_screen.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class StationCard extends StatelessWidget {
  final String id;
  final String name;
  final String address;
  final String latitude;
  final String longitude;
  final String connectorType;
  final String currentType;
  final double power;
  final String status;
  final String photoUrl;
  final int tariffId;
  final Function(int)? onRoutePressed;

  const StationCard({
    super.key,
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
    this.onRoutePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Фото станции
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: CachedNetworkImage(
              imageUrl: photoUrl,
              height: 150,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder:
                  (context, url) => Container(
                    height: 150,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              errorWidget:
                  (context, url, error) => Container(
                    height: 150,
                    color: Colors.grey[200],
                    child: const Center(
                      child: FittedBox(
                        child: Icon(Icons.ev_station, color: Colors.grey),
                      ),
                    ),
                  ),
            ),
          ),

          // Информация
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Название и расстояние
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Container(
                    //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    //   decoration: BoxDecoration(
                    //     color: Colors.green[50],
                    //     borderRadius: BorderRadius.circular(12),
                    //   ),
                    //   child: Text(
                    //     distance,
                    //     style: TextStyle(
                    //       color: Colors.green[800],
                    //       fontSize: 12,
                    //     ),
                    //   ),
                    // ),
                  ],
                ),

                const SizedBox(height: 8),

                // Адрес (может занимать несколько строк)
                Text(
                  address,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 12),

                // Характеристики (располагаем в столбик)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFeatureRow(
                      Icons.electric_bolt,
                      'Тип: ${connectorType}',
                    ),
                    const SizedBox(height: 6),
                    _buildFeatureRow(Icons.bolt, 'Мощность: $power'),
                    const SizedBox(height: 6),
                    _buildFeatureRow(
                      Icons.power,
                      'Статус: $status',

                      color: () {
                        if (status == "active") {
                          return Colors.green;
                        } else {
                          return Colors.red;
                        }
                      }(),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Кнопка маршрута
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF0D7CFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      if (onRoutePressed != null) {
                        onRoutePressed!(int.tryParse(id) ?? 0);
                      } else {
                        // Старая реализация как fallback
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => StationsScreen(
                                  selectedStationId: int.tryParse(id),
                                ),
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'Построить маршрут',
                      style: TextStyle(fontSize: 14, color: Colors.white),
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

  Widget _buildFeatureRow(IconData icon, String text, {Color? color}) {
    if (text.contains('Статус')) {
      if (text.contains('free')) {
        text = 'Статус: Свободна';
        color = Colors.green;
      } else if (text.contains('busy')) {
        text = 'Статус: Занята';
        color = Colors.red;
      } else if (text.contains('reserved')) {
        text = 'Статус: Забронирована';
        color = Colors.red;
      } else {
        text = text;
      }
    }
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? Colors.blue[600]),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: color ?? Colors.black87),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
