import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dua Merchant-POS berjajar di Recent Apps.
///
/// taskAffinity kosong berarti activity-nya tidak berkerabat dengan task
/// mana pun — termasuk task-nya sendiri. Apa pun yang membukanya dengan
/// FLAG_ACTIVITY_NEW_TASK, dan notifikasi selalu begitu, ditaruh Android
/// di task baru alih-alih memakai yang sudah ada.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('tidak memakai taskAffinity kosong', () {
    expect(manifest, isNot(contains('android:taskAffinity=""')));
  });

  test('memakai singleTask, bukan singleTop', () {
    // singleTop hanya mencegah tumpukan ganda di dalam satu task,
    // sementara masalahnya justru task keduanya.
    expect(manifest, contains('android:launchMode="singleTask"'));
  });

  test('hanya ada satu activity peluncur', () {
    // Dua entri LAUNCHER juga menghasilkan dua ikon dan dua task.
    expect('android.intent.category.LAUNCHER'.allMatches(manifest).length, 1);
  });
}
