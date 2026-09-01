# -*- coding: utf-8 -*-
"""Apunta esta copia a SU proyecto de Supabase.

    python configurar.py
        Dice a qué proyecto apunta hoy cada archivo. No escribe nada.

    python configurar.py https://xxxx.supabase.co sb_publishable_xxxx
        Lo escribe en los 10 archivos de una vez y comprueba que no quede
        ninguna referencia al proyecto anterior.

POR QUE EXISTE ESTO
-------------------
La URL y la clave no están en un archivo de configuración: están escritas en
cada página, con un nombre distinto en cada una (`SB_URL`, `SB_URL_AD`,
`SB_URL_CS`, `SB_URL_CO`, `SUPABASE_URL`). Cambiarlas a mano es abrir diez
archivos y acertar en todos; olvidar UNO no da error visible: esa pantalla
sigue funcionando —contra la base equivocada—. Una captura de series hecha
desde ahí escribe una venta real en la tienda de origen, y ahí sí descuadra el
inventario de gente que está vendiendo.

Por eso se cambia todo de golpe y se comprueba al final que no quede rastro.
"""
import io, os, re, sys

BASE = os.path.dirname(os.path.abspath(__file__))

# Todo lo que lleva la URL o la clave escrita. Los dos .py no se publican, pero
# hablan con la misma base: etiquetas_preventa.py lee los apartados para
# imprimir las etiquetas y preventa_cupo_gen.py nombra el proyecto en el SQL
# que genera.
ARCHIVOS = ['index.html', 'tablero.html', 'captura_series.html', 'admin.html',
            'comisiones.html', 'actualizar_datos.html', 'horarios.html',
            'accesorios_tecnico.html', 'etiquetas_preventa.py',
            'preventa_cupo_gen.py']

RX_URL = re.compile(r'https://([a-z0-9]{16,32})\.supabase\.co')
RX_KEY = re.compile(r'sb_publishable_[A-Za-z0-9_-]{16,}')

# El proyecto del planeador, apagado en agosto de 2026. Aparece en un comentario
# histórico de horarios.html que explica por qué ya no se usa: si se sustituyera,
# el comentario pasaría a mentir.
HISTORICO = {'lgnyqfstmcqpkbekspte'}


def leer(p):
    with io.open(os.path.join(BASE, p), encoding='utf-8') as f:
        return f.read()


def escribir(p, s):
    with io.open(os.path.join(BASE, p), 'w', encoding='utf-8', newline='') as f:
        f.write(s)


def refs_por_url():
    """Los identificadores de proyecto que aparecen como URL en algún archivo.

    Sirve para reconocer un ref suelto en un comentario sin confundirlo con
    cualquier otra palabra larga."""
    todos = set()
    for p in ARCHIVOS:
        try:
            todos |= set(RX_URL.findall(leer(p)))
        except OSError:
            pass
    return todos - HISTORICO


def estado():
    """Qué ref de proyecto y qué clave usa cada archivo."""
    conocidos = refs_por_url()
    refs, claves, faltan = {}, {}, []
    for p in ARCHIVOS:
        try:
            s = leer(p)
        except OSError:
            faltan.append(p)
            continue
        r = [x for x in RX_URL.findall(s) if x not in HISTORICO]
        # preventa_cupo_gen.py nombra el proyecto sin URL, dentro de un
        # comentario del SQL que genera. Cuenta igual: si dice el proyecto
        # equivocado, el SQL se pega donde no es.
        if not r:
            r = [x for x in re.findall(r'\b([a-z0-9]{16,32})\b', s)
                 if x in conocidos]
        k = RX_KEY.findall(s)
        if r:
            refs.setdefault(r[0], []).append(p)
        if k:
            claves.setdefault(k[0], []).append(p)
    return refs, claves, faltan


def mostrar():
    refs, claves, faltan = estado()
    for p in faltan:
        print('  falta el archivo %s' % p)
    if not refs:
        print('Ningún archivo tiene URL de Supabase. Algo va mal.')
        return 1
    print('Proyecto al que apunta cada archivo:\n')
    for r, ps in sorted(refs.items(), key=lambda x: -len(x[1])):
        print('  https://%s.supabase.co  (%d archivos)' % (r, len(ps)))
        for p in ps:
            print('      %s' % p)
    print('\nClaves publicables en uso: %d' % len(claves))
    for k, ps in sorted(claves.items(), key=lambda x: -len(x[1])):
        print('  %s...  en %d archivos' % (k[:24], len(ps)))
    if len(refs) > 1:
        print('\nOJO: apuntan a MÁS DE UN proyecto. Unas pantallas escriben en '
              'una base y otras en otra, sin dar error.')
        return 1
    print('\n  python configurar.py <URL> <clave publicable>   para cambiarlo')
    return 0


def validar(url, key):
    problemas = []
    if not re.match(r'^https://[a-z0-9]{16,32}\.supabase\.co/?$', url):
        problemas.append('La URL tiene que ser https://xxxx.supabase.co, tal cual '
                         'sale en Settings -> API -> Project URL. Recibí: %s' % url)
    if key.startswith('sb_secret_') or 'service_role' in key:
        problemas.append('Esa es la clave SECRETA. Va escrita en HTML público: '
                         'quien abra la página tendría permiso total sobre la '
                         'base, saltándose la RLS. Usa la publicable.')
    elif key.startswith('eyJ'):
        problemas.append('Esa es la anon key en formato JWT (la antigua). '
                         'verificar.py bloquea el commit al verla, porque a '
                         'simple vista no se distingue de una service_role. En '
                         'Settings -> API usa la publicable, la que empieza por '
                         'sb_publishable_.')
    elif not key.startswith('sb_publishable_'):
        problemas.append('La clave publicable empieza por sb_publishable_. '
                         'Recibí algo que no lo hace.')
    return problemas


def aplicar(url, key):
    problemas = validar(url, key)
    if problemas:
        print('NO se cambió nada:')
        for p in problemas:
            print('  · ' + p)
        return 1

    url = url.rstrip('/')
    ref_nuevo = RX_URL.match(url).group(1)
    refs, _, faltan = estado()
    if faltan:
        print('NO se cambió nada: falta(n) %s' % ', '.join(faltan))
        return 1
    viejos = [r for r in refs if r != ref_nuevo]

    tocados = []
    for p in ARCHIVOS:
        original = leer(p)
        s = RX_URL.sub(lambda m: m.group(0) if m.group(1) in HISTORICO else url,
                       original)
        s = RX_KEY.sub(key, s)
        # El ref suelto en comentarios (preventa_cupo_gen.py nombra el proyecto
        # donde se pega el SQL). Va después de las URLs para no partirlas.
        for viejo in viejos:
            s = s.replace(viejo, ref_nuevo)
        if s != original:
            escribir(p, s)
            tocados.append(p)

    # Comprobar sobre lo escrito, no sobre lo que creemos haber escrito: el
    # archivo que se olvida es justo el que nadie mira.
    refs, claves, _ = estado()
    malos = [r for r in refs if r != ref_nuevo]
    if malos or len(claves) > 1:
        print('Se escribió, pero quedó rastro del proyecto anterior:')
        for r in malos:
            print('  · %s sigue en: %s' % (r, ', '.join(refs[r])))
        if len(claves) > 1:
            print('  · hay %d claves distintas en uso' % len(claves))
        return 1

    print('%d archivos apuntan ahora a %s' % (len(tocados), url))
    for p in tocados:
        print('   · %s' % p)
    print('\nFalta:')
    print('  1. python verificar.py      (tiene que decir "Todo en orden")')
    print('  2. subir VERSION en sw.js — cambiaron los .html y el service worker')
    print('     sirve los viejos desde la caché, sin avisar')
    print('  3. el alta de la tienda se hace desde la app: menú -> Registrar tienda')
    return 0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    if not args:
        return mostrar()
    if len(args) != 2:
        print(__doc__)
        return 1
    return aplicar(args[0], args[1])


if __name__ == '__main__':
    sys.exit(main())
