// Yerel ağda koç sunucusunu bulur.
//
// Önce mDNS ile "_koc._tcp.local" sorulur (bilgisayar kendini duyurur). Bazı
// telefonlar ya da modemler bunu engeller; o zaman telefonun kendi ağındaki
// adresler tek tek kısa bir "/merhaba" isteğiyle denenir. İkisi de olmazsa
// kullanıcı IP'yi elle yazar.
import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import '../domain/koc_baglantisi.dart';
import 'koc_istemcisi.dart';

class KocBulucu {
  KocBulucu(this._istemci);
  final KocIstemcisi _istemci;

  /// Bulunan sunucular, bulundukça gelir (aynı sunucu bir kez).
  Stream<KocSunucuBilgisi> bul({bool tara = true}) async* {
    final gorulen = <String>{};
    for (final a in await _mdns()) {
      final s = await _istemci.merhaba(a.adres, a.port);
      if (s != null && gorulen.add(s.sunucuId)) yield s;
    }
    if (!tara || gorulen.isNotEmpty) return;
    await for (final s in _tara()) {
      if (gorulen.add(s.sunucuId)) yield s;
    }
  }

  /// Eşli sunucunun IP'si değiştiyse (modem yeni adres verdiyse) yeni adresi.
  Future<KocSunucuBilgisi?> yeniden(String sunucuId, {bool tara = false}) async {
    await for (final s in bul(tara: tara)) {
      if (s.sunucuId == sunucuId) return s;
    }
    return null;
  }

  Future<List<({String adres, int port})>> _mdns() async {
    final sonuc = <({String adres, int port})>[];
    final client = MDnsClient();
    try {
      await client.start().timeout(const Duration(seconds: 2));
      const sure = Duration(seconds: 2);
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(kocServisAdi),
        timeout: sure,
      )) {
        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
          timeout: sure,
        )) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: sure,
          )) {
            sonuc.add((adres: ip.address.address, port: srv.port));
          }
        }
      }
    } on Object {
      // mDNS bu ağda ya da bu telefonda çalışmıyor; tarama devralır.
    } finally {
      client.stop();
    }
    return sonuc;
  }

  Stream<KocSunucuBilgisi> _tara() async* {
    final adresler = <String>[];
    try {
      for (final arayuz in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in arayuz.addresses) {
          adresler.addAll(taranacakAdresler(a.address));
        }
      }
    } on SocketException {
      return;
    }
    const grup = 48;
    for (var i = 0; i < adresler.length; i += grup) {
      final parca = adresler.skip(i).take(grup);
      final bulunan = await Future.wait([
        for (final a in parca) _istemci.merhaba(a, kocVarsayilanPort, sure: const Duration(milliseconds: 800)),
      ]);
      for (final s in bulunan) {
        if (s != null) yield s;
      }
    }
  }
}
