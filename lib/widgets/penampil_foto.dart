import 'package:flutter/material.dart';

import '../utils/gambar_base64.dart';

/// Membuka foto selayar penuh, bisa digeser dan dizoom.
///
/// Foto ulasan tampil sebagai petak kecil 82 piksel — cukup untuk tahu
/// ada fotonya, tidak cukup untuk melihat apa isinya. Yang membuka
/// halaman ulasan justru sedang mencari itu: makanannya benar-benar
/// seperti apa.
Future<void> lihatFoto(
  BuildContext context,
  List<String> foto, {
  int mulai = 0,
}) {
  if (foto.isEmpty) return Future.value();
  return Navigator.of(context).push(
    // Rute penuh, bukan dialog: foto yang dizoom di dalam kotak dialog
    // tetap terpotong kotaknya, dan yang mau melihat detail justru
    // butuh seluruh layarnya.
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PenampilFoto(foto: foto, mulai: mulai),
    ),
  );
}

class _PenampilFoto extends StatefulWidget {
  final List<String> foto;
  final int mulai;

  const _PenampilFoto({required this.foto, required this.mulai});

  @override
  State<_PenampilFoto> createState() => _PenampilFotoState();
}

class _PenampilFotoState extends State<_PenampilFoto> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.mulai;
    _controller = PageController(initialPage: widget.mulai);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Hitam, bukan warna tema: yang dilihat foto orang lain, dan latar
      // gelap membuat mata berhenti membandingkannya dengan halaman di
      // belakangnya.
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: widget.foto.length > 1
            ? Text('${_index + 1} dari ${widget.foto.length}',
                style: const TextStyle(fontSize: 15))
            : null,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.foto.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.memory(
              byteGambar(widget.foto[i]),
              fit: BoxFit.contain,
              // Satu foto rusak tidak boleh mengosongkan seluruh
              // penampilnya — yang lain masih bisa dilihat.
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white38,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
