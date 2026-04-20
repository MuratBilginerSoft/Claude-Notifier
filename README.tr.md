# Claude-Notifier

Claude Code bir işi bitirdiğinde ya da sana bir soru sorduğunda sistem sesi çalar ve masaüstü bildirimi gösterir. Windows, macOS, Linux. Tek satır kurulum. Bağımlılık yok.

![demo](./assets/demo.gif)

> 🇬🇧 **English:** [README.md](./README.md)

## Kurulum

**Windows (PowerShell):**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main/install.ps1)))
```

<details>
<summary>Neden <code>irm | iex</code> değil?</summary>

`irm | iex` indirilen text'i bir expression olarak değerlendirir, ama `install.ps1` `param(...)` bloğu kullanıyor — `param()` sadece script block başlangıcında geçerli. `[scriptblock]::Create(...)` indirilen text'i gerçek bir script block'a çevirir, `&` operatörü de onu çalıştırır. Böylece parametre geçirmek de kolay olur: `& ([scriptblock]::Create((irm ...))) -Uninstall`.

</details>

**macOS / Linux (`jq` gerekir):**

```bash
curl -fsSL https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main/install.sh | bash
```

Yeni bir Claude Code oturumu aç ya da `/hooks` komutunu çalıştır.

## Nasıl çalışır

Installer `~/.claude-notifier/` altına küçük bir helper script koyar ve `~/.claude/settings.json`'a iki hook ekler — biri `Stop` (iş bitti) event'i için, diğeri `Notification` (Claude dikkatini bekliyor) event'i için. Mevcut hook'larına dokunmaz.

Runtime helper her platformda doğru API'yi seçer: Windows'ta `SystemSounds` + WinRT toast, macOS'ta `afplay` + `osascript`, Linux'ta `paplay` + `notify-send`.

## Özelleştirme

Tüm ayarlar environment variable üzerinden — shell'inde veya `~/.claude/settings.json` içindeki `env` alanında tanımlayabilirsin.

| Değişken                               | Değerler                                 | Varsayılan            | Amaç                                         |
|----------------------------------------|------------------------------------------|-----------------------|----------------------------------------------|
| `CLAUDE_NOTIFIER_LANG`                 | `en`, `tr`                               | `en`                  | Mesaj dili                                   |
| `CLAUDE_NOTIFIER_EVENTS`               | `stop`, `notification`                   | `stop,notification`   | Hangi event'ler bildirim tetiklesin (CSV)    |
| `CLAUDE_NOTIFIER_SOUND`                | `0`, `1`                                 | `1`                   | Ses aç/kapa                                  |
| `CLAUDE_NOTIFIER_TOAST`                | `0`, `1`                                 | `1`                   | Toast aç/kapa                                |
| `CLAUDE_NOTIFIER_SOUND_STOP`           | yerleşik isim ya da ses dosyası yolu     | _(platform varsayılanı)_ | **Stop** event'i için ses override'ı       |
| `CLAUDE_NOTIFIER_SOUND_NOTIFICATION`   | yerleşik isim ya da ses dosyası yolu     | _(platform varsayılanı)_ | **Notification** event'i için ses override'ı |

**Ses override değerleri:**

- **Windows:** yerleşik isimlerden biri — `Asterisk`, `Beep`, `Exclamation`, `Hand`, `Question` (büyük/küçük harf fark etmez) **ya da** bir `.wav` dosyasının mutlak yolu.
- **macOS / Linux:** ses dosyasının mutlak yolu. macOS `afplay` kullanır (`.aiff`, `.wav`, `.mp3`, `.m4a` vb. destekler). Linux `paplay`, o yoksa `aplay` ile çalar.

Değer geçersizse ya da dosya yoksa script stderr'a uyarı yazar ve platform varsayılanına düşer.

Örnek — sessiz mod, sadece sorularda tetiklen, Türkçe mesaj:

```json
{
  "env": {
    "CLAUDE_NOTIFIER_SOUND": "0",
    "CLAUDE_NOTIFIER_EVENTS": "notification",
    "CLAUDE_NOTIFIER_LANG": "tr"
  }
}
```

Örnek — Windows'ta özel sesler:

```json
{
  "env": {
    "CLAUDE_NOTIFIER_SOUND_STOP": "Beep",
    "CLAUDE_NOTIFIER_SOUND_NOTIFICATION": "C:\\Sounds\\ding.wav"
  }
}
```

## Kaldırma

**Windows:**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main/install.ps1))) -Uninstall
```

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main/install.sh | bash -s -- --uninstall
```

Uninstall yalnızca `claude-notifier`'ın hook entry'lerini ve helper klasörünü siler. Diğer hook'ların olduğu gibi kalır.

## Güvenlik — çalıştırmadan önce okumak ister misin?

Bu proje `curl | bash` kalıbını kullanıyor. İstersen önce oku:

```bash
curl -fsSL https://raw.githubusercontent.com/MuratBilginerSoft/Claude-Notifier/main/install.sh -o install.sh
less install.sh
bash install.sh
```

## Gereksinimler

- **Windows:** Windows 10 build 19041+ veya Windows 11, PowerShell 5.1+
- **macOS:** macOS 12+ (Monterey veya üzeri)
- **Linux:** bash, `jq`, bildirim daemon'ı (`libnotify-bin` üzerinden `notify-send`); ses için `pulseaudio` ya da `alsa-utils`

## Sorun giderme

- **"Kurdum, bir şey olmadı"** → Claude Code'da bir kez `/hooks` aç, ya da CLI'ı yeniden başlat. Hook watcher ayar değişikliklerini reload'ta yakalar.
- **Linux: ses var ama toast yok** → `sudo apt install libnotify-bin`
- **Windows: toast çıkmıyor ama ses var** → Focus Assist bildirimleri engelliyor olabilir

## Katkı

PR'lar açık. Bağımlılık eklemeden, script başı ~200 satır sınırını koru.

## Lisans

MIT — bkz. [LICENSE](./LICENSE).
