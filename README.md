# external-agent

**Claude Code için taşeron skill'i.** Claude işi planlar, basit ve orta zorluktaki
görevleri dış kodlama ajanlarına yaptırır:

- **OpenAI Codex CLI** (varsayılan model `gpt-6.1-sol`)
- **Google Antigravity CLI** (`agy`, Gemini modelleri)

Ajanın yaptığı iş otomatik olarak doğrulanır ve bağımsız bir incelemeden geçer. Claude
sadece sorun çıktığında devreye girer. Böylece Claude'un token'ları zor işlere
(tasarım, karmaşık hata ayıklama, kararlar) kalır, ayak işlerini taşeronlar yapar.

> Superpowers'ın `subagent-driven-development` yaklaşımından esinlenildi. Fark şu:
> alt ajanlar Claude değil, ayrı CLI'ler.

---

## Nasıl çalışır?

Claude her görev için kendi içinde eksiksiz bir görev özeti (brief) yazar ve tek bir
komutla gönderir:

```
Claude ──brief──▶ agent_run.sh delegate
                    │
                    ├─ 1. uygula      : Codex / Antigravity kodu yazar (commit atamaz)
                    ├─ 2. doğrula     : test komutunu BETİK çalıştırır (ajanın "geçti" demesi yetmez)
                    ├─ 3. incele      : yeni, salt okunur bir oturum brief'e göre inceler
                    │                   (istenirse diğer model ailesinden)
                    ├─ 4. düzelt      : kritik/önemli bulgular aynı oturuma geri gönderilir (en fazla 2 tur)
                    └─ FINAL DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED | NEEDS_ATTENTION | FAILED
Claude ◀── tek satır durum + değişen dosyalar + açık kalan notlar
```

`DONE` gelirse Claude değişikliği okumaz, sıradaki göreve geçer. En sonda tüm testleri
bir kez çalıştırır ve tüm değişikliğe tek bir inceleme yaptırır.

## Test sonuçları

Aynı 3 senaryo kullanıldı: iki görevlik bir Python planı, kenar durumu yoğun bir JS
ayrıştırıcı ve kodu değiştirmeden hata araştırma. Değerlendirme, ajanların görmediği
gizli testlerle yapıldı. Denetleyici her durumda Claude Opus 5.5.

| Yapılandırma | Başarı | Ajan süresi (plan / ayrıştırıcı / araştırma) | Not |
|---|---|---|---|
| Skill olmadan, Claude + Codex | %93 | – | Kodda 2 gerçek hata kaldı (kesirli tam dolu kutu, NaN) |
| **Skill + Codex (gpt-6.1-sol)** | **%100** | 131 sn / – / 74 sn | Bağımsız inceleme gerçek hataları yakaladı |
| **Skill + Antigravity (Gemini 4 Argon)** | **%100** | 204 sn / 149 sn / 83 sn | Codex'e yakın süre, çok daha az token |
| Skill + Antigravity (Gemini 3.8 Flash) | %100 | 373 sn / 605 sn / 170 sn | Doğru ama 2-4 kat yavaş ve daha çok token |

Ayrıştırıcı senaryosunun Codex çalıştırması farklı bir modda yapıldığı için süresi
kıyaslanamıyor, tabloda bu yüzden "–" var.

Claude tarafındaki token kullanımı taşerondan bağımsız olarak çalıştırma başına
yaklaşık 75-98 bin. Bunun yaklaşık 60 bini her Claude oturumunun sabit yükü.

---

## Gereksinimler

| | macOS / Linux | Windows |
|---|---|---|
| Claude Code | ✓ | ✓ |
| bash | sistemde var (macOS'un bash 3.2'si yeterli) | **Git for Windows** (Git Bash). Claude Code da Bash aracı için bunu kullanır |
| Python 3.8+ | `python3` | `python` (betik ikisini de dener; Microsoft Store kısayolunu atlar) |
| git | ✓ | ✓ (Git for Windows ile gelir) |
| En az bir taşeron | `codex` ve/veya `agy`, giriş yapılmış olarak | aynı |

- **Codex CLI:** `brew install --cask codex` ya da `npm i -g @openai/codex`, ardından
  `codex login`.
- **Antigravity CLI:** Antigravity uygulamasıyla gelir (`agy`). Güncellemek için
  `agy update`.

## Kurulum

### macOS / Linux

```bash
git clone https://github.com/cemalguvenn/external-agent.git
cd external-agent
./install.sh          # kopyalar: ~/.claude/skills/external-agent
./install.sh --link   # ya da sembolik bağ kurar: git pull ile güncellenir
```

### Windows (PowerShell)

```powershell
git clone https://github.com/cemalguvenn/external-agent.git
cd external-agent
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Komut `%USERPROFILE%\.claude\skills\external-agent` klasörüne kurar. Git Bash ve Python
bulunamazsa uyarı verir.

### Elle kurulum

`external-agent/` klasörünü `~/.claude/skills/` altına kopyalamanız yeterli. Kurduktan
sonra Claude Code'u yeniden başlatın.

## Kullanım

Normal konuşur gibi isteyin, skill kendiliğinden devreye girer:

- "plan.md'deki görevleri codex'e yaptır, her birini kontrol et, commit atma"
- "testleri yazma işini antigravity'ye ver, incelemeyi codex yapsın"
- "bu hatanın nedenini codex'e araştırt ama kodu değiştirmesin"
- "ayak işlerini dış ajanlara ver, sen mimariyle uğraş"
- "parseDimensions'ı gemini 4 argon ile yazdır, iyice kontrol et"

**Antigravity modeli:** skill sabit bir model kullanmaz. Antigravity ilk kez
gerektiğinde mevcut modelleri listeler (`agy models`) ve size seçtirir; Gemini
modelleri önce gösterilir. Kalıcı bir varsayılan için `EXTERNAL_AGENT_AGY_MODEL`
değişkenini ayarlayabilirsiniz.

### Ayarlar (ortam değişkenleri)

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `EXTERNAL_AGENT_MODEL` | `gpt-6.1-sol` | Codex modeli |
| `EXTERNAL_AGENT_AGY_MODEL` | (yok, kullanıcıya sorulur) | Antigravity modeli, ör. `gemini-4-argon-medium` |
| `EXTERNAL_AGENT_RUNS` | `$TMPDIR/external-agent` | Çalıştırma kayıtlarının kök klasörü |
| `EXTERNAL_AGENT_SNAP_ROOT` | `~/.cache/external-agent` | Antigravity'nin geçici proje kopyaları |

### Betiği doğrudan kullanmak

```bash
S=~/.claude/skills/external-agent/scripts/agent_run.sh
$S models --agent agy
$S delegate --agent agy --model gemini-4-argon-medium --review-agent codex \
   --cd ~/proje --brief gorev.md --verify "npm test" --name gorev-1
$S delegate --agent codex --sandbox read-only --cd ~/proje --brief soru.md   # sadece araştırma
```

## Güvenlik ve sınırlar

- Taşeronlar **commit atmaz**. Codex'e görev özetinde yasaklanır ve atarsa betik uyarı
  verir; Antigravity'nin sandbox'ı `.git`'i salt okunur yapar. Kabul edilen işi
  Claude stage'ler, ya da siz istediyseniz commit'ler.
- Codex `workspace-write` sandbox'ında çalışır; ağ erişimi kapalıdır (`--network` ile
  açılır).
- Antigravity'nin ekransız modunda güvenilir bir "salt okunur" mod yok. Bu yüzden
  inceleme ve araştırma projenin **geçici bir kopyasında** yapılır; gerçek projeye
  dokunulmaz ve kopya iş bitince silinir.
- Antigravity'ye giden her talimatın sonunda şemanın tamamı ve bir kapsam kuralı
  var: proje klasörü dışına, ortam değişkenlerine ve başka araçların verilerine
  bakmak yasak. Bu kural olmadan Gemini Flash'ın proje dışında dolaştığı görüldü.
- Riskli işlerde (güvenlik, ödeme, veri taşıma, genel API) skill **ayrıntılı kontrol
  moduna** geçer: Claude değişiklikleri kendisi okur ve test eder.

### Bilinen kısıtlar

- **macOS:** Antigravity, `~/Library/Application Support` altındaki projelerde
  çalışamaz (sandbox orayı engelliyor).
- **Antigravity güvenilir alanları:** proje, Antigravity'nin `trustedWorkspaces`
  listesindeki bir klasörün altında olmalı (varsayılan olarak ev dizini).
- **Windows: gerçek bir Windows makinesinde henüz test edilmedi.** Python ve kopyalama
  farkları macOS'ta benzetilerek test edildi. Ayrıca:
  - Antigravity'nin terminal sandbox'ı Windows 11 24H2 gerektirir.
  - Codex'in Windows sandbox'ı sorun çıkarırsa WSL içinde kullanın.

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| Codex çıkış kodu 137, hiç çıktı yok | Claude Code'un Bash sandbox'ı Codex'i durduruyor. Skill komutları zaten sandbox kapalı çalıştırır; elle çalıştırıyorsanız siz de kapatın. |
| `codex: command not found` / bozuk symlink | `brew reinstall --cask codex` |
| `agy needs a model` | Listelenen modellerden birini seçin |
| `jetski: no output produced … permission` | agy'yi doğrudan değil betikle çağırın |
| Çok yavaş Antigravity çalıştırması | Proje ve geçici kopya klasörü ev dizini altında olmalı |

Ayrıntılar: `external-agent/references/codex-cli.md` ve `antigravity-cli.md`.

## Klasör yapısı

```
external-agent/                 ← skill (bunu ~/.claude/skills/ altına kurun)
├── SKILL.md                    ← Claude'un okuduğu talimatlar
├── scripts/
│   ├── agent_run.sh            ← delegate / task / resume / review / models
│   ├── implementer.schema.json ← ajan rapor şeması
│   └── review.schema.json      ← inceleme bulguları şeması
├── references/                 ← brief şablonları, CLI notları, ayrıntılı kontrol modu
└── evals/                      ← 3 test senaryosu (gizli testler dahil)
install.sh / install.ps1
```

Test senaryolarını `claude plugin eval` (Claude Code v2.1.269 ve üstü) ile yeniden
çalıştırabilirsiniz. Bunlar gerçek ve ücretli model çalıştırmalarıdır.

## Lisans

MIT. Ayrıntılar `LICENSE` dosyasında.
