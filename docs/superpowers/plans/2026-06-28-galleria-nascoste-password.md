# Galleria: immagini nascoste con password - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nascondere alcune immagini dalla griglia della galleria e rivelarle con una password, lasciando i file PNG intatti in `output/`.

**Architecture:** Tutto vive nel file unico `Avvia Krea 2.command` (server Python stdlib + pagina HTML embeddata nella stringa `PAGE`). La validazione della password è lato server: i nomi delle immagini nascoste non vengono inviati alla pagina finché non si invia la password corretta a `/api/sblocca`. Lo stato (quali file sono nascosti) è un array JSON in `nascoste.json` accanto allo script.

**Tech Stack:** Python 3 standard library (`http.server`), HTML/CSS/JS vanilla embeddato. Nessuna dipendenza.

## Global Constraints

- **File unico:** ogni modifica sta dentro `Avvia Krea 2.command`. Niente nuovi moduli Python.
- **Solo stdlib Python.** Nessuna libreria da installare.
- **Trappola stringa HTML:** la pagina è dentro una stringa Python `"""..."""`. Nel JS embeddato NON usare sequenze con backslash (`\n`, `\t`, `\x..`); se servono, raddoppiarle (`\\n`). Un backslash interpretato da Python spezza lo script e rende muti TUTTI i bottoni, in silenzio.
- **Verifica JS obbligatoria:** dopo ogni modifica al `<script>`, validarlo con `node --check`.
- **Path portabile:** nessun path assoluto; usare `Path(__file__)` / la costante `BASE`.
- **Repo pubblico:** `PASSWORD_GALLERIA` finirà visibile su GitHub (accettato: è riservatezza visiva, non sicurezza). `nascoste.json` NON deve entrare nel repo.
- **Niente trattini lunghi** (—) in codice/commenti/messaggi: usare trattini corti, virgole, parentesi.
- **Nota sui test:** il progetto non ha framework di test. La verifica usa: compile-check Python, un harness curl sugli endpoint (avviato importando il modulo, senza `main()`/`ensure_comfy`), e `node --check` sul JS. È il ciclo di verifica reale del progetto.

---

### Task 1: Persistenza dello stato + password + gitignore

**Files:**
- Modify: `Avvia Krea 2.command` (zona costanti ~righe 32-39; aggiunta funzioni dopo ~riga 39)
- Modify: `.gitignore`

**Interfaces:**
- Produces:
  - Costante `PASSWORD_GALLERIA: str`
  - Costante `NASCOSTE_FILE: Path`
  - `load_nascoste() -> set[str]` (robusta: insieme vuoto se file mancante/corrotto)
  - `save_nascoste(names: Iterable[str]) -> None` (scrive un array JSON ordinato)

- [ ] **Step 1: Scrivere il test (harness Python) che fallisce**

Creare un file temporaneo di verifica `/tmp/test_nascoste.py`:

```python
import importlib.util
spec = importlib.util.spec_from_file_location(
    "krea_ui", "Avvia Krea 2.command")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

# la costante password esiste
assert isinstance(m.PASSWORD_GALLERIA, str) and m.PASSWORD_GALLERIA != ""

# roundtrip: parto da vuoto, salvo due nomi, rileggo
import json
m.NASCOSTE_FILE.write_text("[]")
assert m.load_nascoste() == set()
m.save_nascoste({"b.png", "a.png"})
assert m.load_nascoste() == {"a.png", "b.png"}
# il file su disco e' un array JSON ordinato
assert json.loads(m.NASCOSTE_FILE.read_text()) == ["a.png", "b.png"]
# robustezza: file corrotto -> insieme vuoto, niente eccezioni
m.NASCOSTE_FILE.write_text("non-json{")
assert m.load_nascoste() == set()
m.NASCOSTE_FILE.unlink()
print("OK task1")
```

- [ ] **Step 2: Eseguire il test e verificare che fallisce**

Run: `cd "$(dirname "Avvia Krea 2.command")" 2>/dev/null; python3 /tmp/test_nascoste.py`
(eseguire dalla cartella `interfaccia smart krea 2`)
Expected: FAIL con `AttributeError: module 'krea_ui' has no attribute 'PASSWORD_GALLERIA'`.

- [ ] **Step 3: Implementare costanti e funzioni**

In `Avvia Krea 2.command`, subito dopo il blocco percorsi (dopo la riga `INPUT = COMFYDIR / "input"...`), aggiungere la costante file:

```python
NASCOSTE_FILE = BASE / "nascoste.json"   # nomi-file nascosti dalla galleria (dato locale, NON nel repo)
```

Dopo il blocco `COMFY = ...` / `PORT = ...`, aggiungere la password:

```python
# Password della galleria nascosta. Riservatezza VISIVA, non sicurezza vera:
# i file restano in output/, vengono solo tolti dalla griglia finche' non sblocchi.
# NB: il repo e' PUBBLICO -> questa password sara' visibile su GitHub. Cambiala qui.
PASSWORD_GALLERIA = "krea2"
```

Dopo le costanti `PRESETS = {...}` (prima di `def build_graph`), aggiungere le funzioni:

```python
def load_nascoste():
    """Insieme dei nomi-file nascosti. Robusto a file mancante o corrotto."""
    try:
        data = json.loads(NASCOSTE_FILE.read_text())
        return set(data) if isinstance(data, list) else set()
    except Exception:
        return set()

def save_nascoste(names):
    """Salva l'insieme dei nascosti come array JSON ordinato."""
    NASCOSTE_FILE.write_text(json.dumps(sorted(names)))
```

In `.gitignore`, aggiungere in fondo:

```
# Stato locale della galleria nascosta (nomi-file, non deve finire nel repo)
nascoste.json
```

- [ ] **Step 4: Eseguire il test e verificare che passa**

Run: `python3 /tmp/test_nascoste.py`
Expected: `OK task1`

- [ ] **Step 5: Verificare che lo script compila ancora**

Run: `python3 -c "import importlib.util; s=importlib.util.spec_from_file_location('k','Avvia Krea 2.command'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print('compile ok')"`
Expected: `compile ok`

- [ ] **Step 6: Commit**

```bash
git add "Avvia Krea 2.command" .gitignore
git commit -m "Galleria nascoste: persistenza stato + password + gitignore

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Endpoint backend (filtro galleria + sblocca/nascondi/mostra)

**Files:**
- Modify: `Avvia Krea 2.command` (handler `/api/galleria` ~righe 499-506; `do_POST` ~righe 535-538)

**Interfaces:**
- Consumes: `load_nascoste()`, `save_nascoste()`, `PASSWORD_GALLERIA` (Task 1)
- Produces (contratto HTTP usato dal frontend nei Task 3-4):
  - `GET /api/galleria` -> `{"images": [{"file": str, "up": bool}, ...]}` SENZA i file nascosti
  - `POST /api/sblocca` body `{"password": str}` -> `{"ok": true, "items": [{"file","up"}...]}` se giusta, `{"ok": false}` se sbagliata
  - `POST /api/nascondi` body `{"file": str}` -> `{"ok": true}`
  - `POST /api/mostra` body `{"file": str}` -> `{"ok": true}`

- [ ] **Step 1: Scrivere il test (harness curl) che fallisce**

Creare `/tmp/test_endpoint.py` (avvia il server importando il modulo, SENZA `main()`/`ensure_comfy`, su una porta di test):

```python
import importlib.util, threading, time, json, urllib.request, tempfile, os
from pathlib import Path
spec = importlib.util.spec_from_file_location("krea_ui", "Avvia Krea 2.command")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

# isolo output e stato in una cartella temporanea
tmp = Path(tempfile.mkdtemp())
m.OUTPUT = tmp / "output"; m.OUTPUT.mkdir()
m.NASCOSTE_FILE = tmp / "nascoste.json"
for n in ["a.png", "b.png", "c.png"]:
    (m.OUTPUT / n).write_bytes(b"\\x89PNG\\r\\n\\x1a\\n")  # contenuto fittizio
m.save_nascoste({"b.png"})

from http.server import ThreadingHTTPServer
srv = ThreadingHTTPServer(("127.0.0.1", 8195), m.Handler)
threading.Thread(target=srv.serve_forever, daemon=True).start(); time.sleep(0.3)

def get(p):
    return json.loads(urllib.request.urlopen("http://127.0.0.1:8195"+p, timeout=5).read())
def post(p, body):
    r = urllib.request.Request("http://127.0.0.1:8195"+p,
        data=json.dumps(body).encode(), headers={"Content-Type":"application/json"})
    return json.loads(urllib.request.urlopen(r, timeout=5).read())

# galleria esclude le nascoste
files = {i["file"] for i in get("/api/galleria")["images"]}
assert files == {"a.png", "c.png"}, files

# sblocco con password sbagliata
assert post("/api/sblocca", {"password": "xxx"}) == {"ok": False}
# sblocco giusto -> ritorna le nascoste
r = post("/api/sblocca", {"password": m.PASSWORD_GALLERIA})
assert r["ok"] is True and {i["file"] for i in r["items"]} == {"b.png"}, r

# nascondi a.png -> sparisce dalla galleria, appare nello sblocco
assert post("/api/nascondi", {"file": "a.png"})["ok"] is True
assert {i["file"] for i in get("/api/galleria")["images"]} == {"c.png"}

# mostra b.png -> torna nella galleria
assert post("/api/mostra", {"file": "b.png"})["ok"] is True
assert {i["file"] for i in get("/api/galleria")["images"]} == {"b.png", "c.png"}
print("OK task2")
```

- [ ] **Step 2: Eseguire il test e verificare che fallisce**

Run: `python3 /tmp/test_endpoint.py`
Expected: FAIL su `/api/sblocca` (404 -> `HTTPError` o JSON decode), perché gli endpoint non esistono ancora; il filtro galleria fallisce l'assert (`{"a.png","b.png","c.png"}`).

- [ ] **Step 3: Modificare `/api/galleria` per escludere le nascoste**

In `do_GET`, sostituire il blocco esistente:

```python
        if u.path == "/api/galleria":
            imgs = []
            try:
                files = sorted(OUTPUT.glob("*.png"), key=lambda p: p.stat().st_mtime, reverse=True)[:24]
                imgs = [{"file": p.name, "up": p.name.startswith("Krea2_up")} for p in files]
            except Exception:
                pass
            self._send(200, {"images": imgs}); return
```

con (filtra PRIMA di tagliare a 24, così restano 24 visibili):

```python
        if u.path == "/api/galleria":
            imgs = []
            try:
                nasc = load_nascoste()
                files = sorted(OUTPUT.glob("*.png"), key=lambda p: p.stat().st_mtime, reverse=True)
                files = [p for p in files if p.name not in nasc][:24]
                imgs = [{"file": p.name, "up": p.name.startswith("Krea2_up")} for p in files]
            except Exception:
                pass
            self._send(200, {"images": imgs}); return
```

- [ ] **Step 4: Aggiungere gli endpoint POST**

In `do_POST`, subito dopo il blocco `if path == "/api/upscale": self._upscale(req); return` e PRIMA di `if path != "/api/genera":`, inserire:

```python
        if path == "/api/sblocca":
            if (req.get("password") or "") != PASSWORD_GALLERIA:
                self._send(200, {"ok": False}); return
            nasc = load_nascoste(); items = []
            try:
                files = sorted(OUTPUT.glob("*.png"), key=lambda p: p.stat().st_mtime, reverse=True)
                items = [{"file": p.name, "up": p.name.startswith("Krea2_up")}
                         for p in files if p.name in nasc]
            except Exception:
                pass
            self._send(200, {"ok": True, "items": items}); return

        if path == "/api/nascondi":
            name = os.path.basename(req.get("file") or "")
            if not name:
                self._send(400, {"error": "file mancante"}); return
            nasc = load_nascoste(); nasc.add(name); save_nascoste(nasc)
            self._send(200, {"ok": True}); return

        if path == "/api/mostra":
            name = os.path.basename(req.get("file") or "")
            if not name:
                self._send(400, {"error": "file mancante"}); return
            nasc = load_nascoste(); nasc.discard(name); save_nascoste(nasc)
            self._send(200, {"ok": True}); return
```

- [ ] **Step 5: Eseguire il test e verificare che passa**

Run: `python3 /tmp/test_endpoint.py`
Expected: `OK task2`

- [ ] **Step 6: Commit**

```bash
git add "Avvia Krea 2.command"
git commit -m "Galleria nascoste: endpoint galleria filtrata + sblocca/nascondi/mostra

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Frontend - bottone Nascondi sulle card + marcatore lucchetto

**Files:**
- Modify: `Avvia Krea 2.command` (stringa `PAGE`: funzioni JS `cardHTML` ~righe 388-402, `grid.onclick` ~righe 419-425; aggiunta funzioni `nascondi`/`mostra`)

**Interfaces:**
- Consumes: `POST /api/nascondi`, `POST /api/mostra` (Task 2)
- Produces (campo sull'oggetto item, usato dal Task 4): `it.hidden: bool` (true = immagine nascosta, mostrata col lucchetto). Gli item esistenti senza il campo valgono come `false`.

- [ ] **Step 1: Aggiungere lucchetto + bottone nascondi/mostra in `cardHTML`**

Nella funzione `cardHTML`, sostituire il `return` del ramo "done" (quello con `<img src=...`) con:

```javascript
  const url = "/img/"+encodeURIComponent(it.file);
  const up = it.canUpscale ? `<button data-act="up" data-file="${it.file}">&#10530; Upscale &#215;4</button>` : "";
  const lock = it.hidden ? ` <span class="tag" title="immagine nascosta">&#128274;</span>` : "";
  const hideBtn = it.hidden
    ? `<button data-act="mostra" data-file="${it.file}">&#128065; Rendi visibile</button>`
    : `<button data-act="nascondi" data-file="${it.file}">&#128584; Nascondi</button>`;
  return `<div class="card">
    <img src="${url}" data-act="zoom" data-file="${it.file}">
    <div class="meta"><span>${it.label}${lock}</span><a href="${url}" download>scarica</a></div>
    <div class="acts"><button data-act="meta" data-file="${it.file}">&#9432; Dati</button>${up}${hideBtn}</div>
  </div>`;
```

- [ ] **Step 2: Gestire i nuovi click in `grid.onclick`**

Nella funzione `grid.onclick`, dopo la riga `else if (b.dataset.act === "meta") showMeta(f);`, aggiungere:

```javascript
  else if (b.dataset.act === "nascondi") nascondi(f);
  else if (b.dataset.act === "mostra") mostra(f);
```

- [ ] **Step 3: Aggiungere le funzioni `nascondi` e `mostra`**

Subito dopo la funzione `upscale(file){...}` (prima di `function addItem`), aggiungere:

```javascript
async function nascondi(file){
  try { await fetch("/api/nascondi",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({file})}); }
  catch(e){ setMsg("Errore nel nascondere: "+e, true); return; }
  items = items.filter(it => it.file !== file);
  render();
}
async function mostra(file){
  try { await fetch("/api/mostra",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({file})}); }
  catch(e){ setMsg("Errore: "+e, true); return; }
  const it = items.find(x => x.file === file);
  if (it) it.hidden = false;
  render();
}
```

- [ ] **Step 4: Estrarre il `<script>` e validarlo con node**

Run:
```bash
python3 -c "import importlib.util,re; s=importlib.util.spec_from_file_location('k','Avvia Krea 2.command'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); open('/tmp/page.js','w').write(re.search(r'<script>(.*)</script>', m.PAGE, re.S).group(1))" && node --check /tmp/page.js && echo "JS OK"
```
Expected: `JS OK` (nessun errore di sintassi). Questo conferma anche che nessun backslash è stato interpretato male da Python.

- [ ] **Step 5: Commit**

```bash
git add "Avvia Krea 2.command"
git commit -m "Galleria nascoste: bottone Nascondi/Rendi visibile e marcatore lucchetto

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Frontend - controllo Sblocca/Richiudi con password

**Files:**
- Modify: `Avvia Krea 2.command` (stringa `PAGE`: HTML sopra `<div class="grid">` ~riga 302; CSS ~righe 231-235; JS stato + handler)

**Interfaces:**
- Consumes: `POST /api/sblocca` (Task 2), campo `it.hidden` e funzione `render()` (Task 3)
- Produces: nessuna interfaccia per task successivi (è l'ultimo task).

- [ ] **Step 1: Aggiungere la barra con il bottone nell'HTML**

Nella stringa `PAGE`, subito PRIMA di `<div class="grid" id="grid"></div>`, inserire:

```html
  <div class="gallerybar"><button id="reveal" class="reveal">&#128274; Mostra nascoste</button></div>
```

- [ ] **Step 2: Aggiungere il CSS del controllo**

Nel blocco `<style>`, dopo le regole `.pager span {...}`, aggiungere:

```css
  .gallerybar { display:flex; justify-content:flex-end; margin-top:18px; }
  .reveal { background:var(--panel); color:var(--mut); border:1px solid var(--line);
            border-radius:9px; padding:8px 14px; font-size:13px; cursor:pointer; }
  .reveal:hover { background:#262a33; }
```

- [ ] **Step 3: Aggiungere lo stato `unlocked` e l'handler del bottone**

Nel `<script>`, dopo la riga `let uid = 0;`, aggiungere:

```javascript
let unlocked = false;     // galleria nascosta sbloccata in questa sessione
```

Dopo l'handler `$("#dice").onclick = ...;`, aggiungere:

```javascript
$("#reveal").onclick = async () => {
  if (unlocked){
    items = items.filter(it => !it.hidden);   // richiudi: togli le nascoste dalla vista
    unlocked = false;
    $("#reveal").innerHTML = "&#128274; Mostra nascoste";
    page = 0; render();
    return;
  }
  const pw = prompt("Password per vedere le immagini nascoste:");
  if (pw === null) return;
  let res;
  try { res = await (await fetch("/api/sblocca",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({password:pw})})).json(); }
  catch(e){ setMsg("Errore di rete: "+e, true); return; }
  if (!res.ok){ setMsg("Password sbagliata.", true); return; }
  setMsg("");
  (res.items || []).forEach(im => {
    if (!items.some(it => it.file === im.file))
      items.push({id:++uid, status:"done", file:im.file, label:"nascosta", canUpscale:!im.up, hidden:true});
  });
  unlocked = true;
  $("#reveal").innerHTML = "&#128275; Richiudi";
  page = 0; render();
};
```

- [ ] **Step 4: Estrarre il `<script>` e validarlo con node**

Run:
```bash
python3 -c "import importlib.util,re; s=importlib.util.spec_from_file_location('k','Avvia Krea 2.command'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); open('/tmp/page.js','w').write(re.search(r'<script>(.*)</script>', m.PAGE, re.S).group(1))" && node --check /tmp/page.js && echo "JS OK"
```
Expected: `JS OK`

- [ ] **Step 5: Prova end-to-end manuale**

Avviare l'interfaccia (`python3 "Avvia Krea 2.command"`, serve ComfyUI sulla 8189 solo per generare; per provare il nascondere bastano immagini già in `output/`). Nel browser:
1. Su una card, cliccare `🙈 Nascondi` -> la card sparisce dalla griglia.
2. Cliccare `🔒 Mostra nascoste`, inserire password sbagliata -> messaggio "Password sbagliata.", nulla appare.
3. Cliccare di nuovo, password giusta (`krea2`) -> la card riappare col `🔒`; il bottone diventa `🔓 Richiudi`.
4. Sulla card nascosta, `👁 Rendi visibile` -> il lucchetto sparisce, l'immagine torna normale.
5. Ricaricare la pagina (F5) -> le immagini ancora in `nascoste.json` NON compaiono (richiusura automatica).

Expected: tutti e 5 i punti come descritto. Confermare osservando il browser.

- [ ] **Step 6: Commit**

```bash
git add "Avvia Krea 2.command"
git commit -m "Galleria nascoste: controllo Sblocca/Richiudi con password

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Documentazione (CLAUDE.md) e push

**Files:**
- Modify: `CLAUDE.md` (sezione interfaccia: endpoint, funzioni UI, trappole)

**Interfaces:** nessuna (solo docs).

- [ ] **Step 1: Aggiornare la tabella endpoint e le funzioni UI**

In `CLAUDE.md`, nella tabella degli endpoint aggiungere le righe per `/api/sblocca`, `/api/nascondi`, `/api/mostra` e annotare che `/api/galleria` esclude le nascoste. Nella sezione "Funzioni attuali della UI" aggiungere: bottone `🙈 Nascondi` per card, controllo `🔒 Mostra nascoste` con password (costante `PASSWORD_GALLERIA`), marcatore lucchetto, `👁 Rendi visibile`. Annotare che lo stato sta in `nascoste.json` (gitignorato) e che lo sblocco vale a sessione (reload richiude).

- [ ] **Step 2: Commit e push**

```bash
git add CLAUDE.md docs/
git commit -m "Doc: galleria con immagini nascoste e sblocco a password

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push
```
Expected: push su `origin/main` riuscito.

---

## Self-Review (compilata)

**Spec coverage:**
- Riservatezza visiva, file in output/ intatti -> Task 2 (nessuno spostamento/cifratura). OK
- Validazione lato server (approccio A) -> Task 2 `/api/sblocca`. OK
- Persistenza in `nascoste.json` + gitignore -> Task 1. OK
- Password costante con avviso repo pubblico -> Task 1. OK
- Endpoint galleria filtrata + sblocca/nascondi/mostra -> Task 2. OK
- Bottone Nascondi, controllo Mostra nascoste, marcatore lucchetto, Rendi visibile, richiusura al reload -> Task 3-4. OK
- Trappola stringa HTML + node --check -> Global Constraints + step di verifica Task 3-4. OK

**Placeholder scan:** nessun TBD/TODO; ogni step ha codice/comando concreto. OK

**Type consistency:** `load_nascoste()`/`save_nascoste()` usate coerenti tra Task 1 e 2. Contratto HTTP (`{"ok","items"}`, `{"images"}`) coerente tra Task 2 (produce) e Task 3-4 (consuma). Campo `it.hidden` introdotto in Task 3 e usato in Task 4. OK
