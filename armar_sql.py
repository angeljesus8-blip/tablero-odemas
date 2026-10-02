# -*- coding: utf-8 -*-
"""Junta los .sql en el UNICO orden en que se pueden pegar.

    python armar_sql.py        -> escribe supabase_TODO.sql
    python armar_sql.py -v     -> ademas explica por que va cada uno donde va

POR QUE EXISTE ESTO
-------------------
Los .sql no son un esquema: son la historia de parches de una tienda, escritos
uno detras de otro a lo largo de un mes. Catorce funciones estan definidas en
mas de un archivo —`venta_guardar` en cuatro— y al pegar GANA LA ULTIMA. Pegar
en desorden no da error: deja corriendo una version vieja de la funcion que
guarda las ventas, y eso no se nota hasta que los numeros no cuadran.

El orden no siempre es la fecha. Los casos que hay que respetar estan en
POR_QUE, abajo, y `comprobar()` verifica que se cumplan antes de escribir nada.
"""
import io, os, re, sys

# El orden. Cada bloque es una etapa; dentro, el orden es el que importa.
ORDEN = [
 ('Base — la tienda y quien entra', [
   'supabase_00_tiendas.sql',
   'supabase_empleados.sql',
   'supabase_acceso.sql',
   'supabase_admin_por_empleado.sql',
   'supabase_cuenta_subgerente.sql',
   'supabase_hoja_auth.sql',
 ]),
 ('Esquema y lecturas', [
   'supabase_migracion_esquema.sql',
   'supabase_funciones_lectura.sql',
   'supabase_funciones_lectura_resto.sql',
   'supabase_horarios.sql',
   'supabase_venta_guardar.sql',
   'supabase_ventas_devolucion.sql',
   'supabase_preventa_cupo.sql',
 ]),
 ('Escrituras, cargas y avisos', [
   'supabase_cargas_admin.sql',
   'supabase_escrituras_resto.sql',
   'supabase_fotos_venta.sql',
   'supabase_inventario_preventa.sql',
   'supabase_preventa_series.sql',
   'supabase_notificaciones.sql',
   'supabase_notif_diagnostico.sql',
   'supabase_apartados_traspaso.sql',
   'supabase_attach_preventa.sql',
   'supabase_attach_apartados.sql',
   'supabase_puesto_en_sesion.sql',
 ]),
 ('Lo ultimo de agosto', [
   'supabase_venta_editar.sql',
   'supabase_venta_exhibicion.sql',
   'supabase_ventas_detalle_entrega.sql',
   'supabase_venta_grupo.sql',
   'supabase_equipo_por_numero.sql',
   'supabase_token_alta.sql',
 ]),
 ('Septiembre — cada quien ve lo suyo', [
   'supabase_comisiones_privadas.sql',
   'supabase_alta_por_invitacion.sql',
   'supabase_venta_capturado_por.sql',
   'supabase_llaves_tienda.sql',
   'supabase_permiso_por_sesion.sql',
 ]),
 ('26-sep-2026 — el precio de lista no es una promo', [
   'supabase_precio_lista.sql',
 ]),
 ('2-oct-2026 — el candado de las lecturas', [
   'supabase_candado.sql',
 ]),
]

# (antes, despues, por que). `comprobar()` los verifica contra ORDEN.
POR_QUE = [
 ('supabase_preventa_series.sql', 'supabase_precio_lista.sql',
  'carga_precio_lista se protege con escritura_ok_, que nace en preventa_series'),
 ('supabase_migracion_esquema.sql', 'supabase_precio_lista.sql',
  'el trigger vive en catalogo y la funcion borra de promos: las dos tablas '
  'tienen que existir antes'),
 ('supabase_00_tiendas.sql', 'supabase_migracion_esquema.sql',
  'las diez tablas llevan store_id REFERENCES tiendas: sin la tabla, el esquema '
  'falla en su primera linea'),
 ('supabase_admin_por_empleado.sql', 'supabase_hoja_auth.sql',
  'los dos hacen DROP y recrean login_empleado, y solo la de hoja_auth devuelve '
  'gas_token. Al reves, el login deja de entregar la clave de escritura: la app '
  'entra, se ve entera y no guarda NADA, sin dar un error'),
 ('supabase_cuenta_subgerente.sql', 'supabase_migracion_esquema.sql',
  'las politicas RLS del esquema llaman a admin_de(), que se define ahi'),
 ('supabase_cuenta_subgerente.sql', 'supabase_puesto_en_sesion.sql',
  'puesto_en_sesion trae la version de vincular_mi_cuenta que ademas devuelve '
  'el puesto; la de antes deja al subgerente sin poder editar'),
 ('supabase_migracion_esquema.sql', 'supabase_preventa_cupo.sql',
  'los dos definen apartado_cabe, el trigger que impide apartar mas piezas de '
  'las que hay. Gana el de preventa_cupo'),
 ('supabase_funciones_lectura.sql', 'supabase_venta_exhibicion.sql',
  'venta_exhibicion trae la version buena de inventario_vivo y eol_precio_venta: '
  'la que sabe de piezas de exhibicion. Con la vieja, el stock miente'),
 ('supabase_venta_guardar.sql', 'supabase_escrituras_resto.sql', 'venta_guardar, v2'),
 ('supabase_escrituras_resto.sql', 'supabase_venta_exhibicion.sql', 'venta_guardar, v3'),
 ('supabase_venta_exhibicion.sql', 'supabase_venta_grupo.sql',
  'venta_guardar, v4 y definitiva: la que sabe agrupar varias piezas en una '
  'venta. Es la funcion que da de comer a la tienda; que gane la ultima'),
 ('supabase_attach_preventa.sql', 'supabase_attach_apartados.sql',
  'los dos redefinen ventas_hoy y son del MISMO dia, asi que la fecha no decide. '
  'La de apartados hace lo mismo que la otra Y ADEMAS suma los apartados '
  'cobrados hoy. Al reves se pierde esa suma y el attach del dia sale bajo'),
 ('supabase_hoja_auth.sql', 'supabase_equipo_por_numero.sql',
  'recrea los dos logins para que `hoja_auth` salga de la ficha de la persona '
  'y no del texto escrito a mano. Al reves gana la version vieja y la marca no '
  'se mira: el boton de «Ventas del dia» se queda como estaba, sin dar error'),
 ('supabase_cargas_admin.sql', 'supabase_token_alta.sql',
  'token_alta va al final: necesita la tabla y no la toca nadie despues'),
 ('supabase_preventa_series.sql', 'supabase_token_alta.sql',
  'escritura_ok_ se define en preventa_series y token_alta la explica'),
 ('supabase_funciones_lectura_resto.sql', 'supabase_comisiones_privadas.sql',
  'los dos definen comisiones_lista. La de lectura_resto es la de UN argumento, '
  'que devuelve el sueldo del equipo entero —y en esta copia el de CUALQUIER '
  'tienda— a quien traiga la clave publicable, que viaja dentro del HTML. Al '
  'reves se recrea esa version y se deshace el REVOKE: la app sigue viendose '
  'igual y el agujero queda abierto, sin dar un error'),
 ('supabase_preventa_series.sql', 'supabase_comisiones_privadas.sql',
  'comisiones_privadas llama a escritura_ok_ y ademas la EXIGE al empezar: sin '
  'ella el archivo se planta con un RAISE en vez de crear la funcion a medias'),
 ('supabase_venta_editar.sql', 'supabase_comisiones_privadas.sql',
  'lo mismo con puede_gestionar_, que es quien decide si gerente y subgerente '
  'ven al equipo'),
 ('supabase_migracion_esquema.sql', 'supabase_alta_por_invitacion.sql',
  'alta_tienda escribe en tiendas y empleados, y una funcion LANGUAGE plpgsql '
  'no se valida al crearse: si las tablas no estan, esto se pega sin una queja '
  'y revienta el dia que alguien abre una tienda'),
 ('supabase_venta_grupo.sql', 'supabase_venta_capturado_por.sql',
  'venta_guardar, v5: la de venta_grupo con p_token y ademas p_quien, y '
  'ventas_detalle con capturado_por. Al reves gana la v4, la app que manda '
  'p_quien recibe PGRST202 y deja de guardar ventas'),
 ('supabase_preventa_series.sql', 'supabase_venta_capturado_por.sql',
  'venta_guardar llama a escritura_ok_, que se define en preventa_series'),
 ('supabase_equipo_por_numero.sql', 'supabase_permiso_por_sesion.sql',
  'los dos definen empleado_permiso. La de permiso_por_sesion deja dar de baja '
  'tambien al gerente que entra con correo (sin numero de empleado). Al reves '
  'gana la vieja y ese gerente vuelve a leer «no administras esta tienda»'),
 ('supabase_cuenta_subgerente.sql', 'supabase_permiso_por_sesion.sql',
  'empleado_permiso llama a admin_de, que se define en cuenta_subgerente'),
 ('supabase_alta_por_invitacion.sql', 'supabase_llaves_tienda.sql',
  'la llave de invitaciones.usado_store necesita la tabla invitaciones, que se '
  'crea en alta_por_invitacion. Al reves el ALTER TABLE falla y el pegado se '
  'queda a medias'),
 ('supabase_empleados.sql', 'supabase_llaves_tienda.sql',
  'la llave de empleados.store_id necesita la tabla empleados'),
 ('supabase_precio_lista.sql', 'supabase_candado.sql',
  'el candado renombra la version VIVA de ocho lecturas y redirige a quien las '
  'llama: si algun archivo las redefine despues, vuelve a crear la puerta abierta '
  'y el candado no sirve, sin dar un error'),
 ('supabase_preventa_series.sql', 'supabase_candado.sql',
  'candado_ok_ llama a escritura_ok_, que se define en preventa_series'),
 ('supabase_venta_exhibicion.sql', 'supabase_candado.sql',
  'renombra inventario_vivo y eol_precio_venta: tiene que ser la version buena'),
 ('supabase_apartados_traspaso.sql', 'supabase_candado.sql',
  'renombra apartados_lista: tiene que ser la version con cupo y dias_tarde'),
 ('supabase_token_alta.sql', 'supabase_alta_por_invitacion.sql',
  'la tienda nace SIN gas_token escrito a mano: lo pone el DEFAULT que instala '
  'token_alta. Al reves, la tienda se crea y no puede guardar ni una venta '
  '-escritura_ok_ rechaza todo lo que llegue sin token-, y nada lo dice'),
]

# Cual es la version buena de cada funcion que aparece en varios archivos.
# Escrito a mano y comprobado una por una: es lo unico que separa un sistema que
# funciona de uno que corre una version vieja de la funcion que guarda ventas.
ESPERADO_GANA = {
  'login_asesor':               'supabase_equipo_por_numero.sql',
  'login_empleado':             'supabase_equipo_por_numero.sql',
  'vincular_mi_cuenta':         'supabase_puesto_en_sesion.sql',
  'apartado_cabe':              'supabase_preventa_cupo.sql',
  'apartado_guardar':           'supabase_apartados_traspaso.sql',
  'apartados_lista':            'supabase_apartados_traspaso.sql',
  'avisos_vigentes':            'supabase_escrituras_resto.sql',
  'inventario_vivo':            'supabase_venta_exhibicion.sql',
  'eol_precio_venta':           'supabase_venta_exhibicion.sql',
  'venta_guardar':              'supabase_venta_capturado_por.sql',
  'ventas_detalle':             'supabase_venta_capturado_por.sql',
  'ventas_hoy':                 'supabase_attach_apartados.sql',
  'comisiones_lista':           'supabase_comisiones_privadas.sql',
  'empleado_permiso':           'supabase_permiso_por_sesion.sql',
  'tablero_todo':               'supabase_candado.sql',
}

SALIDA = 'supabase_TODO.sql'
BASE = os.path.dirname(os.path.abspath(__file__))
LISTA = [n for _, g in ORDEN for n in g]


def comprobar():
    """Que la lista sea completa y que se respeten las precedencias."""
    problemas = []
    pos = {n: i for i, n in enumerate(LISTA)}

    # SALIDA fuera: es lo que genera este script, no una fuente.
    hay = set(n for n in os.listdir(BASE)
              if re.match(r'supabase_.*\.sql$', n) and n != SALIDA)
    for n in LISTA:
        if n not in hay:
            problemas.append('%s esta en la lista y no en la carpeta' % n)
    # Lo contrario importa mas: un .sql que nadie pega es una funcion que no
    # existira, y eso se descubre en produccion.
    for n in sorted(hay - set(LISTA)):
        problemas.append('%s esta en la carpeta y NO en la lista: no se pegaria' % n)

    for antes, despues, motivo in POR_QUE:
        if antes in pos and despues in pos and pos[antes] > pos[despues]:
            problemas.append('%s tiene que ir ANTES de %s — %s' % (antes, despues, motivo))
    return problemas


def quien_gana(texto):
    """Que archivo aporta la ULTIMA definicion de cada funcion repetida.

    Es la comprobacion que de verdad importa, y se hace sobre el archivo
    generado y no sobre la lista: el orden puede estar bien escrito y aun asi
    dejar ganando a la version equivocada, porque una funcion aparece en cuatro
    archivos y no en dos. Se mira el texto final, que es lo que se pega."""
    marcas = [(m.start(), m.group(1))
              for m in re.finditer(r'-- ={10} (\S+) ={10}', texto)]

    def de_quien(pos):
        quien = '?'
        for p, n in marcas:
            if p <= pos:
                quien = n
            else:
                break
        return quien

    # Los comentarios se blanquean en vez de borrarse, para no mover las
    # posiciones: si se movieran, cada funcion se atribuiria al archivo de al lado.
    limpio = re.sub(r'--[^\n]*', lambda m: ' ' * len(m.group(0)), texto)
    limpio = re.sub(r'/\*.*?\*/', lambda m: ' ' * len(m.group(0)), limpio, flags=re.S)

    defs = {}
    for m in re.finditer(r'create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?(\w+)',
                         limpio, re.I):
        defs.setdefault(m.group(1), []).append(m.start())
    return {n: [de_quien(p) for p in ps] for n, ps in defs.items() if len(ps) > 1}


def main():
    verboso = '-v' in sys.argv
    problemas = comprobar()
    if problemas:
        print('NO se escribio nada:')
        for p in problemas:
            print('  · ' + p)
        return 1

    partes = []
    for etapa, grupo in ORDEN:
        partes.append(u'\n\n' + u'-' * 62 + u'\n--  ETAPA: %s\n' % etapa + u'-' * 62 + u'\n')
        for n in grupo:
            with io.open(os.path.join(BASE, n), encoding='utf-8', errors='replace') as f:
                partes.append(u'\n\n-- ========== %s ==========\n\n' % n + f.read())

    cab = (u'-- Generado por armar_sql.py. No se edita a mano: se edita el .sql\n'
           u'-- que toque y se vuelve a generar, o el cambio se pierde.\n'
           u'--\n'
           u'-- Se pega ENTERO en el SQL Editor de Supabase, de una vez y en este\n'
           u'-- orden. Cada archivo lleva al final sus propias comprobaciones.\n'
           u'--\n-- %d archivos, en %d etapas.\n' % (len(LISTA), len(ORDEN)))

    texto = cab + u''.join(partes)

    # Que gane quien tiene que ganar. Se comprueba ANTES de escribir: un
    # supabase_TODO.sql a medio revisar es peor que ninguno, porque se pega.
    gana = quien_gana(texto)
    malos = []
    for n, quienes in sorted(gana.items()):
        if n in ESPERADO_GANA and quienes[-1] != ESPERADO_GANA[n]:
            malos.append('%s: gana %s y tenia que ganar %s'
                         % (n, quienes[-1], ESPERADO_GANA[n]))
    if malos:
        print('NO se escribio nada — el orden deja ganando la version equivocada:')
        for m in malos:
            print('  · ' + m)
        return 1

    salida = os.path.join(BASE, SALIDA)
    with io.open(salida, 'w', encoding='utf-8', newline='') as f:
        f.write(texto)
    print('supabase_TODO.sql — %d archivos, %d lineas, %d funciones repetidas resueltas' %
          (len(LISTA), len(texto.splitlines()), len(gana)))

    if verboso:
        print('\nOrden y por que:')
        i = 0
        for etapa, grupo in ORDEN:
            print('\n  %s' % etapa.upper())
            for n in grupo:
                i += 1
                motivos = [m for a, d, m in POR_QUE if d == n]
                print('   %2d. %-38s %s' % (i, n, motivos[0] if motivos else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
