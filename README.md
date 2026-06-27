# Interfaccia Smart Krea 2

Una pagina web semplice per generare immagini con **Krea 2 Turbo** in locale, senza
combattere con l'interfaccia a nodi di ComfyUI.

ComfyUI resta acceso come "motore" invisibile; tu usi una pagina pulita con:

- box per il **prompt**
- scelta di **formato/risoluzione**
- spunta **Nudo / uncensored** (attiva/spegne il modulo Rebalance)
- **seed** (vuoto = casuale, oppure fisso per ripetere uno scatto)
- quante immagini generare in un colpo
- **galleria** con le immagini, a pagine da 6
- **⤢ Upscale ×4** su ogni immagine (Remacri o RealESRGAN)
- **ⓘ Dati**: legge dal PNG il prompt e i parametri con cui l'immagine è stata fatta
- **✕ Quit**: spegne l'interfaccia

Tutto in **un solo file** che si avvia col doppio click. Niente librerie da installare:
usa solo Python già presente sul Mac.

---

## Come si usa

1. **Doppio click** su `Avvia Krea 2.command`.
   - Se ComfyUI non è acceso, prova ad avviarlo da solo.
   - Si apre il browser sulla pagina (`http://127.0.0.1:8190`).
2. Scrivi il prompt, scegli le opzioni, premi **GENERA**.
3. Quando l'immagine compare, puoi **scaricarla**, vederne i **Dati**, o fare **Upscale ×4**.
4. Per chiudere: bottone **✕ Quit** in alto a destra.

> La prima volta che apri il `.command`, macOS potrebbe chiedere conferma
> (tasto destro → *Apri* la prima volta).

---

## Requisiti

- **macOS** con **Python 3** (già incluso nel sistema).
- **ComfyUI** installato e funzionante, in ascolto sulla porta **8189**.
- I modelli di **Krea 2 Turbo** dentro `ComfyUI/models/`:

  | File | Cartella |
  |------|----------|
  | `krea2_turbo_bf16.safetensors` | `diffusion_models/` |
  | `qwen3vl_4b_fp8_scaled.safetensors` | `text_encoders/` |
  | `qwen_image_vae.safetensors` | `vae/` |
  | `4x_foolhardy_Remacri.pth` | `upscale_models/` |
  | `RealESRGAN_x4plus.pth` | `upscale_models/` |

  (Modelli da scaricare da [Comfy-Org/Krea-2](https://huggingface.co/Comfy-Org/Krea-2).)

- Per la spunta **Nudo / uncensored** serve il custom node
  [ConditioningKrea2Rebalance](https://github.com/nova452/ComfyUI-ConditioningKrea2Rebalance)
  in `ComfyUI/custom_nodes/`. Senza, lascia la spunta disattivata.

---

## Dove va messo il file

Il `.command` deve stare in una **cartella accanto a `ComfyUI/`**, cioè così:

```
La tua cartella di progetto/
├── ComfyUI/                     <- l'installazione di ComfyUI
└── interfaccia smart krea 2/
    ├── Avvia Krea 2.command     <- questo programma
    └── README.md
```

Lo script trova ComfyUI salendo di una cartella, quindi questa struttura è importante.

---

## Note

- Porte usate: **8190** per questa interfaccia, **8189** per ComfyUI.
- Le immagini finiscono in `ComfyUI/output/` (le bozze come `Krea2_ui_...`,
  gli upscale come `Krea2_up_...`).
- La spunta **uncensored** amplifica il prompt per ottenere nudo: usala in modo
  responsabile e in linea con le leggi del tuo Paese. Genera solo persone adulte e immaginarie.

## Licenza

MIT. Fanne quello che vuoi.
