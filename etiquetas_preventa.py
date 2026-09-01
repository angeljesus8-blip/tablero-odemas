#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Etiquetas recortables para pegar en las cajas de preventa.

    python etiquetas_preventa.py

Saca los apartados de Supabase y arma un PDF carta con una etiqueta por cliente,
para recortar y pegar en su caja. Con seis Orange Ocean idénticos en bodega, la
etiqueta es lo que evita entregar la pieza de otro.

EL PDF NO VA AL REPO. Lleva nombre y teléfono de clientes y este repositorio es
público, así que se escribe en ../_privado_no_publicar/, que está fuera de él.
Ver la regla `personales` de verificar.py.

La serie va en monoespaciada y grande a propósito: se coteja dígito a dígito
contra la etiqueta de la caja, y en tipografía proporcional el 0/O y el 1/I se
confunden justo cuando hay prisa.
"""
import io, json, os, sys, urllib.request

from reportlab.lib.pagesizes import letter
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

SB_URL = 'https://ecuqtqxmdehzbbsmlxrh.supabase.co'
SB_KEY = 'sb_publishable_ANNakHYo8KtRhKHcU6XiyQ_DRRXMlce'
STORE  = '1217'

BASE  = os.path.dirname(os.path.abspath(__file__))
LOGO  = os.path.join(BASE, '..', '07_Look&feel', 'logo odemas Vt color.png')
SALIDA_DIR = os.path.join(BASE, '..', '_privado_no_publicar')
SALIDA = os.path.join(SALIDA_DIR, 'etiquetas_preventa_pura90s.pdf')

# Colores Odemás (Manual-Logo-Odemas.md)
ROJO    = (0xD1/255, 0x20/255, 0x26/255)
NARANJA = (0xF3/255, 0x70/255, 0x21/255)
AZUL    = (0x33/255, 0x6B/255, 0xB4/255)
VERDE   = (0x1a/255, 0x8c/255, 0x4e/255)
GRIS    = (0.45, 0.45, 0.45)
LINEA   = (0.80, 0.80, 0.80)


def apartados():
    req = urllib.request.Request(
        SB_URL + '/rest/v1/rpc/apartados_lista',
        data=json.dumps({'p_store': STORE}).encode('utf-8'),
        headers={'apikey': SB_KEY, 'Authorization': 'Bearer ' + SB_KEY,
                 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=20) as r:
        filas = json.loads(r.read().decode('utf-8'))
    # Los cancelados no se imprimen: esa pieza ya no es de nadie.
    vivos = [f for f in filas if (f.get('estatus') or '') != 'Cancelado']
    vivos.sort(key=lambda f: ((f.get('color') or ''), (f.get('cliente') or '')))
    return vivos


def partir_producto(color):
    """`color` trae el producto entero: 'Pura 90S Pro Max 12/512GB · Graphite Black'.

    Se guardó así el 4-ago-2026 para no tener que deducir el modelo por el
    precio (ver MAPA, cadena 2-bis). Aquí se vuelve a separar para poder darle
    a cada parte su tamaño.
    """
    txt = (color or '').strip()
    if '·' in txt:
        modelo, col = txt.split('·', 1)
        return modelo.strip(), col.strip()
    return txt, ''


def recorta(c, x, y, w, h):
    """Marco punteado: la línea por donde se corta."""
    c.saveState()
    c.setStrokeColorRGB(*LINEA)
    c.setLineWidth(0.4)
    c.setDash(2, 2)
    c.rect(x, y, w, h)
    c.restoreState()


def encoge(c, texto, fuente, tam, ancho):
    """Baja el tamaño hasta que el texto quepa. Nombres largos los hay
    —'Adrian ortega hernandez'— y recortarlos con puntos suspensivos en una
    etiqueta que sirve para identificar a una persona es justo lo que no."""
    while tam > 6 and c.stringWidth(texto, fuente, tam) > ancho:
        tam -= 0.5
    return tam


def etiqueta(c, x, y, w, h, a, logo):
    recorta(c, x, y, w, h)
    m = 5 * mm                       # margen interno
    ix, iw = x + m, w - 2 * m
    top = y + h - m

    # ── cabecera: logo + PREVENTA ──
    if logo:
        try:
            c.drawImage(logo, ix, top - 7*mm, width=18*mm, height=7*mm,
                        preserveAspectRatio=True, anchor='sw', mask='auto')
        except Exception:
            pass                      # sin logo la etiqueta sirve igual
    c.setFont('Helvetica-Bold', 7)
    c.setFillColorRGB(*NARANJA)
    c.drawRightString(x + w - m, top - 4*mm, 'PREVENTA PURA 90S')
    cur = top - 11*mm

    # ── cliente ──
    nombre = (a.get('cliente') or '(sin nombre)').upper()
    tam = encoge(c, nombre, 'Helvetica-Bold', 13, iw)
    c.setFont('Helvetica-Bold', tam)
    c.setFillColorRGB(0.1, 0.1, 0.1)
    c.drawString(ix, cur, nombre)
    cur -= 5*mm

    tel = (a.get('telefono') or '').strip()
    if tel:
        c.setFont('Helvetica', 8.5)
        c.setFillColorRGB(*GRIS)
        c.drawString(ix, cur, 'Tel. ' + tel)
    cur -= 5.5*mm

    # ── producto ──
    modelo, color = partir_producto(a.get('color'))
    c.setFont('Helvetica-Bold', 8.5)
    c.setFillColorRGB(*AZUL)
    c.drawString(ix, cur, modelo[:44])
    cur -= 4.2*mm
    if color:
        c.setFont('Helvetica', 8.5)
        c.setFillColorRGB(0.25, 0.25, 0.25)
        c.drawString(ix, cur, color)
    cur -= 6*mm

    # ── serie: lo que se coteja contra la caja ──
    serie = (a.get('serie') or '').strip()
    caja_h = 7*mm
    c.setFillColorRGB(0.96, 0.96, 0.97)
    c.setStrokeColorRGB(*LINEA); c.setLineWidth(0.5)
    c.rect(ix, cur - 1.5*mm, iw, caja_h, fill=1, stroke=1)
    if serie:
        c.setFont('Courier-Bold', 10)
        c.setFillColorRGB(0.1, 0.1, 0.1)
        c.drawString(ix + 2*mm, cur + 0.7*mm, 'N/S ' + serie)
    else:
        # Sin serie la etiqueta no sirve para su único fin: identificar LA caja.
        # Se imprime igual, marcado, para que se vea que falta ligarla.
        c.setFont('Helvetica-Bold', 9)
        c.setFillColorRGB(*ROJO)
        c.drawString(ix + 2*mm, cur + 0.7*mm, 'FALTA LIGAR LA SERIE')
    cur -= 7.5*mm

    # ── pie: ticket + seguro ──
    c.setFont('Helvetica', 7.5)
    c.setFillColorRGB(*GRIS)
    tx = (a.get('transaccion') or '').strip()
    c.drawString(ix, cur, ('Ticket ' + tx) if tx else 'sin ticket')

    if a.get('con_seguro'):
        et = 'CON SEGURO'
        c.setFont('Helvetica-Bold', 7.5)
        an = c.stringWidth(et, 'Helvetica-Bold', 7.5) + 4*mm
        c.setFillColorRGB(0.91, 0.98, 0.94)
        c.rect(x + w - m - an, cur - 1.2*mm, an, 4.6*mm, fill=1, stroke=0)
        c.setFillColorRGB(*VERDE)
        c.drawCentredString(x + w - m - an/2, cur, et)


def main():
    filas = apartados()
    if not filas:
        print('No hay apartados que imprimir.')
        return 1

    if not os.path.isdir(SALIDA_DIR):
        os.makedirs(SALIDA_DIR)

    logo = LOGO if os.path.exists(LOGO) else None
    if not logo:
        print('aviso: no encontré el logo en 07_Look&feel — sale sin él')

    W, H = letter
    cols, fils = 2, 5
    mx, my = 10*mm, 10*mm                       # márgenes de hoja
    w = (W - 2*mx) / cols
    h = (H - 2*my) / fils

    c = canvas.Canvas(SALIDA, pagesize=letter)
    c.setTitle('Etiquetas preventa Pura 90S · HES 1217')

    for i, a in enumerate(filas):
        pos = i % (cols * fils)
        if i and pos == 0:
            c.showPage()
        col, fil = pos % cols, pos // cols
        x = mx + col * w
        y = H - my - (fil + 1) * h
        etiqueta(c, x + 2*mm, y + 2*mm, w - 4*mm, h - 4*mm, a, logo)

    c.showPage()
    c.save()

    sin_serie = [f for f in filas if not (f.get('serie') or '').strip()]
    print('PDF: %s' % os.path.normpath(SALIDA))
    print('%d etiquetas · %d hoja(s)' % (len(filas), (len(filas) + 9) // 10))
    if sin_serie:
        print('OJO: %d sin serie, salen marcadas en rojo:' % len(sin_serie))
        for f in sin_serie:
            print('   - ' + (f.get('cliente') or ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
