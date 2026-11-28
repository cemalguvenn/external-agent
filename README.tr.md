# external-agent

[English](README.md) · **Türkçe**

**Claude Code ve Antigravity için 3 büyük yapay zeka ailesini kolektif çalıştıran orkestrasyon skill'i.**
Host olarak **Claude Code (Opus)** ya da **Antigravity (Gemini 4 Neon)** üzerinden çalışır;
görevleri modellerin en güçlü olduğu alanlara göre üç büyük CLI arasında paylaştırır:

- **Anthropic Claude Code CLI (`claude`):** Ana taşıyıcı **Opus** (`opus`), hızlı ekonomik yardımcı **Sonnet** (`sonnet`)
- **Google Antigravity CLI (`agy`):** Ana taşıyıcı **Gemini 4 Neon**, hızlı/ekonomik yardımcı & web arama & Nano Banana görsel üretimi için **Hydrogen**, kritik incelemeler için **Carbon**
- **OpenAI Codex CLI (`codex`):** İşçi arı **GPT-6.2 Sol**, kritik incelemeler & zor hata ayıklama için **GPT-6.2 Astra**, görsel üretimi için **Luna**

Devredilen her görev bağımsız olarak doğrulanır ve **farklı model ailesinden** bir
incelemeden geçer. Opus ve Neon kritik kodlama, kodla görsel üretim, standart incelemeler
ve son onayları üstlenirken, kullanım limitleri 3 platform arasında en verimli şekilde
paylaşılır.

---

## Nasıl çalışır?

Host her görev için kendi içinde eksiksiz bir brief yazar ve tek bir komutla gönderir:

```
Host (Opus / Neon) ──brief──▶ agent_run.sh delegate
                                │
                                ├─ 0. kota     : Codex'in son kullanımı okunur (%90 ve üstünde Codex atlanır)
                                ├─ 1. uygula   : claude / agy / codex kodu yazar (commit atamaz)
                                ├─ 2. doğrula  : test komutunu BETİK bağımsız çalıştırır
                                ├─ 3. incele   : farklı model ailesinden taze, salt okunur oturum inceler
                                ├─ 4. düzelt   : kritik/önemli bulgular aynı oturuma geri gider (en fazla 2 tur)
                                │   (bir ajanın kotası biterse uygun diğer dış CLI rolü devralır)
                                └─ FINAL DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED | NEEDS_ATTENTION | LIMITED | FAILED
Host ◀── tek satır durum + değişen dosyalar + açık kalan notlar
```

`DONE` gelirse host diff okuyarak token harcamaz, sıradaki göreve geçer. En sonda tüm
testleri bir kez çalıştırır ve tüm değişikliğe tek bir toplu inceleme yaptırır.

### Kota ve 3 yönlü fallback

- **Başlamadan önce:** Codex 5 saatlik ve haftalık kotasını oturum dosyalarına yazar.
  Betik en güncel değeri okur (`usage: codex 5h=40% week=12%`) ve %90 üstünde
  (`EXTERNAL_AGENT_CODEX_MAX_PCT`) Codex'i baştan atlar.
- **Görev sırasında:** Herhangi bir CLI kullanım/rate limitine takılırsa o adım `LIMITED`
  işaretlenir ve rol, kotası uygun başka bir dış CLI'ye devredilir (`--host` verildiyse
  host'un kendi CLI'sine geri dönülmez).
- **Tüm dış CLI'lar dolduysa:** `FINAL LIMITED` döner ve `limits:` satırında sıfırlanma
  bilgisi gösterilir. Tek bir ajanda ısrar etmek için `--no-fallback` kullanılır.

---

## Görev dağılımı

Skill ana yükü çalıştığı platforma göre dengeler: **Antigravity**'de ana yükü **Neon**,
**Claude Code**'da **Opus** taşır; ancak büyük işlerde iki ana taşıyıcı yükü her zaman
paylaşır (`agy` içindeki Claude modelleri kullanılmaz, Claude görevleri her zaman doğrudan
`--agent claude` üzerinden gider).

| İş | Kim |
|---|---|
| **Ana / zor kodlama, mimari, diğer ajan raporlarının son onayı** | **Ana Taşıyıcılar: Opus & Neon.** Host ana yükü taşır, bağımsız ağır modülleri diğer ana taşıyıcıya devreder (`claude opus` / `agy gemini-4-neon-high`) |
| **Kodla görsel içerik üretimi** (SVG, Canvas, WebGL/Three.js, CSS/HTML UI, shader, grafikler) | **Sadece Ana Taşıyıcılar: Opus veya Neon** |
| **Standart / hafif kodlama:** 1–3 dosyalık özellik, rutin hata düzeltme, test yazımı, refactor | **İşçi Arı: `codex` `gpt-6.2-sol`** (`medium`/`high`) |
| **Hızlı & ekonomik ayak işleri + web arama:** hızlı web araştırması, net tarifli mekanik düzenlemeler, doküman/özet | **`agy` `gemini-4-hydrogen-low/medium`** (özellikle web arama & mekanik işler) veya **`claude` `sonnet`** (hafif düzenleme, doküman, özet) |
| **Raster / AI görsel ve asset üretimi:** ikon, sprite, doku, mockup | **Nano Banana** (`agy` `gemini-4-hydrogen-low` / `image-generator`) & **Codex Image** (`codex` `gpt-6-luna` `low`) |
| **Salt okunur kod araştırması** | `agy` `gemini-4-neon-high`, `claude` `opus` veya `codex` `gpt-6.2-astra` `high` |
| **Standart görev incelemesi** | **Ana Taşıyıcılar (Opus / Neon), farklı aileden:** Sol'ün işini Neon veya Opus; Opus'un işini Neon; Neon'un işini Opus inceler |
| **Kritik görev incelemesi & son toplu inceleme** | **Ağır Siklet İncelemeciler (farklı aileden): `agy` `gemini-4-carbon`** (hesapta açıksa, yoksa `gemini-4-neon-high/xhigh`) ve/veya **`codex` `gpt-6.2-astra`** |

### Görsel görevleri ve A/B Mockup Yarıştırması

- **Kodla görsel içerik** (SVG, Canvas, Three.js, shader, grafikler) her zaman **Opus**
  veya **Neon** tarafından yazılır.
- **Raster / AI görsel üretimi** için **Nano Banana** ve **Codex Image** kullanılır
  (`--no-review` + format doğrulayan `--verify`).
- **A/B Mockup Yarıştırması:** Önemli görsel işlerde veya çoklu asset setlerinde her iki
  görsel modeline paralel birer mockup yaptırılır. Ana taşıyıcılardan biri (host veya
  bağımsız seçim için diğer ana taşıyıcı) iki çıktıyı inceleyip kazananı seçer ve kalan
  tüm görsel görevlerini kazanan modele atar.

---

## Kendini güncel tutma: `doctor`

Host her oturumun başında `agent_run.sh doctor` çalıştırır:

1. **CLI sürümleri:** kurulu `codex`, `agy` ve `claude` sürümlerini en yeni sürümlerle
   karşılaştırır.
2. **Model listesi:** CLI'ların sunduğu modelleri `scripts/models.tsv` ile karşılaştırır
   (hesapta `gemini-4-carbon` açıksa ayrıca bildirir).
3. **Deneme çalıştırması (probe):** önerilen her modele küçük bir "OK" testi yapar (CLI
   sürümü başına 14 gün önbelleklenir, sadece güncelleme sonrası kota harcar).

```bash
S=~/.claude/skills/external-agent/scripts/agent_run.sh
$S doctor                            # tam kontrol (codex, agy, claude)
$S doctor --no-probe                 # sadece ücretsiz kontroller
$S doctor --agent codex --reprobe    # önbelleği yok say, yeniden dene
```

---

## Gereksinimler ve Kurulum

| | macOS / Linux | Windows |
|---|---|---|
| Host | Claude Code ve/veya Antigravity | aynı |
| bash | sistemde var | **Git for Windows** (Git Bash) |
| Python 3.8+ | `python3` | `python` (Microsoft Store kısayolu atlanır) |
| git | ✓ | ✓ (Git for Windows ile gelir) |
| Ajan CLI'ları | `claude`, `codex`, `agy` (giriş yapılmış) | aynı |

### macOS / Linux

```bash
git clone https://github.com/cemalguvenn/external-agent.git
cd external-agent
./install.sh --link --force                  # Claude Code + Antigravity'ye (varsa) sembolik bağ kurar
./install.sh --target claude|agy|both        # belirli bir platforma kurulum
```

### Windows (PowerShell)

```powershell
git clone https://github.com/cemalguvenn/external-agent.git
powershell -ExecutionPolicy Bypass -File .\external-agent\install.ps1 -Force
# İsteğe bağlı: -Target claude | agy | both
```

Kurulumdan sonra Claude Code / Antigravity'yi yeniden başlatın.

---

## Kullanım

Normal konuşur gibi isteyin, skill kendiliğinden devreye girer:

- "plan.md'deki görevleri dış ajanlarla dağıt; ağır kısımları opus ve neon paylaşsın, testleri sol yazsın"
- "auth değişikliklerine carbon veya astra ile kritik inceleme yaptır"
- "hydrogen ile son API dokümanına hızlıca bakıp config'i güncellet"
- "ikon seti için codex ve nano banana'ya birer mockup yaptır, en iyisini seçip kalanları ona ver"
- "interaktif SVG/Canvas grafiği sen veya diğer ana taşıyıcı yazsın"

### Ortam değişkenleri

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `EXTERNAL_AGENT_MODEL` | `gpt-6.2-sol` | Varsayılan Codex modeli |
| `EXTERNAL_AGENT_AGY_MODEL` | (oturumda ilk seferde sorulur) | Varsayılan Antigravity modeli (ör. `gemini-4-neon-medium`) |
| `EXTERNAL_AGENT_CLAUDE_MODEL` | `opus` | Varsayılan Claude CLI modeli (`opus` veya `sonnet`) |
| `EXTERNAL_AGENT_HOST` | (yok) | Host platformu (`claude` veya `agy`); otomatik fallback'te atlanır |
| `EXTERNAL_AGENT_CODEX_MAX_PCT` | `90` | Codex'in 5 saatlik ya da haftalık kullanımı bu %'ye ulaşınca Codex atlanır |
| `EXTERNAL_AGENT_RUNS` | `$TMPDIR/external-agent` | Çalıştırma kayıtlarının kök klasörü |
| `EXTERNAL_AGENT_SNAP_ROOT` | `~/.cache/external-agent` | Antigravity ve Claude salt okunur çalıştırmalarının geçici kopyaları |

### Betiği doğrudan kullanmak

```bash
S=~/.claude/skills/external-agent/scripts/agent_run.sh
$S doctor
$S models --agent agy
$S delegate --host claude --agent codex --model gpt-6.2-sol \
   --review-agent agy --review-model gemini-4-neon-high \
   --cd ~/proje --brief gorev.md --verify "npm test" --name gorev-1
$S delegate --host agy --agent claude --model opus \
   --review-agent codex --review-model gpt-6.2-astra \
   --cd ~/proje --brief cekirdek.md --verify "pytest" --name cekirdek-1
```

---

## Güvenlik ve sınırlar

- **Taşeronlar commit atmaz.** Brief'te yasaklanır, `HEAD` değişirse betik uyarır ve
  Antigravity sandbox'ı `.git`'i salt okunur tutar.
- **Salt okunur izolasyon:** Codex kendi `read-only` sandbox'ında çalışır; Antigravity ve
  Claude inceleme ve araştırmaları iş bitince silinen geçici proje kopyasında yürütür.
- **Ayrıntılı kontrol modu:** Güvenlik, kimlik doğrulama, ödeme, veri taşıma veya genel
  API değişikliklerinde host adım adım kontrole geçip diff'i kendisi okur ve test eder.
- **Host sandbox'ı:** `agent_run.sh` çağrıları host sandbox'ı kapalı çalıştırılmalıdır
  (Claude Code: Bash sandbox kapalı; Antigravity: `BypassSandbox: true`).

Ayrıntılar ve sorun giderme: `external-agent/references/claude-cli.md`, `codex-cli.md` ve
`antigravity-cli.md`.

## Klasör yapısı

```
external-agent/                 ← skill (~/.claude/skills/ ve/veya ~/.gemini/config/skills/ altına kurulur)
├── SKILL.md                    ← host'un (Claude Code / Antigravity) okuduğu talimatlar
├── scripts/
│   ├── agent_run.sh            ← delegate / task / resume / review / models / doctor
│   ├── doctor.py               ← CLI sürümü, model listesi ve deneme çalıştırması kontrolü
│   ├── models.tsv              ← claude, codex ve agy için bilinen modeller ve rolleri
│   ├── implementer.schema.json ← yapılandırılmış ajan rapor şeması
│   └── review.schema.json      ← yapılandırılmış inceleme bulguları şeması
├── references/                 ← brief şablonları, CLI notları, ayrıntılı kontrol modu
└── evals/                      ← ekransız değerlendirme betikleri ve test senaryoları
install.sh / install.ps1
```

## Lisans

MIT. Ayrıntılar `LICENSE` dosyasında.
