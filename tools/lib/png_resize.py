#!/usr/bin/env python3
"""Redimensionne un PNG sans dépendance externe (ni ImageMagick, ni Pillow).

Supporte les PNG 8 bits non entrelacés : palette (3), gris (0), gris+alpha (4),
RGB (2), RGBA (6). Sort toujours en RGBA 8 bits.

Usage : png_resize.py <entree.png> <sortie.png> <largeur> [hauteur]
"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, 'rb').read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise SystemExit(f'{path} : ce n\'est pas un PNG')
    pos = 8
    idat = b''
    palette = b''
    trns = b''
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b'IHDR':
            w, h, depth, ctype, _comp, _filt, interlace = struct.unpack(
                '>IIBBBBB', body)
            if depth != 8 or interlace != 0:
                raise SystemExit(
                    f'{path} : PNG {depth} bits entrelacé={interlace} non géré')
        elif kind == b'PLTE':
            palette = body
        elif kind == b'tRNS':
            trns = body
        elif kind == b'IDAT':
            idat += body
        elif kind == b'IEND':
            break
    raw = zlib.decompress(idat)

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    stride = w * channels
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        # Défiltrage PNG (filtres 0 à 4).
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif f != 0:
            raise SystemExit(f'{path} : filtre PNG inconnu {f}')
        out[y * stride:(y + 1) * stride] = line
        prev = line

    # Normalisation en RGBA.
    rgba = bytearray(w * h * 4)
    if ctype == 6:
        rgba = out
    elif ctype == 2:
        for i in range(w * h):
            rgba[4 * i:4 * i + 4] = out[3 * i:3 * i + 3] + b'\xff'
    elif ctype == 0:
        for i in range(w * h):
            v = out[i]
            rgba[4 * i:4 * i + 4] = bytes((v, v, v, 255))
    elif ctype == 4:
        for i in range(w * h):
            v = out[2 * i]
            rgba[4 * i:4 * i + 4] = bytes((v, v, v, out[2 * i + 1]))
    elif ctype == 3:
        entries = len(palette) // 3
        for i in range(w * h):
            idx = out[i]
            if idx >= entries:
                idx = 0
            r, g, b = palette[3 * idx:3 * idx + 3]
            a = trns[idx] if idx < len(trns) else 255
            rgba[4 * i:4 * i + 4] = bytes((r, g, b, a))
    return w, h, rgba


def resample(w, h, rgba, dw, dh):
    """Moyenne de surface (bon rendu, pas de crénelage)."""
    out = bytearray(dw * dh * 4)
    xr = w / dw
    yr = h / dh
    for y in range(dh):
        y0, y1 = int(y * yr), max(int((y + 1) * yr), int(y * yr) + 1)
        for x in range(dw):
            x0, x1 = int(x * xr), max(int((x + 1) * xr), int(x * xr) + 1)
            r = g = b = a = n = 0
            for sy in range(y0, min(y1, h)):
                base = sy * w * 4
                for sx in range(x0, min(x1, w)):
                    i = base + sx * 4
                    r += rgba[i]
                    g += rgba[i + 1]
                    b += rgba[i + 2]
                    a += rgba[i + 3]
                    n += 1
            o = (y * dw + x) * 4
            if n:
                out[o:o + 4] = bytes((r // n, g // n, b // n, a // n))
    return out


def write_png(path, w, h, rgba):
    def chunk(kind, body):
        return (struct.pack('>I', len(body)) + kind + body +
                struct.pack('>I', zlib.crc32(kind + body) & 0xFFFFFFFF))

    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += rgba[y * w * 4:(y + 1) * w * 4]
    png = (b'\x89PNG\r\n\x1a\n' +
           chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
           chunk(b'IDAT', zlib.compress(bytes(raw), 9)) +
           chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    src, dst, dw = sys.argv[1], sys.argv[2], int(sys.argv[3])
    dh = int(sys.argv[4]) if len(sys.argv) > 4 else dw
    w, h, rgba = read_png(src)
    write_png(dst, dw, dh, resample(w, h, rgba, dw, dh))
    print(f'{dst} : {dw}x{dh} (depuis {w}x{h})')


if __name__ == '__main__':
    main()
