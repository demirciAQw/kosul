// Ayarlar > Bilgisayarla eşle.
//
// Eşli değilken: koçu bul (ya da IP'yi elle yaz), bilgisayarı seç, terminalde
// çıkan 6 haneli kodu yaz. Eşliyken: son eşitleme, "Şimdi eşitle" ve
// "Eşlemeyi kaldır".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/palette.dart';
import '../../../app/widgets/tone_icon.dart';
import '../../../core/utils/formatters.dart';
import '../data/koc_istemcisi.dart';
import '../domain/koc_baglantisi.dart';
import '../sync_providers.dart';

const _cihazAdi = 'Koçum telefonu';

class EslemeEkrani extends ConsumerWidget {
  const EslemeEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esleme = ref.watch(kocEslemesiProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bilgisayarla eşle')),
      body: esleme.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Okunamadı: $e')),
        data: (e) => e == null ? const _Eslestir() : _Esli(esleme: e),
      ),
    );
  }
}

/// Eşliyken: durum ve düğmeler.
class _Esli extends ConsumerStatefulWidget {
  const _Esli({required this.esleme});
  final KocEslemesi esleme;

  @override
  ConsumerState<_Esli> createState() => _EsliState();
}

class _EsliState extends ConsumerState<_Esli> {
  bool _calisiyor = false;

  Future<void> _esitle() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _calisiyor = true);
    final d = await ref.read(kocEsitleyiciProvider).dene(zorla: true);
    if (!mounted) return;
    setState(() => _calisiyor = false);
    messenger.showSnackBar(SnackBar(content: Text(d?.sonHata ?? 'Eşitlendi.')));
  }

  Future<void> _kaldir() async {
    final e = widget.esleme;
    final evet = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eşleme kaldırılsın mı?'),
        content: Text('${e.sunucuAdi} artık yedek almaz. Bilgisayardaki yedekler silinmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaldır')),
        ],
      ),
    );
    if (evet != true || !mounted) return;
    setState(() => _calisiyor = true);
    // Bilgisayara ulaşılamasa da telefondaki anahtar silinir; bilgisayarda
    // `koc eslemeler --sil` ile kaldırılabilir.
    var bilgisayarda = true;
    try {
      await ref.read(kocIstemcisiProvider).eslemeyiKaldir(e.adres, e.port, e.anahtar);
    } on KocHatasi {
      bilgisayarda = false;
    }
    await ref.read(eslemeDeposuProvider).eslemeyiSil();
    ref.invalidate(kocEslemesiProvider);
    ref.invalidate(esitlemeDurumuProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bilgisayarda
              ? 'Eşleme kaldırıldı.'
              : 'Telefonda kaldırıldı. Bilgisayara ulaşılamadı; orada "koc eslemeler --sil" ile kaldırabilirsin.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.esleme;
    final durum = ref.watch(esitlemeDurumuProvider).value ?? const EsitlemeDurumu();
    final theme = Theme.of(context);
    final son = durum.sonBasari;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const ToneIcon(Icons.computer_rounded, color: KocumColors.green),
            title: Text(e.sunucuAdi),
            subtitle: Text('${e.adres}:${e.port}'),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Son eşitleme', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(son == null ? 'Henüz yok' : formatShortDate(son.toLocal())),
                if (durum.sonHata != null) ...[
                  const SizedBox(height: 8),
                  Text(durum.sonHata!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 12),
                Text(
                  'Telefon, aynı Wi-Fi\'deyken uygulama açılınca ve bir çalışma oturumu bitince '
                  'yedeğini (fotoğrafsız) bilgisayara kendiliğinden gönderir. Veri değişmediyse '
                  'yalnızca kısa bir özet gider.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _calisiyor ? null : _esitle,
          icon: _calisiyor
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync_rounded),
          label: const Text('Şimdi eşitle'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _calisiyor ? null : _kaldir,
          icon: const Icon(Icons.link_off_rounded),
          label: const Text('Eşlemeyi kaldır'),
        ),
      ],
    );
  }
}

/// Eşli değilken: bul, seç, kodu yaz.
class _Eslestir extends ConsumerStatefulWidget {
  const _Eslestir();

  @override
  ConsumerState<_Eslestir> createState() => _EslestirState();
}

class _EslestirState extends ConsumerState<_Eslestir> {
  final _ip = TextEditingController();
  final _kod = TextEditingController();
  final _bulunanlar = <KocSunucuBilgisi>[];
  StreamSubscription<KocSunucuBilgisi>? _arama;
  bool _ariyor = false;
  bool _calisiyor = false;
  bool _aramaBitti = false;
  KocSunucuBilgisi? _secili;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _bul();
  }

  @override
  void dispose() {
    _arama?.cancel();
    _ip.dispose();
    _kod.dispose();
    super.dispose();
  }

  void _bul() {
    _arama?.cancel();
    setState(() {
      _bulunanlar.clear();
      _ariyor = true;
      _aramaBitti = false;
      _hata = null;
    });
    _arama = ref
        .read(kocBulucuProvider)
        .bul()
        .listen(
          (s) => setState(() => _bulunanlar.add(s)),
          onDone: () {
            if (mounted) {
              setState(() {
                _ariyor = false;
                _aramaBitti = true;
              });
            }
          },
        );
  }

  Future<void> _elle() async {
    final a = adresCoz(_ip.text);
    if (a == null) {
      setState(() => _hata = 'Adres anlaşılmadı. Örnek: 192.168.1.20');
      return;
    }
    setState(() {
      _calisiyor = true;
      _hata = null;
    });
    final s = await ref.read(kocIstemcisiProvider).merhaba(a.adres, a.port, sure: const Duration(seconds: 4));
    if (!mounted) return;
    setState(() => _calisiyor = false);
    if (s == null) {
      setState(() => _hata = '${a.adres} adresinde koç sunucusu yok. Bilgisayarda "koc sunucu" açık mı?');
      return;
    }
    await _sec(s);
  }

  /// Bilgisayar seçilince terminalde kod çıkar.
  Future<void> _sec(KocSunucuBilgisi s) async {
    final arama = _arama;
    if (arama != null) unawaited(arama.cancel());
    setState(() {
      _calisiyor = true;
      _hata = null;
      _ariyor = false;
    });
    try {
      await ref.read(kocIstemcisiProvider).esleBasla(s.adres, s.port, cihazAdi: _cihazAdi);
      if (!mounted) return;
      setState(() => _secili = s);
    } on KocHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  Future<void> _esle() async {
    final s = _secili;
    final kod = eslemeKodu(_kod.text);
    if (s == null) return;
    if (kod == null) {
      setState(() => _hata = 'Kod 6 rakam olmalı.');
      return;
    }
    setState(() {
      _calisiyor = true;
      _hata = null;
    });
    final depo = ref.read(eslemeDeposuProvider);
    try {
      final r = await ref
          .read(kocIstemcisiProvider)
          .esle(s.adres, s.port, kod: kod, cihazId: await depo.cihazId(), cihazAdi: _cihazAdi);
      await depo.eslemeKaydet(
        KocEslemesi(adres: s.adres, port: s.port, anahtar: r.anahtar, sunucuId: r.sunucuId, sunucuAdi: r.ad),
      );
      // Önceki eşlemeden kalan iz yeni bilgisayarda geçersiz.
      await depo.durumKaydet(const EsitlemeDurumu());
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      ref.invalidate(kocEslemesiProvider);
      ref.invalidate(esitlemeDurumuProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Eşlendi. İlk yedek gönderiliyor…')));
      unawaited(ref.read(kocEsitleyiciProvider).dene(zorla: true));
    } on KocHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secili = _secili;
    final hata = _hata;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (secili == null) ...[
          Text(
            'Bilgisayarda "koc sunucu" komutunu çalıştır. Telefon ve bilgisayar aynı Wi-Fi\'de olmalı; '
            'internet gerekmez.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Bulunan bilgisayarlar', style: theme.textTheme.titleSmall)),
              TextButton.icon(
                onPressed: _ariyor || _calisiyor ? null : _bul,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Yeniden ara'),
              ),
            ],
          ),
          if (_ariyor) const LinearProgressIndicator(),
          for (final s in _bulunanlar)
            Card(
              child: ListTile(
                leading: const ToneIcon(Icons.computer_rounded, color: KocumColors.blue),
                title: Text(s.ad),
                subtitle: Text('${s.adres}:${s.port}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _calisiyor ? null : () => _sec(s),
              ),
            ),
          if (_aramaBitti && _bulunanlar.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Bulunamadı. "koc sunucu" açık mı? Bilgisayarın güvenlik duvarı 8765 portunu engelliyor olabilir. '
                'Adresi elle de yazabilirsin; sunucu açılırken ekrana yazar.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          Text('IP adresini elle yaz', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ip,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: '192.168.1.20', border: OutlineInputBorder()),
                  onSubmitted: (_) => _elle(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(onPressed: _calisiyor ? null : _elle, child: const Text('Bağlan')),
            ],
          ),
        ] else ...[
          Card(
            child: ListTile(
              leading: const ToneIcon(Icons.computer_rounded, color: KocumColors.blue),
              title: Text(secili.ad),
              subtitle: Text('${secili.adres}:${secili.port}'),
              trailing: TextButton(
                onPressed: _calisiyor
                    ? null
                    : () {
                        setState(() => _secili = null);
                        _bul();
                      },
                child: const Text('Değiştir'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Bilgisayarın ekranında 6 haneli bir kod çıktı. Onu buraya yaz (5 dakika geçerli).',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _kod,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 8),
            decoration: const InputDecoration(hintText: '000000', border: OutlineInputBorder()),
            onSubmitted: (_) => _esle(),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _calisiyor ? null : _esle, child: const Text('Eşle')),
          TextButton(onPressed: _calisiyor ? null : () => _sec(secili), child: const Text('Yeni kod iste')),
        ],
        if (hata != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(hata, style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (_calisiyor)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
