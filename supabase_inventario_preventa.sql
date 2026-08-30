-- ============================================================
--  Las entregas de preventa NO descuentan stock
--  7-ago-2026
-- ============================================================
--
--  EL PROBLEMA, CON LOS NÚMEROS QUE LO DESTAPARON
--  ----------------------------------------------
--  Una preventa se COBRA EN EL POS EL DÍA QUE EL CLIENTE APARTA, no el día que
--  se lleva el equipo. Así que para cuando llega el embarque, el POS ya
--  descontó esas piezas, y el "Informe de Artículos Totales" las trae fuera del
--  On Hand.
--
--  Se vio así, el 7-ago-2026, al subir el informe con los apartados ya ligados:
--
--      SKU 100307499 (Orange Ocean)  On Hand 1  ·  apartados 6
--      SKU 100307448 (Graphite Black) On Hand 1  ·  apartados 2
--
--  Seis piezas apartadas de una sola en existencia es imposible: la prueba de
--  que el On Hand ya venía sin ellas.
--
--  Con `apartado_entregar` registrando una venta, `inventario_vivo` volvía a
--  restarlas. No daba negativos —hay greatest(0,…)— y por eso no se vería como
--  un error: daría CERO. El tablero marcaría agotados dos SKUs de los que sí
--  queda una pieza libre, y el asesor le diría "no hay" a un cliente que sí
--  podía comprarlo. Se arreglaba solo al subir el informe siguiente, pero
--  mientras tanto es una venta que se escapa.
--
--  LA CORRECCIÓN
--  -------------
--  `inventario_vivo` deja de contar las ventas que son la entrega de un
--  apartado. Esas piezas ya las descontó el POS; contarlas aquí es descontarlas
--  dos veces.
--
--  Ojo con lo que esto NO cambia: la venta sigue existiendo, con su serie, su
--  vendedor y su fecha. Cuenta para comisiones, para el leaderboard y para el
--  detalle del día. Lo único que no hace es mover el stock.
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
--
--  ------------------------------------------------------------
--  CÓMO COMPROBAR QUE NO ROMPIÓ NADA — hacerlo, no saltárselo
--  ------------------------------------------------------------
--  `inventario_vivo` es la función que se verificó CONTANDO CAJAS EN PISO. Si
--  se traduce mal, el tablero miente sobre el stock y nadie se entera hasta que
--  falta mercancía.
--
--  Hoy la prueba es fácil y concluyente: **no hay ni una venta ligada a un
--  apartado** (los 10 están en 'Asignado', ninguno 'Entregado'). Por lo tanto
--  este cambio NO PUEDE alterar ningún número. Si algo se mueve, está mal.
--
--  Antes de pegar:
--    CREATE TEMP TABLE inv_antes AS SELECT * FROM public.inventario_vivo('1217');
--
--  Después de pegar:
--    SELECT count(*) AS deben_ser_cero FROM (
--      SELECT sku, onhand, vendido, stock, exhibicion, exh_vendida FROM inv_antes
--      EXCEPT
--      SELECT sku, onhand, vendido, stock, exhibicion, exh_vendida
--        FROM public.inventario_vivo('1217')
--    ) d;
--    -- Tiene que dar 0. Si da cualquier otra cosa, NO seguir.
-- ============================================================


CREATE OR REPLACE FUNCTION public.inventario_vivo(p_store text)
RETURNS TABLE (
  sku text, descripcion text, precio numeric,
  onhand integer, vendido integer, stock integer,
  exhibicion integer, exh_vendida integer
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH vendidas AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
      -- Las entregas de preventa NO cuentan: el POS ya descontó esas piezas el
      -- día que el cliente pagó el apartado, semanas antes de llevárselo. El On
      -- Hand del informe ya viene sin ellas. Ver la cabecera de este archivo.
      AND NOT EXISTS (
        SELECT 1 FROM public.apartados a
         WHERE a.venta_id = v.id
      )
    GROUP BY v.sku
  )
  SELECT
    c.sku,
    c.descripcion,
    c.precio,
    coalesce(i.onhand, 0)                                            AS onhand,
    -- vendido DESDE el corte diario, no en total
    greatest(0, coalesce(vd.total,0) - coalesce(co.vendidas,0))::int AS vendido,
    -- stock vendible = solo almacén. La exhibición NO se suma ni se resta.
    greatest(0, coalesce(i.onhand,0)
              - greatest(0, coalesce(vd.total,0) - coalesce(co.vendidas,0)))::int AS stock,
    coalesce(i.exhibicion, 0)                                        AS exhibicion,
    -- vendido desde la última subida de piso, con su propio corte
    greatest(0, coalesce(vd.total,0) - coalesce(ce.vendidas,0))::int AS exh_vendida
  FROM public.catalogo c
  LEFT JOIN public.inventario i  ON i.store_id  = c.store_id AND i.sku  = c.sku
  LEFT JOIN vendidas vd          ON vd.sku      = c.sku
  LEFT JOIN public.inventario_corte co
         ON co.store_id = c.store_id AND co.sku = c.sku AND co.tipo = 'onhand'
  LEFT JOIN public.inventario_corte ce
         ON ce.store_id = c.store_id AND ce.sku = c.sku AND ce.tipo = 'exhibicion'
  WHERE c.store_id = p_store;
$$;


-- ------------------------------------------------------------
-- El corte tiene que contar igual, o el arreglo dura UN DÍA
-- ------------------------------------------------------------
-- Esto no es un extra: sin ello, el arreglo de arriba se convierte en un error
-- distinto en cuanto se suba el siguiente informe.
--
-- `cargar_cortes` no guarda el corte que le manda el GAS: lo DESPEJA, con
--     corte = (total de ventas en Supabase) - (lo que el GAS reporta como v)
--
-- Y ahí hay una asimetría que no se ve a simple vista: las entregas de preventa
-- las escribe `apartado_entregar` **solo en Supabase**. La hoja no se entera, o
-- sea que la `v` del GAS nunca las incluye, pero el `total` de Supabase sí.
-- Resultado: el corte se infla con las entregas de preventa.
--
-- Con la lectura ya filtrada, la cuenta quedaría:
--     vendido = total_sin_preventa - corte_inflado = v - (nº de entregas)
--
-- O sea que cada entrega de preventa RESTARÍA una venta normal del conteo. Con
-- 3 ventas del día y 6 entregas, `vendido` daría 0 en vez de 3, y el tablero
-- mostraría 3 piezas de más. El mismo desajuste de antes, al revés, y bastante
-- peor: enseñar stock que no existe manda a un asesor a buscar una caja que no
-- está, delante del cliente.
--
-- Las dos cuentas tienen que excluir exactamente lo mismo.
CREATE OR REPLACE FUNCTION public.cargar_cortes(p_store text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE d jsonb; a int; b int;
BEGIN
  SELECT r.content::jsonb INTO d
  FROM public.tiendas t,
       LATERAL extensions.http_get(t.gas_url || '?modo=inventario&t=' || t.gas_token) r
  WHERE t.store_id = p_store;
  IF d IS NULL OR d ? 'error' THEN RETURN 'la nube no devolvio inventario'; END IF;

  -- El GAS no guarda el corte: guarda cuantas ventas habia CUANDO se tomo, y
  -- reporta v = (ventas totales de ahora) - corte. Aqui se despeja al reves,
  -- con las ventas ya cargadas:  corte = total - v.
  -- Por eso este paso va DESPUES de cargar_ventas y no antes.
  --
  -- El filtro de las entregas de preventa es EL MISMO que usa inventario_vivo,
  -- y tiene que seguir siendolo: si uno de los dos cambia, el otro tambien.
  WITH totales AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
      AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
    GROUP BY v.sku
  ), reportado AS (
    SELECT j.key AS sku,
           coalesce((j.value->>'v')::int, 0)  AS v,
           coalesce((j.value->>'ev')::int, 0) AS ev
    FROM jsonb_each(d) j
    WHERE trim(j.key) <> ''
  )
  INSERT INTO public.inventario_corte (store_id, tipo, sku, vendidas)
  SELECT p_store, 'onhand', r.sku, greatest(0, coalesce(t.total,0) - r.v)
  FROM reportado r LEFT JOIN totales t ON t.sku = r.sku
  ON CONFLICT (store_id, tipo, sku) DO UPDATE
    SET vendidas = excluded.vendidas, tomado_en = now();
  GET DIAGNOSTICS a = ROW_COUNT;

  WITH totales AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
      AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
    GROUP BY v.sku
  ), reportado AS (
    SELECT j.key AS sku, coalesce((j.value->>'ev')::int, 0) AS ev
    FROM jsonb_each(d) j WHERE trim(j.key) <> ''
  )
  INSERT INTO public.inventario_corte (store_id, tipo, sku, vendidas)
  SELECT p_store, 'exhibicion', r.sku, greatest(0, coalesce(t.total,0) - r.ev)
  FROM reportado r LEFT JOIN totales t ON t.sku = r.sku
  ON CONFLICT (store_id, tipo, sku) DO UPDATE
    SET vendidas = excluded.vendidas, tomado_en = now();
  GET DIAGNOSTICS b = ROW_COUNT;

  RETURN 'corte onhand=' || a || ' · corte exhibicion=' || b;
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERROR ' || SQLSTATE || ': ' || left(regexp_replace(SQLERRM,'https?://[^ ]+','<url>','g'), 170);
END $function$;


-- ============================================================
--  DESPUÉS DE APLICAR
-- ============================================================
--  1) La comprobación de arriba (deben_ser_cero) tiene que dar 0.
--
--  2) Cuando ya haya entregado alguna, el efecto se ve así:
--       SELECT a.cliente, a.sku, a.serie, v.id AS venta
--         FROM public.apartados a JOIN public.ventas v ON v.id = a.venta_id
--        WHERE a.store_id = '1217';
--     Esas ventas existen —cuentan para comisiones— y NO aparecen en el
--     `vendido` de inventario_vivo.
--
--  3) El stock de esos SKU debe seguir siendo el On Hand del informe:
--       SELECT sku, onhand, vendido, stock
--         FROM public.inventario_vivo('1217')
--        WHERE sku IN ('100307448','100307499');
--     -> vendido 0 y stock 1 en los dos, aunque se hayan entregado 8 piezas.
-- ============================================================
