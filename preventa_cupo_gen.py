#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Genera supabase_preventa_cupo.sql leyendo los cupos de tablero.html.

    python preventa_cupo_gen.py

El cupo tiene que vivir en dos lados: en `tablero.html` (lo que ve el asesor) y
en la tabla `preventa_cupo` de Supabase (el tope que de verdad frena dos
apartados simultáneos). Escribirlo a mano en los dos es como se desincronizan
las cosas: aquí se escribe UNA vez, en la const PREVENTA, y el SQL se genera.

Al cambiar un cupo: edita `tablero.html`, corre esto, pega el SQL resultante.
"""
import io, os, re, sys

BASE = os.path.dirname(os.path.abspath(__file__))
STORE = '1217'


def cupos_de_tablero():
    html = io.open(os.path.join(BASE, 'tablero.html'), encoding='utf-8').read()
    m = re.search(r'const PREVENTA = \[(.*?)\n\];', html, re.S)
    if not m:
        sys.exit('No encontré la const PREVENTA en tablero.html')
    filas = re.findall(r"sku:'(\d+)'.*?color:'([^']+)'.*?cupo:(\d+)", m.group(1))
    if not filas:
        sys.exit('La const PREVENTA no trae ningún sku con cupo')
    return [(sku, color, int(n)) for sku, color, n in filas]


def main():
    filas = cupos_de_tablero()
    total = sum(n for _, _, n in filas)
    # La coma va ANTES del comentario: si va después queda DENTRO de él, se
    # pierde, y el INSERT sale sin separar las filas.
    lineas = []
    for i, (sku, color, n) in enumerate(filas):
        coma = ',' if i < len(filas) - 1 else ''
        lineas.append("  ('%s', '%s', %d)%s   -- %s" % (STORE, sku, n, coma, color))
    valores = '\n'.join(lineas)

    sql = PLANTILLA % {'total': total, 'cuantos': len(filas),
                       'valores': valores, 'store': STORE}
    destino = os.path.join(BASE, 'supabase_preventa_cupo.sql')
    io.open(destino, 'w', encoding='utf-8', newline='\n').write(sql)
    print('Escrito: supabase_preventa_cupo.sql')
    print('%d SKUs, %d piezas en total' % (len(filas), total))
    for sku, color, n in filas:
        print('  %s  %-16s %d' % (sku, color, n))


PLANTILLA = u'''-- ============================================================
--  PREVENTA — el cupo se respeta en la base, no en el navegador
-- ============================================================
--  GENERADO por preventa_cupo_gen.py desde la const PREVENTA de tablero.html.
--  No editar a mano: cambia el cupo en tablero.html y vuelve a generarlo.
--
--  Medido el 5-ago-2026: la tabla `preventa_cupo` estaba VACÍA. El trigger
--  `apartado_cabe` ya existía, pero con el tope en NULL deja pasar todo —lo dice
--  su propia línea: "sin cupo definido, sin límite"—. O sea que el único freno
--  era el número del navegador, y dos asesores apartando la última pieza a la
--  vez podían guardarla los dos.
--
--  Al correr esto, el tope empieza a aplicarse DE VERDAD: un apartado que se
--  pase se rechaza con "Cupo agotado: X de Y piezas ya apartadas".
--
--  Se pega completo en el SQL Editor del proyecto "HES" (ecuqtqxmdehzbbsmlxrh).
--  Es idempotente.
-- ============================================================


-- ── 1 · Los cupos (%(cuantos)d SKUs, %(total)d piezas) ──────────────────
INSERT INTO public.preventa_cupo (store_id, sku, cupo) VALUES
%(valores)s
ON CONFLICT (store_id, sku) DO UPDATE SET cupo = EXCLUDED.cupo;


-- ── 2 · Que cancelar no cuente contra el cupo ───────────────
-- El trigger sumaba NEW.piezas siempre, incluso al marcar un apartado como
-- Cancelado: la pieza que se está liberando contaba como ocupada. Hoy no
-- estorba porque ningún SKU está al tope, pero con el cupo lleno impediría
-- cancelar — justo cuando hace falta liberar el lugar.
CREATE OR REPLACE FUNCTION public.apartado_cabe()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE tope integer; usado integer;
BEGIN
  IF NEW.estatus = 'Cancelado' THEN RETURN NEW; END IF;
  SELECT cupo INTO tope FROM public.preventa_cupo
   WHERE store_id = NEW.store_id AND sku = NEW.sku;
  IF tope IS NULL THEN RETURN NEW; END IF;   -- sin cupo definido, sin límite
  SELECT coalesce(sum(piezas),0) INTO usado FROM public.apartados
   WHERE store_id = NEW.store_id AND sku = NEW.sku
     AND estatus <> 'Cancelado' AND id <> coalesce(NEW.id, -1);
  IF usado + NEW.piezas > tope THEN
    RAISE EXCEPTION 'Cupo agotado: %% de %% piezas ya apartadas', usado, tope;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS apartado_cabe_trg ON public.apartados;
CREATE TRIGGER apartado_cabe_trg BEFORE INSERT OR UPDATE ON public.apartados
  FOR EACH ROW EXECUTE FUNCTION public.apartado_cabe();


-- ── 3 · Verificación ────────────────────────────────────────
--  a) Los cupos quedaron y NINGUNO está por debajo de lo ya apartado.
--     La columna `sobrepasado` tiene que salir toda en false: si alguna dice
--     true, ese SKU tiene más apartados que cupo y habría que subirle el cupo
--     o cancelar alguno ANTES de que alguien intente tocarlo.
--
--     SELECT c.sku, c.cupo,
--            coalesce(sum(a.piezas) FILTER (WHERE a.estatus <> 'Cancelado'), 0) AS apartadas,
--            coalesce(sum(a.piezas) FILTER (WHERE a.estatus <> 'Cancelado'), 0) > c.cupo AS sobrepasado
--       FROM public.preventa_cupo c
--       LEFT JOIN public.apartados a ON a.store_id = c.store_id AND a.sku = c.sku
--      WHERE c.store_id = '%(store)s'
--      GROUP BY c.sku, c.cupo
--      ORDER BY c.sku;
--
--  b) El tope frena de verdad. Con Orange Ocean (100307499) lleno, esto DEBE
--     fallar con "Cupo agotado". Va dentro de una transacción que se deshace,
--     así que no deja rastro:
--
--     BEGIN;
--       INSERT INTO public.apartados (store_id, sku, cliente, piezas)
--       VALUES ('%(store)s', '100307499', 'PRUEBA — no dejar', 99);
--     ROLLBACK;
--
--  c) Cancelar sigue siendo posible aunque el SKU esté al tope. (UPDATE no
--     acepta ORDER BY ... LIMIT en Postgres, de ahí la subconsulta.)
--
--     BEGIN;
--       UPDATE public.apartados SET estatus = 'Cancelado'
--        WHERE id = (SELECT id FROM public.apartados
--                     WHERE store_id = '%(store)s' AND sku = '100307499'
--                       AND estatus <> 'Cancelado'
--                     ORDER BY id LIMIT 1);
--     ROLLBACK;
'''


if __name__ == '__main__':
    main()
