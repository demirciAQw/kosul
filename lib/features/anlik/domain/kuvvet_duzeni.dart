// Kuvvet düzeni (saf Dart, rastgelelik yok): bağlar çeker, düğümler iter,
// her anlık sarmaldaki yerine bir yayla bağlıdır.
//
// "Düzen ↔ Bağ" kaydırıcısı [bag] (0…1): 0'da yay güçlü, tarih düzeni korunur;
// 1'de yay zayıf, bağlar şekli bozar. En fazla 300 adım. İtme sadece yakın
// düğümler arasında hesaplanır (ızgara), 2000 düğüme kadar hızlıdır.
// Hesap isolate içinde çalıştırılır (grafik ekranı).
import 'dart:math' as math;

import 'graf.dart';

/// Döner: düğüm kimliği → son konum. Aynı girdi her zaman aynı sonucu verir.
Map<String, ({double x, double y})> kuvvetDuzeni(GrafVerisi g, {double bag = 0.3, int adim = 300}) {
  final n = g.dugumler.length;
  if (n == 0) return const {};
  final indeks = {for (var i = 0; i < n; i++) g.dugumler[i].id: i};
  final x = [for (final d in g.dugumler) d.x];
  final y = [for (final d in g.dugumler) d.y];
  final vx = List<double>.filled(n, 0), vy = List<double>.filled(n, 0);
  final kenarlar = [
    for (final k in g.kenarlar)
      if (indeks[k.a] != null && indeks[k.b] != null && indeks[k.a] != indeks[k.b])
        (indeks[k.a]!, indeks[k.b]!, k.agirlik),
  ];

  final s = bag.clamp(0.0, 1.0);
  final yay = 0.12 * (1 - s) + 0.004; // sarmal yerine çekiş
  final cekim = 0.01 + 0.05 * s; // bağların çekişi
  const itme = 900.0;
  const menzil = 60.0; // bu uzaklıktan sonra itme yok
  const idealUzunluk = 30.0;
  const surtunme = 0.82;

  for (var t = 0; t < adim; t++) {
    final soguma = 1 - t / adim; // adım büyüklüğü giderek küçülür
    final fx = List<double>.filled(n, 0), fy = List<double>.filled(n, 0);

    // İtme: ızgara hücrelerinde sadece komşu hücreler.
    final izgara = <int, List<int>>{};
    int hucre(double v) => (v / menzil).floor();
    int anahtar(int a, int b) => a * 100003 + b;
    for (var i = 0; i < n; i++) {
      (izgara[anahtar(hucre(x[i]), hucre(y[i]))] ??= []).add(i);
    }
    for (var i = 0; i < n; i++) {
      final hx = hucre(x[i]), hy = hucre(y[i]);
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (final j in izgara[anahtar(hx + dx, hy + dy)] ?? const <int>[]) {
            if (j <= i) continue;
            var ddx = x[i] - x[j], ddy = y[i] - y[j];
            var d2 = ddx * ddx + ddy * ddy;
            if (d2 > menzil * menzil) continue;
            if (d2 < 0.01) {
              // Üst üste: sıraya göre sabit bir yöne ayır (rastgele değil).
              ddx = math.cos(i * 2.399);
              ddy = math.sin(i * 2.399);
              d2 = 1;
            }
            final kuvvet = itme / d2;
            final d = math.sqrt(d2);
            fx[i] += kuvvet * ddx / d;
            fy[i] += kuvvet * ddy / d;
            fx[j] -= kuvvet * ddx / d;
            fy[j] -= kuvvet * ddy / d;
          }
        }
      }
    }

    // Bağlar: ideal uzunluğa çeker.
    for (final (a, b, w) in kenarlar) {
      final ddx = x[b] - x[a], ddy = y[b] - y[a];
      final d = math.sqrt(ddx * ddx + ddy * ddy) + 1e-6;
      final k = cekim * w * (d - idealUzunluk);
      fx[a] += k * ddx / d;
      fy[a] += k * ddy / d;
      fx[b] -= k * ddx / d;
      fy[b] -= k * ddy / d;
    }

    // Yay: sabit düğümler başlangıç yerine; serbestler (etiket) merkeze çok hafif.
    for (var i = 0; i < n; i++) {
      final d = g.dugumler[i];
      final k = d.sabit ? yay : 0.002;
      final hx = d.sabit ? d.x : 0.0, hy = d.sabit ? d.y : 0.0;
      fx[i] += k * (hx - x[i]);
      fy[i] += k * (hy - y[i]);
    }

    for (var i = 0; i < n; i++) {
      vx[i] = (vx[i] + fx[i]) * surtunme;
      vy[i] = (vy[i] + fy[i]) * surtunme;
      final hiz = math.sqrt(vx[i] * vx[i] + vy[i] * vy[i]);
      final sinir = 20 * soguma + 0.5;
      if (hiz > sinir) {
        vx[i] *= sinir / hiz;
        vy[i] *= sinir / hiz;
      }
      x[i] += vx[i];
      y[i] += vy[i];
    }
  }
  return {for (var i = 0; i < n; i++) g.dugumler[i].id: (x: x[i], y: y[i])};
}
