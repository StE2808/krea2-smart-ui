#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Interfaccia Smart Krea 2 - FILE UNICO, doppio click e via.

Cosa fa col doppio click (dal Finder):
  1) se ComfyUI non e' acceso, lo avvia da solo (porta 8189) e aspetta che sia pronto
  2) avvia questa interfaccia (porta 8190)
  3) apre il browser sulla pagina

ComfyUI resta il MOTORE invisibile; qui sopra c'e' la pagina semplice:
prompt, formato, checkbox "Nudo / uncensored", seed, quante immagini, GENERA, galleria.

Solo libreria standard di Python: niente da installare.
"""

import json, os, random, shutil, subprocess, threading, time, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs
import urllib.request, urllib.error

# ---------------------------------------------------------------------------
# Percorsi e costanti
# ---------------------------------------------------------------------------
BASE     = Path(__file__).resolve().parent          # .../interfaccia smart krea 2
PROJECT  = BASE.parent                              # .../Krea 2
COMFYDIR = PROJECT / "ComfyUI"
OUTPUT   = COMFYDIR / "output"                      # dove ComfyUI salva le immagini
INPUT    = COMFYDIR / "input"                       # da dove LoadImage legge (per l'upscale)

COMFY    = "http://127.0.0.1:8189"   # il motore
PORT     = 8190                       # porta di questa interfaccia (separata)

# Preset del nodo Rebalance = la "manopola" del modulo uncensored.
PRESETS = {
    True:  {"multiplier": 4.0, "per_layer_weights": "1.0,1.0,1.0,1.0,1.0,1.0,1.0,2.5,5.0,1.1,4.0,1.0"},  # nudo
    False: {"multiplier": 1.0, "per_layer_weights": ""},                                                   # neutro
}

# ---------------------------------------------------------------------------
# Comunicazione con ComfyUI
# ---------------------------------------------------------------------------
def build_graph(prompt, nudo, width, height, seed):
    """Pipeline Krea 2 Turbo validata (vedi genera_krea2.py)."""
    rb = PRESETS[bool(nudo)]
    return {
        "1": {"class_type": "UNETLoader",
              "inputs": {"unet_name": "krea2_turbo_bf16.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader",
              "inputs": {"clip_name": "qwen3vl_4b_fp8_scaled.safetensors", "type": "krea2", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "qwen_image_vae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["2", 0]}},
        "5": {"class_type": "ConditioningKrea2Rebalance",
              "inputs": {"conditioning": ["4", 0],
                         "multiplier": rb["multiplier"], "per_layer_weights": rb["per_layer_weights"]}},
        "6": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["4", 0]}},
        "7": {"class_type": "EmptyLatentImage",
              "inputs": {"width": int(width), "height": int(height), "batch_size": 1}},
        "8": {"class_type": "KSampler",
              "inputs": {"seed": int(seed), "steps": 8, "cfg": 1.0,
                         "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0,
                         "model": ["1", 0], "positive": ["5", 0],
                         "negative": ["6", 0], "latent_image": ["7", 0]}},
        "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
        "10": {"class_type": "SaveImage", "inputs": {"filename_prefix": "Krea2_ui", "images": ["9", 0]}},
    }

def build_upscale_graph(filename, model):
    """Upscale 4x di un'immagine esistente: LoadImage -> modello -> SaveImage."""
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": filename}},
        "2": {"class_type": "UpscaleModelLoader", "inputs": {"model_name": model}},
        "3": {"class_type": "ImageUpscaleWithModel",
              "inputs": {"upscale_model": ["2", 0], "image": ["1", 0]}},
        "4": {"class_type": "SaveImage", "inputs": {"filename_prefix": "Krea2_up", "images": ["3", 0]}},
    }

def comfy_alive():
    try:
        urllib.request.urlopen(COMFY + "/system_stats", timeout=2)
        return True
    except Exception:
        return False

def comfy_post(path, payload):
    req = urllib.request.Request(COMFY + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=30).read())

def comfy_get(path):
    return json.loads(urllib.request.urlopen(COMFY + path, timeout=30).read())

def ensure_comfy():
    """Se ComfyUI non risponde, prova ad avviarlo dal venv e aspetta che sia pronto."""
    if comfy_alive():
        print("ComfyUI gia' acceso.")
        return True
    venv_py = COMFYDIR / "venv" / "bin" / "python"
    main_py = COMFYDIR / "main.py"
    if not (venv_py.exists() and main_py.exists()):
        print("ATTENZIONE: non trovo il venv di ComfyUI. Avvialo a mano sulla porta 8189.")
        return False
    print("Avvio ComfyUI in sottofondo (puo' volerci un minuto la prima volta)...")
    subprocess.Popen([str(venv_py), str(main_py), "--port", "8189"],
                     cwd=str(COMFYDIR),
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(180):
        if comfy_alive():
            print("ComfyUI pronto.")
            return True
        time.sleep(1)
    print("ComfyUI non si e' avviato in tempo. Provo lo stesso ad aprire l'interfaccia.")
    return False

def png_text_chunks(path):
    """Legge i chunk testuali (tEXt/iTXt) di un PNG con sola stdlib.
    ComfyUI ci salva dentro 'prompt' (il grafo) e a volte 'workflow'."""
    import struct, zlib
    out = {}
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return out
    i = 8
    while i + 8 <= len(data):
        ln  = struct.unpack(">I", data[i:i+4])[0]
        typ = data[i+4:i+8]
        chunk = data[i+8:i+8+ln]
        if typ == b"tEXt" and b"\x00" in chunk:
            k, v = chunk.split(b"\x00", 1)
            out[k.decode("latin1")] = v.decode("latin1", "replace")
        elif typ == b"iTXt":
            try:
                k, rest = chunk.split(b"\x00", 1)
                compflag = rest[0]; rest = rest[2:]            # salta compflag + method
                _lang, rest = rest.split(b"\x00", 1)
                _tk, txt = rest.split(b"\x00", 1)
                if compflag == 1:
                    txt = zlib.decompress(txt)
                out[k.decode("latin1")] = txt.decode("utf-8", "replace")
            except Exception:
                pass
        i += 12 + ln
        if typ == b"IEND":
            break
    return out

def png_summary(fields):
    """Estrae i parametri leggibili dal grafo salvato nel PNG."""
    s = {}
    raw = fields.get("prompt")
    if not raw:
        return s
    try:
        g = json.loads(raw)
    except Exception:
        return s
    for node in g.values():
        ct = node.get("class_type"); inp = node.get("inputs", {})
        if ct == "CLIPTextEncode" and isinstance(inp.get("text"), str):
            s["prompt"] = inp["text"]
        elif ct == "KSampler":
            s.update(seed=inp.get("seed"), steps=inp.get("steps"),
                     cfg=inp.get("cfg"), sampler=inp.get("sampler_name"))
        elif ct == "EmptyLatentImage":
            s["risoluzione"] = f'{inp.get("width")}x{inp.get("height")}'
        elif ct == "ConditioningKrea2Rebalance":
            s["uncensored"] = "si (mult %s)" % inp.get("multiplier") if inp.get("multiplier", 1) > 1 else "no"
        elif ct == "UpscaleModelLoader":
            s["upscaler"] = inp.get("model_name")
    return s

# ---------------------------------------------------------------------------
# Pagina HTML (incorporata: un file solo)
# ---------------------------------------------------------------------------
PAGE = """<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Interfaccia Smart Krea 2</title>
<style>
  :root { --bg:#15171c; --panel:#1e2128; --line:#2c2f38; --txt:#e7e9ee; --mut:#9aa0ad; --acc:#ff7a3c; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--txt); font:15px/1.5 -apple-system,system-ui,sans-serif; }
  header { padding:14px 22px; border-bottom:1px solid var(--line); font-weight:700; font-size:18px;
           display:flex; align-items:center; justify-content:space-between; }
  header span { color:var(--acc); }
  .quit { font-weight:600; font-size:14px; background:#3a2020; color:#ff9a9a;
          border:1px solid #5a2a2a; border-radius:9px; padding:8px 14px; cursor:pointer; }
  .quit:hover { background:#4a2626; }
  .wrap { max-width:1100px; margin:0 auto; padding:22px; }
  .panel { background:var(--panel); border:1px solid var(--line); border-radius:14px; padding:18px; }
  label { display:block; font-size:13px; color:var(--mut); margin:0 0 6px; }
  textarea, select, input[type=number] {
    width:100%; background:#13151a; color:var(--txt); border:1px solid var(--line);
    border-radius:10px; padding:11px 12px; font:inherit; }
  textarea { min-height:110px; resize:vertical; }
  .row { display:flex; gap:14px; flex-wrap:wrap; margin-top:14px; }
  .row > div { flex:1; min-width:150px; }
  .check { display:flex; align-items:center; gap:10px; background:#13151a; border:1px solid var(--line);
           border-radius:10px; padding:11px 12px; cursor:pointer; user-select:none; }
  .check input { width:18px; height:18px; accent-color:var(--acc); }
  .seedline { display:flex; gap:8px; }
  .seedline input { flex:1; }
  button { font:inherit; border:0; border-radius:10px; cursor:pointer; }
  .dice { background:var(--line); color:var(--txt); padding:0 14px; font-size:18px; }
  .go { margin-top:16px; width:100%; background:var(--acc); color:#1a1205; font-weight:700;
        padding:14px; font-size:16px; }
  .go:disabled { opacity:.55; cursor:default; }
  .msg { margin-top:12px; font-size:13px; color:var(--mut); min-height:18px; }
  .msg.err { color:#ff6b6b; }
  .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(220px,1fr)); gap:14px; margin-top:22px; }
  .card { background:var(--panel); border:1px solid var(--line); border-radius:12px; overflow:hidden; }
  .card .ph { aspect-ratio:2/3; display:flex; align-items:center; justify-content:center; color:var(--mut);
              font-size:13px; background:#0f1115; }
  .card img { display:block; width:100%; cursor:zoom-in; }
  .card .meta { padding:8px 10px; font-size:12px; color:var(--mut); display:flex; justify-content:space-between; }
  .card .meta a { color:var(--acc); text-decoration:none; }
  .card .up { width:100%; background:var(--line); color:var(--txt); padding:9px; font-size:13px;
              border-top:1px solid var(--line); }
  .card .up:hover { background:#3a3e49; }
  .card .up:disabled { opacity:.5; cursor:default; }
  .tag { font-size:11px; color:var(--acc); }
  .card .acts { display:flex; }
  .card .acts button { flex:1; background:var(--line); color:var(--txt); padding:9px; font-size:13px;
                       border-top:1px solid var(--line); }
  .card .acts button + button { border-left:1px solid var(--bg); }
  .card .acts button:hover { background:#3a3e49; }
  .card .acts button:disabled { opacity:.5; cursor:default; }
  .pager { display:flex; align-items:center; justify-content:center; gap:16px; margin-top:20px; }
  .pager button { background:var(--panel); color:var(--txt); border:1px solid var(--line);
                  border-radius:9px; padding:8px 16px; }
  .pager button:disabled { opacity:.4; cursor:default; }
  .pager span { color:var(--mut); font-size:13px; }
  #metadlg { background:var(--panel); color:var(--txt); border:1px solid var(--line);
             border-radius:14px; padding:20px; max-width:640px; width:92vw; }
  #metadlg h3 { margin:0 0 14px; }
  #metadlg .kv { display:grid; grid-template-columns:130px 1fr; gap:6px 12px; font-size:14px; }
  #metadlg .kv b { color:var(--mut); font-weight:500; }
  #metadlg .pr { margin-top:14px; }
  #metadlg .pr textarea { width:100%; min-height:120px; background:#13151a; color:var(--txt);
                          border:1px solid var(--line); border-radius:8px; padding:10px; font:13px/1.4 monospace; }
  #metadlg .close { margin-top:16px; background:var(--acc); color:#1a1205; font-weight:700;
                    border:0; border-radius:9px; padding:10px 18px; cursor:pointer; }
  .spin { width:22px; height:22px; border:3px solid var(--line); border-top-color:var(--acc);
          border-radius:50%; animation:r 1s linear infinite; }
  @keyframes r { to { transform:rotate(360deg); } }
  dialog { border:0; background:transparent; max-width:95vw; max-height:95vh; }
  dialog img { max-width:95vw; max-height:95vh; border-radius:10px; }
  dialog::backdrop { background:rgba(0,0,0,.85); }
</style>
</head>
<body>
<header><div>Interfaccia Smart <span>Krea 2</span></div><button class="quit" id="quit">&#10005; Quit</button></header>
<div class="wrap">
  <div class="panel">
    <label>Prompt</label>
    <textarea id="prompt" placeholder="Descrivi l'immagine in inglese...">full body photograph, head to toe, entire figure visible, face clearly visible, a beautiful young woman standing on a sandy beach, full-length portrait, completely nude, bare skin, no clothing, no towel, no fabric, natural body, relaxed pose, arms at her sides, golden hour sunlight, soft warm light, calm sea in the background, analog film photo, natural skin texture, fine grain, photorealistic</textarea>

    <div class="row">
      <div>
        <label>Formato / risoluzione</label>
        <select id="size">
          <option value="512x768">512 x 768 - bozza veloce</option>
          <option value="512x896">512 x 896 - bozza piu' verticale</option>
          <option value="832x1216">832 x 1216 - finale verticale</option>
          <option value="1024x1024">1024 x 1024 - quadrato</option>
        </select>
      </div>
      <div>
        <label>Quante immagini</label>
        <input type="number" id="batch" value="1" min="1" max="6">
      </div>
      <div>
        <label>Seed (vuoto = casuale)</label>
        <div class="seedline">
          <input type="number" id="seed" placeholder="casuale">
          <button class="dice" id="dice" title="Svuota / casuale">&#127922;</button>
        </div>
      </div>
    </div>

    <div class="row">
      <div style="flex:0 0 auto">
        <label>&nbsp;</label>
        <label class="check"><input type="checkbox" id="nudo" checked> Nudo / uncensored</label>
      </div>
      <div>
        <label>Upscaler (per il bottone sotto le immagini)</label>
        <select id="upscaler">
          <option value="4x_foolhardy_Remacri.pth">Remacri 4x - grana/pelle (consigliato)</option>
          <option value="RealESRGAN_x4plus.pth">RealESRGAN 4x - piu' liscio</option>
        </select>
      </div>
    </div>

    <button class="go" id="go">GENERA</button>
    <div class="msg" id="msg"></div>
  </div>

  <div class="grid" id="grid"></div>
  <div class="pager" id="pager" style="display:none">
    <button id="prev">&#8592; Indietro</button>
    <span id="pageinfo"></span>
    <button id="next">Avanti &#8594;</button>
  </div>
</div>

<dialog id="lb"><img id="lbimg" src=""></dialog>
<dialog id="metadlg">
  <h3>Dati immagine</h3>
  <div class="kv" id="metakv"></div>
  <div class="pr"><label style="font-size:13px;color:var(--mut)">Prompt</label><textarea id="metaprompt" readonly></textarea></div>
  <button class="close" id="metaclose">Chiudi</button>
</dialog>

<script>
const $ = s => document.querySelector(s);
const grid = $("#grid"), msg = $("#msg");
const PER = 6;            // immagini per pagina
let items = [];           // {id,label,status:'pending'|'done'|'failed',file,canUpscale}
let page = 0;
let uid = 0;

$("#dice").onclick = () => { $("#seed").value = ""; };

$("#quit").onclick = async () => {
  if (!confirm("Chiudere l'interfaccia e il server? (ComfyUI resta acceso a parte.)")) return;
  try { await fetch("/api/quit"); } catch(e){}
  document.body.innerHTML =
    '<div style="display:flex;height:100vh;align-items:center;justify-content:center;'+
    'color:#9aa0ad;font:16px -apple-system,sans-serif;text-align:center">'+
    'Interfaccia chiusa.<br>Puoi chiudere questa scheda del browser.</div>';
  setTimeout(() => { try { window.close(); } catch(e){} }, 400);
};

$("#go").onclick = async () => {
  const prompt = $("#prompt").value.trim();
  if (!prompt) { setMsg("Scrivi un prompt.", true); return; }
  const [w,h] = $("#size").value.split("x").map(Number);
  const body = {
    prompt, width:w, height:h,
    nudo: $("#nudo").checked,
    batch: Math.max(1, Math.min(6, parseInt($("#batch").value)||1)),
    seed: $("#seed").value === "" ? null : parseInt($("#seed").value)
  };
  $("#go").disabled = true; setMsg("Invio a ComfyUI...");
  let res;
  try { res = await (await fetch("/api/genera",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)})).json(); }
  catch(e){ setMsg("Errore di rete: "+e, true); $("#go").disabled=false; return; }
  if (res.error){ setMsg(res.error, true); $("#go").disabled=false; return; }
  setMsg("In generazione... (Turbo: ~1 min a bozza)");
  res.jobs.forEach(job => {
    const it = addItem({label:"seed "+job.seed, canUpscale:true});
    poll(job.prompt_id, it);
  });
  $("#go").disabled = false;
};

async function upscale(file){
  const model = $("#upscaler").value;
  setMsg("Upscale in corso... (~10 s)");
  let res;
  try { res = await (await fetch("/api/upscale",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({filename:file, model})})).json(); }
  catch(e){ setMsg("Errore upscale: "+e, true); return; }
  if (res.error){ setMsg(res.error, true); return; }
  const nice = model.indexOf("Remacri")>=0 ? "Remacri 4x" : "RealESRGAN 4x";
  const it = addItem({label:"upscale "+nice, canUpscale:false});
  poll(res.prompt_id, it);
  setMsg("");
}

function addItem(it){ it.id = ++uid; it.status = "pending"; items.unshift(it); page = 0; render(); return it; }

async function poll(prompt_id, it){
  for (let i=0;i<240;i++){
    await new Promise(r=>setTimeout(r,2000));
    let st;
    try { st = await (await fetch("/api/stato?id="+prompt_id)).json(); } catch(e){ continue; }
    if (st.done && st.images.length){
      it.status = "done"; it.file = st.images[0]; render(); return;
    }
  }
  it.status = "failed"; render();
}

function cardHTML(it){
  if (it.status === "pending")
    return `<div class="card"><div class="ph"><div class="spin"></div></div>
            <div class="meta"><span>${it.label}</span><span>...</span></div></div>`;
  if (it.status === "failed")
    return `<div class="card"><div class="ph">scaduto</div>
            <div class="meta"><span>${it.label}</span></div></div>`;
  const url = "/img/"+encodeURIComponent(it.file);
  const up = it.canUpscale ? `<button data-act="up" data-file="${it.file}">&#10530; Upscale &#215;4</button>` : "";
  return `<div class="card">
    <img src="${url}" data-act="zoom" data-file="${it.file}">
    <div class="meta"><span>${it.label}</span><a href="${url}" download>scarica</a></div>
    <div class="acts"><button data-act="meta" data-file="${it.file}">&#9432; Dati</button>${up}</div>
  </div>`;
}

function render(){
  const pages = Math.max(1, Math.ceil(items.length/PER));
  if (page > pages-1) page = pages-1;
  grid.innerHTML = items.slice(page*PER, page*PER+PER).map(cardHTML).join("");
  const pager = $("#pager");
  if (items.length > PER){
    pager.style.display = "flex";
    $("#pageinfo").textContent = `pagina ${page+1} / ${pages} - ${items.length} immagini`;
    $("#prev").disabled = page === 0;
    $("#next").disabled = page >= pages-1;
  } else {
    pager.style.display = "none";
  }
}

grid.onclick = e => {
  const b = e.target.closest("[data-act]"); if (!b) return;
  const f = b.dataset.file;
  if (b.dataset.act === "zoom") zoom("/img/"+encodeURIComponent(f));
  else if (b.dataset.act === "up") upscale(f);
  else if (b.dataset.act === "meta") showMeta(f);
};
$("#prev").onclick = () => { if (page>0){ page--; render(); } };
$("#next").onclick = () => { page++; render(); };

async function showMeta(file){
  let d;
  try { d = await (await fetch("/api/meta?file="+encodeURIComponent(file))).json(); }
  catch(e){ setMsg("Metadati non leggibili.", true); return; }
  const s = d.summary || {};
  const labels = {prompt:"Prompt", seed:"Seed", risoluzione:"Risoluzione", steps:"Step",
                  cfg:"CFG", sampler:"Sampler", uncensored:"Uncensored", upscaler:"Upscaler"};
  let kv = "";
  for (const k of ["seed","risoluzione","steps","cfg","sampler","uncensored","upscaler"])
    if (s[k] !== undefined) kv += `<b>${labels[k]}</b><span>${s[k]}</span>`;
  kv += `<b>File</b><span>${file}</span>`;
  $("#metakv").innerHTML = kv;
  $("#metaprompt").value = s.prompt || "(nessun prompt nei metadati - probabilmente un upscale)";
  $("#metadlg").showModal();
}
$("#metaclose").onclick = () => $("#metadlg").close();
$("#metadlg").addEventListener("click", e => { if (e.target.id === "metadlg") $("#metadlg").close(); });

function zoom(url){ $("#lbimg").src = url; $("#lb").showModal(); }
$("#lb").onclick = () => $("#lb").close();
function setMsg(t, err){ msg.textContent = t; msg.className = "msg" + (err?" err":""); }

// all'apertura: ricarica le ultime immagini gia' presenti in output/
async function loadGallery(){
  let res;
  try { res = await (await fetch("/api/galleria")).json(); } catch(e){ return; }
  (res.images || []).forEach(im => {
    items.push({id:++uid, status:"done", file:im.file, label:"salvata", canUpscale:!im.up});
  });
  render();
}
loadGallery();
</script>
</body>
</html>
"""

# ---------------------------------------------------------------------------
# Server HTTP
# ---------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path in ("/", "/index.html"):
            self._send(200, PAGE, "text/html; charset=utf-8"); return
        if u.path == "/api/quit":
            self._send(200, {"ok": True})
            # chiude il processo (= il server) poco dopo aver risposto al browser
            threading.Thread(target=lambda: (time.sleep(0.4), os._exit(0)), daemon=True).start()
            return
        if u.path.startswith("/img/"):
            name = os.path.basename(u.path[len("/img/"):])
            f = OUTPUT / name
            if f.exists(): self._send(200, f.read_bytes(), "image/png")
            else: self._send(404, "non trovata", "text/plain")
            return
        if u.path == "/api/galleria":
            imgs = []
            try:
                files = sorted(OUTPUT.glob("*.png"), key=lambda p: p.stat().st_mtime, reverse=True)[:24]
                imgs = [{"file": p.name, "up": p.name.startswith("Krea2_up")} for p in files]
            except Exception:
                pass
            self._send(200, {"images": imgs}); return

        if u.path == "/api/meta":
            name = os.path.basename(parse_qs(u.query).get("file", [""])[0])
            f = OUTPUT / name
            if not name or not f.exists():
                self._send(404, {"error": "non trovata"}); return
            fields = png_text_chunks(f)
            self._send(200, {"summary": png_summary(fields), "raw": fields.get("prompt", "")})
            return

        if u.path == "/api/stato":
            pid = parse_qs(u.query).get("id", [""])[0]
            try: h = comfy_get("/history/" + pid)
            except Exception: h = {}
            if pid in h:
                imgs = [im.get("filename") for o in h[pid].get("outputs", {}).values()
                        for im in o.get("images", [])]
                self._send(200, {"done": True, "images": imgs})
            else:
                self._send(200, {"done": False, "images": []})
            return
        self._send(404, "not found", "text/plain")

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(length) or b"{}")

        if path == "/api/upscale":
            self._upscale(req); return
        if path != "/api/genera":
            self._send(404, "not found", "text/plain"); return

        prompt = (req.get("prompt") or "").strip()
        if not prompt:
            self._send(400, {"error": "prompt vuoto"}); return
        nudo   = bool(req.get("nudo"))
        width  = int(req.get("width", 512)); height = int(req.get("height", 768))
        batch  = max(1, min(6, int(req.get("batch", 1))))
        seed_in = req.get("seed")
        jobs = []
        for i in range(batch):
            seed = int(seed_in) if (seed_in not in (None, "", 0) and batch == 1) else random.randint(0, 2**32 - 1)
            try:
                resp = comfy_post("/prompt", {"prompt": build_graph(prompt, nudo, width, height, seed)})
                jobs.append({"prompt_id": resp.get("prompt_id"), "seed": seed})
            except urllib.error.HTTPError as e:
                self._send(502, {"error": "ComfyUI ha rifiutato: " + e.read().decode()}); return
            except Exception as e:
                self._send(502, {"error": f"ComfyUI non raggiungibile ({e}). E' acceso sulla 8189?"}); return
        self._send(200, {"jobs": jobs})

    def _upscale(self, req):
        filename = os.path.basename(req.get("filename") or "")
        model    = req.get("model") or "4x_foolhardy_Remacri.pth"
        src = OUTPUT / filename
        if not filename or not src.exists():
            self._send(400, {"error": "immagine da upscalare non trovata"}); return
        # LoadImage legge da input/: copio li' il file generato
        try:
            INPUT.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, INPUT / filename)
        except Exception as e:
            self._send(500, {"error": f"copia in input/ fallita: {e}"}); return
        try:
            resp = comfy_post("/prompt", {"prompt": build_upscale_graph(filename, model)})
            self._send(200, {"prompt_id": resp.get("prompt_id")})
        except urllib.error.HTTPError as e:
            self._send(502, {"error": "ComfyUI ha rifiutato: " + e.read().decode()})
        except Exception as e:
            self._send(502, {"error": f"ComfyUI non raggiungibile ({e})."})


def main():
    print("=== Interfaccia Smart Krea 2 ===")
    ensure_comfy()
    print(f"Interfaccia su  http://127.0.0.1:{PORT}   (lascia questa finestra aperta)")
    try: webbrowser.open(f"http://127.0.0.1:{PORT}")
    except Exception: pass
    try:
        ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        print("\nChiuso.")

if __name__ == "__main__":
    main()
