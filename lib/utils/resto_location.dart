import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Titik lokasi resto beserta alamat yang terbaca dari titik itu.
class RestoPoint {
  final double latitude;
  final double longitude;

  /// Alamat hasil pembacaan balik koordinat. Selalu boleh disunting —
  /// alamat dari peta hampir selalu benar sampai tingkat jalan, tapi
  /// nyaris tidak pernah menyebut "ruko blok C nomor 4", dan justru
  /// bagian itulah yang dicari orang yang mau datang.
  final String? address;

  const RestoPoint({required this.latitude, required this.longitude, this.address});

  @override
  String toString() => '$latitude, $longitude';
}

/// Kegagalan yang perlu diceritakan ke pemakainya apa adanya.
class LocationFailure implements Exception {
  final String message;
  const LocationFailure(this.message);

  @override
  String toString() => message;
}

/// Mengambil posisi perangkat sekarang.
///
/// Dipakai dari layar Info Resto, di mana yang mengisinya biasanya
/// sedang berdiri di restonya sendiri — jauh lebih cepat daripada
/// menggeser peta atau mengetik koordinat.
Future<Position> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationFailure(
        'Layanan lokasi HP sedang mati. Nyalakan GPS lalu coba lagi.');
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) {
    throw const LocationFailure('Izin lokasi ditolak.');
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationFailure(
        'Izin lokasi diblokir permanen. Aktifkan lewat Setelan HP > Aplikasi > '
        'MerchantPOS > Izin > Lokasi.');
  }

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}

/// Membaca alamat dari koordinat lewat Nominatim (OpenStreetMap).
///
/// Dipilih karena gratis dan tanpa kunci API — Google Geocoding menagih
/// per permintaan dan menuntut kartu kredit terdaftar, padahal yang
/// dibutuhkan di sini cuma sekali isi saat resto didaftarkan.
///
/// Nominatim mewajibkan User-Agent yang menyebut aplikasinya; permintaan
/// tanpa itu diblokir. Alamatnya boleh kosong — koordinatnya tetap
/// berguna, dan pemakainya bisa mengetik alamatnya sendiri.
Future<String?> addressOf(double latitude, double longitude) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
    'lat': '$latitude',
    'lon': '$longitude',
    'format': 'jsonv2',
    'accept-language': 'id',
  });

  try {
    final response = await http
        .get(uri, headers: {'User-Agent': 'MerchantPOS/1.0 (aplikasi kasir resto)'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final display = data['display_name'] as String?;
    return (display == null || display.isEmpty) ? null : display;
  } catch (_) {
    // Offline atau layanannya sedang sibuk — koordinatnya tetap tersimpan.
    return null;
  }
}

/// Membuka titik resto di aplikasi peta.
///
/// Memakai tautan universal Google Maps, yang tidak butuh kunci API dan
/// tetap bekerja lewat peramban kalau aplikasi Maps-nya tidak terpasang.
Future<bool> openInMaps(double latitude, double longitude, {String? label}) {
  final uri = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': '$latitude,$longitude',
    if (label != null && label.isNotEmpty) 'query_place_id': '',
  });
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Membaca koordinat dari teks yang ditempel orang.
///
/// Menerima "-6.2,106.8" maupun tautan Google Maps yang memuat "@lat,lng"
/// atau "q=lat,lng" — itulah tiga bentuk yang benar-benar dipakai orang
/// saat diminta "kirim lokasinya".
RestoPoint? parseCoordinates(String raw) {
  final match = RegExp(r'(-?\d{1,3}\.\d+)[,\s]+(-?\d{1,3}\.\d+)').firstMatch(raw);
  if (match == null) return null;

  final lat = double.tryParse(match.group(1)!);
  final lng = double.tryParse(match.group(2)!);
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

  return RestoPoint(latitude: lat, longitude: lng);
}
