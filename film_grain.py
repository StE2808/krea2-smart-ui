#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Grana fotografica realistica in post (chiamato dal server via il python del venv ComfyUI).

Diversa dal reticolo uniforme degli upscaler ESRGAN: rumore CASUALE, monocromatico
(grana di luminanza) e MODULATO per luminanza (max nei mezzitoni, ~0 nel bianco e nelle
ombre profonde). Usato per rifinire un upscale Remacri: la grana casuale maschera il
reticolo regolare lasciato dal modello e da' un look pellicola.

Uso:  python film_grain.py  input.png  output.png  [strength=0.04]  [grain_size=1.6]
"""
import sys
import numpy as np
from PIL import Image


def add_film_grain(img, strength=0.02, grain_size=1.0, shadow_keep=0.15, seed=0):
    """img: array HxWx3 float 0..1 -> stessa cosa con grana.
    strength    = intensita' base (0.03 delicata, 0.08 marcata)
    grain_size  = dimensione del grano in px (1.0 finissima, 2-3 = 35mm grosso)
    shadow_keep = quanto tenere la grana nelle ombre (0=spegne, 1=piena)
    """
    rng = np.random.default_rng(seed)
    h, w, _ = img.shape

    # rumore generato a risoluzione ridotta e riscalato -> grano piu' grosso/organico
    sh, sw = max(1, int(h / grain_size)), max(1, int(w / grain_size))
    noise = rng.standard_normal((sh, sw)).astype(np.float32)
    if (sh, sw) != (h, w):
        noise = np.array(Image.fromarray(noise).resize((w, h), Image.BILINEAR), dtype=np.float32)
    noise -= noise.mean()
    noise /= (noise.std() + 1e-6)          # rumore normalizzato, media 0

    # luminanza per modulare: la grana e' visibile soprattutto nei mezzitoni
    L = img @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    midtone = 1.0 - (2.0 * L - 1.0) ** 2                   # 1 a L=0.5, 0 agli estremi
    weight = shadow_keep + (1.0 - shadow_keep) * np.clip(midtone, 0, 1)
    # nelle alte luci quasi pure togli quasi tutto (cielo che resta pulito)
    weight *= np.clip(1.0 - np.clip((L - 0.85) / 0.15, 0, 1) * 0.9, 0, 1)

    grain = (noise * weight * strength)[..., None]
    return np.clip(img + grain, 0, 1)


if __name__ == "__main__":
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src.rsplit(".", 1)[0] + "_grain.png"
    strength = float(sys.argv[3]) if len(sys.argv) > 3 else 0.02
    grain_size = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    im = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255.0
    out = add_film_grain(im, strength=strength, grain_size=grain_size)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8)).save(dst)
    print("salvato:", dst, "| strength", strength, "| grain_size", grain_size)
