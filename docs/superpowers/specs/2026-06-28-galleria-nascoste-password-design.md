# Galleria: immagini nascoste con password

Data: 2026-06-28
Progetto: Interfaccia Smart Krea 2 (`Avvia Krea 2.command`)

## Obiettivo
Permettere di "nascondere" alcune immagini dalla griglia della galleria e rivelarle
inserendo una password. Criterio di successo: un'immagine nascosta non compare nella
griglia (né nei dati inviati alla pagina) finché non si inserisce la password corretta;
una volta sbloccata ricompare marcata da un lucchetto; al reload della pagina si richiude
da sola.

## Livello di protezione (deciso)
**Riservatezza visiva**, non sicurezza vera. Serve a non mostrare certe immagini a chi
guarda lo schermo. I file PNG restano normali e intatti in `ComfyUI/output/` (nessuna
cifratura, nessuno spostamento di file). Nessuna dipendenza esterna: solo stdlib Python,
coerente con l'architettura a file unico.

## Approccio scelto: validazione lato server (A)
Il backend, di default, NON invia alla pagina i nomi delle immagini nascoste. Per rivelarle,
la pagina invia la password a un endpoint dedicato; solo se la password è corretta il server
risponde con la lista delle nascoste. Così, finché non si sblocca, le nascoste non sono
presenti nemmeno nel sorgente della pagina (non scopribili con "ispeziona pagina").

Scartato l'approccio lato client (server manda tutto con un flag, JS confronta la password):
più semplice ma password e nomi finirebbero nel sorgente, aggirabile banalmente.

## Persistenza dello stato
File `nascoste.json` accanto allo script (`Path(__file__).parent / "nascoste.json"`):
un array JSON di nomi-file (es. `["krea2_00012_.png", "krea2_00031_.png"]`).
- Helper `load_nascoste() -> set[str]` e `save_nascoste(set)`.
- Robusto ai file mancanti/corrotti: se non esiste o non è leggibile, si parte da insieme vuoto.
- Va aggiunto a `.gitignore` (come già `output/` e i png): è dato locale, non deve finire nel repo.

## Password
Costante in cima al file:
```python
PASSWORD_GALLERIA = "krea2"  # cambia qui. NB: il repo è pubblico, la password sarà visibile su GitHub.
```
Commento esplicito sull'avviso repo pubblico. (Nota futura, NON in questo lavoro: per nasconderla
al repo si potrà spostarla in un file `.conf` gitignorato.)

## Endpoint backend
| Metodo | Path | Cosa fa |
|---|---|---|
| GET | `/api/galleria` | *modificato*: esclude i file presenti in `nascoste.json` dalla lista delle ultime immagini |
| POST | `/api/sblocca` | body `{"password": "..."}`; se corretta → `{"ok": true, "items": [ ...card nascoste... ]}`, altrimenti `{"ok": false}` |
| POST | `/api/nascondi` | body `{"file": "nome.png"}` → aggiunge il nome a `nascoste.json`, risponde `{"ok": true}` |
| POST | `/api/mostra` | body `{"file": "nome.png"}` → rimuove il nome da `nascoste.json`, risponde `{"ok": true}` |

Note:
- Le card restituite da `/api/sblocca` hanno la stessa forma di quelle di `/api/galleria`
  (così il frontend le rende con lo stesso codice), più un marcatore che indica che sono nascoste.
- `nascondi`/`mostra` non richiedono password: per "riservatezza visiva" è accettabile. A `mostra`
  si arriva comunque solo dopo aver sbloccato (le card nascoste appaiono solo dopo `/api/sblocca`).

## Frontend (UI)
- **Bottone "🙈 Nascondi" su ogni card visibile**, accanto a scarica / ⓘ Dati / ⤢ Upscale.
  Click → POST `/api/nascondi` → la card sparisce dalla griglia.
- **Controllo globale "🔒 Mostra nascoste"** in cima alla galleria. Click → chiede la password
  (input/prompt) → POST `/api/sblocca`.
  - Password giusta: le immagini nascoste vengono aggiunte alla griglia **marcate con un 🔒**;
    il bottone diventa **"🔓 Richiudi"**, che rimuove le nascoste dalla vista lato client.
  - Password sbagliata: messaggio d'errore, nulla viene rivelato.
- **Card rivelate**: oltre al marcatore 🔒, hanno un bottone **"👁 Rendi visibile"** →
  POST `/api/mostra` → l'immagine torna permanentemente nella galleria normale (perde il lucchetto).
- Lo sblocco vale a sessione lato client: un **reload richiude** (coerente con la scelta).
- Il flusso di generazione non cambia: le nuove immagini nascono **visibili**.

## Trappole da rispettare (dal CLAUDE.md)
- L'HTML sta dentro una stringa Python `"""..."""`: nel JS embeddato NON usare sequenze con
  backslash (`\n`, `\t`, ...) o raddoppiarle (`\\n`). Un `\n` reale spezza lo script e
  rompe tutti i bottoni in silenzio.
- Dopo le modifiche al JS: estrarre il blocco `<script>` dalla pagina servita e validarlo con
  `node --check`.
- Path portabile: nessun path assoluto, usare `Path(__file__).parent`.

## Fuori scope (YAGNI)
- Cifratura dei file su disco.
- Spostamento dei file in sottocartelle.
- Password configurabile dalla UI.
- Sblocco persistente tra reload.
- Più password / livelli / cartelle di nascoste.
