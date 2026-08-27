import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import '../utils/resto_location.dart';

/// Titik yang dipakai saat resto belum punya lokasi: Monas.
///
/// Bukan (0,0), yang berada di laut lepas pantai Afrika — peta yang
/// membuka di sana terlihat rusak, dan orangnya harus menggeser
/// setengah dunia sebelum menemukan kotanya sendiri.
const _defaultCenter = LatLng(-6.175392, 106.827153);

/// Kolom lokasi resto berikut petanya.
///
/// Sebelumnya lokasinya cuma sepasang angka desimal. Angka itu benar,
/// tapi tidak bisa diperiksa: tidak ada yang bisa melihat "-6.914744,
/// 107.609810" lalu tahu itu resto miliknya atau bukan. Salah satu
/// digit — atau lintang dan bujur yang tertukar — baru ketahuan saat
/// pelanggan pertama tersesat.
///
/// Peta di sini menjawab satu pertanyaan yang tidak bisa dijawab angka:
/// apakah titiknya jatuh di tempat yang benar.
class RestoLocationField extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  final bool enabled;
  final bool busy;
  final VoidCallback onUseCurrent;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  /// Dipanggil setelah pin digeser di peta.
  final void Function(double lat, double lng) onPicked;

  const RestoLocationField({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.enabled,
    required this.busy,
    required this.onUseCurrent,
    required this.onPaste,
    required this.onClear,
    required this.onPicked,
  });

  bool get _hasPoint => latitude != null && longitude != null;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => _MapPickerScreen(
          initial: _hasPoint
              ? LatLng(latitude!, longitude!)
              : _defaultCenter,
          hasPoint: _hasPoint,
        ),
      ),
    );
    if (picked == null) return;
    onPicked(picked.latitude, picked.longitude);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: enabled
            ? MerchantPosTheme.surfaceOf(context)
            : MerchantPosTheme.softFillOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MerchantPosTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place_outlined,
                  size: 17, color: MerchantPosTheme.mutedOf(context)),
              const SizedBox(width: 7),
              const Text('Lokasi Merchant',
                  style:
                      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_hasPoint)
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('Buka'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => openInMaps(latitude!, longitude!),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Pratinjau petanya, bukan sekadar angkanya. Diketuk membuka
          // peta penuh untuk menggeser pin.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 150,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _MapView(
                    center: _hasPoint
                        ? LatLng(latitude!, longitude!)
                        : _defaultCenter,
                    // Pratinjau tidak bisa digeser sendiri: yang
                    // menggeser peta kecil di tengah formulir yang bisa
                    // digulir hampir selalu sedang bermaksud menggulir
                    // halamannya.
                    interactive: false,
                    marker: _hasPoint
                        ? LatLng(latitude!, longitude!)
                        : null,
                  ),
                  if (!_hasPoint)
                    Container(
                      color: Colors.black.withOpacity(0.45),
                      alignment: Alignment.center,
                      child: const Text(
                        'Belum ada titik lokasi',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (enabled)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(onTap: () => _openPicker(context)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _hasPoint
                ? '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}'
                : 'Customer belum bisa membuka lokasi merchant di peta.',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: _hasPoint ? FontWeight.w600 : FontWeight.normal,
              color: MerchantPosTheme.mutedOf(context),
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.push_pin_outlined, size: 16),
                    label: const Text('Pilih di Peta'),
                    style:
                        FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                    onPressed: () => _openPicker(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 16),
                    label: const Text('Lokasi Saya'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40)),
                    onPressed: busy ? null : onUseCurrent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.content_paste, size: 15),
                    label: const Text('Tempel koordinat'),
                    onPressed: busy ? null : onPaste,
                  ),
                ),
                if (_hasPoint)
                  TextButton.icon(
                    icon: const Icon(Icons.close, size: 15),
                    label: const Text('Hapus'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: onClear,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Peta OpenStreetMap.
///
/// Stateful, dan itu bukan pilihan gaya. `initialCenter` hanya dibaca
/// sekali saat petanya dibuat — sesudah itu, memberi nilai baru tidak
/// menggerakkan apa pun. Akibatnya pratinjau tetap memandang tempat
/// lama setelah pin dipindahkan, dan penandanya nyempil di pinggir
/// layar atau keluar sama sekali. Yang melihatnya wajar menyimpulkan
/// titiknya salah, padahal cuma kameranya yang tidak ikut pindah.
///
/// [MapController] yang menutupnya: tiap kali titiknya berubah,
/// kameranya digeser ke sana.
class _MapView extends StatefulWidget {
  final LatLng center;
  final bool interactive;
  final LatLng? marker;

  const _MapView({
    required this.center,
    this.interactive = true,
    this.marker,
  });

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  final _controller = MapController();

  /// Petanya sudah siap menerima perintah.
  ///
  /// Memanggil move() sebelum petanya terpasang melempar galat. Titik
  /// yang datang lebih dulu — dan itu yang biasa terjadi, karena data
  /// restonya dimuat sebelum layarnya selesai digambar — disimpan di
  /// sini, lalu dipakai begitu petanya siap.
  bool _ready = false;

  @override
  void didUpdateWidget(_MapView old) {
    super.didUpdateWidget(old);
    if (old.center != widget.center) _recenter();
  }

  void _recenter() {
    if (!_ready) return;
    _controller.move(widget.center, _controller.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: 16,
        onMapReady: () {
          _ready = true;
          // Titik yang sudah berubah sebelum petanya siap tetap
          // terkejar di sini.
          if (_controller.camera.center != widget.center) _recenter();
        },
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // Wajib oleh ketentuan pemakaian ubin OpenStreetMap: pemakai
          // harus bisa dikenali. Tanpa ini permintaannya bisa ditolak
          // sewaktu-waktu, dan petanya berubah jadi kotak-kotak kosong
          // tanpa keterangan apa pun.
          userAgentPackageName: 'com.merchantpos.pos',
        ),
        if (widget.marker != null)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.marker!,
                width: 44,
                height: 44,
                // Ujung runcingnya yang menunjuk titiknya, bukan tengah
                // ikonnya: pin yang dipusatkan tepat di titik justru
                // menunjuk sekitar 20 meter di utaranya.
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on,
                    size: 40, color: Color(0xFFEF4444)),
              ),
            ],
          ),
        // Atribusi OpenStreetMap. Bukan hiasan — ini syarat lisensinya.
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

/// Layar penuh untuk menggeser pin.
///
/// Pin-nya diam di tengah layar dan petanya yang bergerak, bukan
/// sebaliknya. Menyeret pin kecil dengan jari berarti jarinya sendiri
/// menutupi titik yang sedang dibidik — persis bagian yang harus
/// dilihat. Cara ini dipakai hampir semua aplikasi peta, jadi juga
/// tidak perlu dipelajari lagi.
class _MapPickerScreen extends StatefulWidget {
  final LatLng initial;
  final bool hasPoint;

  const _MapPickerScreen({required this.initial, required this.hasPoint});

  @override
  State<_MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<_MapPickerScreen> {
  final _controller = MapController();
  late LatLng _center = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Lokasi Merchant')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: widget.initial,
              initialZoom: widget.hasPoint ? 17 : 13,
              onPositionChanged: (camera, _) =>
                  setState(() => _center = camera.center),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.merchantpos.pos',
              ),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // Pin yang diam di tengah. Diangkat setengah tingginya supaya
          // ujung runcingnya — bukan tengah ikonnya — yang menunjuk
          // titiknya.
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -19),
                child: const Icon(Icons.location_on,
                    size: 44, color: Color(0xFFEF4444)),
              ),
            ),
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Geser peta sampai pin tepat di lokasi merchant',
                      style: TextStyle(
                          fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_center.latitude.toStringAsFixed(6)}, '
                      '${_center.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _center),
                      child: const Text('Pakai Titik Ini'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
