-- ============================================================
--  DISTINGUIR LAS ENTREGAS EN «VENTAS DEL DÍA»
--  17-ago-2026  ·  ampliado con `cobrado_en` y con los COBROS del dia
-- ============================================================
--
--  En la lista de Ventas del día, una entrega de preventa o de traspaso se ve
--  hoy exactamente igual que una venta normal. Y no lo es:
--
--    · el cliente PAGÓ semanas antes — el ticket del POS es de otro día, y a
--      menudo de otro MES (ya está en el MAPA, cadena 6-ter)
--    · NO cuenta para el Assurant del día ni descuenta stock, porque ambas
--      cosas ya pasaron el día del apartado
--    · NO se puede corregir con el ✏️: la venta la creó `apartado_entregar` y
--      el apartado la sigue apuntando
--
--  O sea que quien cuadra la caja contra el POS ve renglones que no va a
--  encontrar, sin ninguna pista de por qué. La distinción no es decorativa: es
--  la explicación de las tres cosas de arriba.
--
--  Se añade `entrega` a `ventas_detalle`: NULL para una venta normal,
--  'preventa' o 'traspaso' para las que salen de un apartado.
--
--  ------------------------------------------------------------
--  Y LOS APARTADOS COBRADOS ESE DÍA, QUE FALTABAN
--  ------------------------------------------------------------
--  Esto no es una comodidad: es un descuadre que ya existía. `ventas_hoy` —el
--  Assurant del día— SÍ cuenta los apartados pagados hoy, porque un apartado es
--  una venta cobrada aunque el equipo no exista todavía. Pero la lista de
--  Ventas del día no los enseñaba.
--
--  O sea que el día que se cobra un apartado, el porcentaje sube y las filas de
--  abajo no lo explican. Es exactamente lo que se arregló el 8-ago-2026 con el
--  attach manual: la suma de las filas tiene que dar el total, y poder
--  comprobarse de un vistazo.
--
--  `clase` dice qué es cada renglón:
--
--    'venta'    capturada en la app, con su equipo y su serie
--    'entrega'  sale de un apartado: se cobró otro día (ver `cobrado_en`)
--    'cobro'    apartado pagado ESE día. Todavía no hay equipo ni serie.
--
--  Los cancelados no salen: esa venta se deshizo. Mismo criterio que
--  `ventas_hoy`, para que las dos cuenten lo mismo.
--
--  ------------------------------------------------------------
--  POR QUÉ HAY QUE DROPEAR
--  ------------------------------------------------------------
--  Cambia el RETURNS TABLE, y Postgres no deja reemplazar el tipo de retorno de
--  una función con `CREATE OR REPLACE`. Sin el DROP, el pegado falla con
--  "cannot change return type of existing function" — que al menos avisa; lo
--  peligroso sería una firma distinta, que crearía una sobrecarga y PostgREST
--  respondería PGRST203.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


DROP FUNCTION IF EXISTS public.ventas_detalle(text, date);

CREATE FUNCTION public.ventas_detalle(p_store text, p_fecha date DEFAULT NULL)
RETURNS TABLE (serie text, sku text, descripcion text, precio numeric,
               vendedor text, con_seguro boolean, vendida_en timestamptz,
               captura_id text, tiene_foto boolean,
               -- NULL = venta normal. 'preventa' / 'traspaso' = sale de un apartado.
               entrega text,
               -- Cuando se COBRO el apartado. NULL en una venta normal, porque
               -- ahi cobro y entrega son el mismo momento y ya lo dice vendida_en.
               cobrado_en timestamptz,
               -- 'venta' | 'entrega' | 'cobro'. Ver la cabecera.
               clase text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH dia AS (
    SELECT coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date) AS d
  )
  -- 1 · Lo que pasó por la app, y las entregas de apartado
  SELECT v.serie, v.sku, v.descripcion, v.precio, v.vendedor, v.con_seguro,
         v.vendida_en, v.captura_id,
         EXISTS (SELECT 1 FROM public.venta_fotos f
                  WHERE f.store_id = v.store_id AND f.captura_id = v.captura_id),
         /* El tipo del apartado que generó esta venta, si lo hay. Es el MISMO
            vínculo que usan `inventario_vivo`, `ventas_hoy`, `cargar_cortes` y
            `comparar_ventas` para excluirlas: `a.venta_id = v.id`. Aquí no se
            excluye nada — se enseña, que es justo lo que faltaba. */
         (SELECT a.tipo      FROM public.apartados a WHERE a.venta_id = v.id LIMIT 1),
         /* La fecha del cobro. Es la que dice en QUE CORTE esta el ticket: el
            cliente pago semanas antes, a veces en otro mes, asi que buscarlo en
            el de hoy es no encontrarlo. Sale del apartado, no de la venta —
            `vendida_en` es el dia de la ENTREGA. */
         (SELECT a.creado_en FROM public.apartados a WHERE a.venta_id = v.id LIMIT 1),
         CASE WHEN EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
              THEN 'entrega' ELSE 'venta' END
  FROM public.ventas v
  CROSS JOIN dia
  WHERE v.store_id = p_store
    AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date = dia.d

  UNION ALL

  /* 2 · Los apartados COBRADOS ese día. No hay fila en `ventas` hasta que se
     entregan, pero el dinero entró hoy y el Assurant ya los cuenta.

     Sin serie ni `captura_id` a propósito: no hay caja que ligar todavía, y sin
     `captura_id` la app no ofrece el ✏️ ni el borrado — que es lo correcto,
     porque un apartado se corrige desde Preventa, no desde aquí. */
  SELECT a.serie,                      -- normalmente NULL; si ya se asignó, se ve
         a.sku,
         coalesce(c.descripcion, a.color),
         a.precio, a.vendedor, a.con_seguro,
         a.creado_en,                  -- para ordenar por la hora del cobro
         NULL::text,                   -- captura_id: no se toca desde Captura
         false,                        -- tiene_foto
         a.tipo,
         a.creado_en,
         'cobro'
  FROM public.apartados a
  LEFT JOIN public.catalogo c ON c.store_id = a.store_id AND c.sku = a.sku
  CROSS JOIN dia
  WHERE a.store_id = p_store
    AND a.estatus <> 'Cancelado'       -- mismo criterio que ventas_hoy
    AND (a.creado_en AT TIME ZONE 'America/Mexico_City')::date = dia.d

  ORDER BY 7;                          -- por hora, todo mezclado como pasó
$$;

REVOKE ALL ON FUNCTION public.ventas_detalle(text,date) FROM public;
GRANT EXECUTE ON FUNCTION public.ventas_detalle(text,date) TO anon, authenticated;

COMMENT ON FUNCTION public.ventas_detalle(text,date) IS
  'Las ventas de un dia para el panel de Captura. `entrega` distingue las que '
  'salen de un apartado (preventa/traspaso): esas se cobraron semanas antes, no '
  'cuentan para el Assurant del dia ni descuentan stock, y no se pueden corregir '
  'con el lapiz. `clase` = venta | entrega | cobro; los cobros son apartados '
  'pagados ese dia, que el Assurant ya cuenta y la lista no ensenaba.';


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) Un día con entregas y cobros — mira la columna `clase`:
--       select clase, serie, vendedor, entrega, cobrado_en
--         from public.ventas_detalle('1217','2026-08-16');
--
--  1-bis) LO QUE IMPORTA: que la lista cuadre con el Assurant del día. Contando
--     solo lo que cuenta para el KPI —o sea, sin las entregas— los totales
--     tienen que coincidir:
--       select count(*) filter (where con_seguro) as con,
--              count(*) filter (where not con_seguro) as sin
--         from public.ventas_detalle('1217')
--        where clase <> 'entrega' and con_seguro is not null;
--       select sum(con_seguro) as con, sum(sin_seguro) as sin
--         from public.ventas_hoy('1217');
--
--  2) Que cuadre con los apartados entregados de ese día:
--       select a.tipo, count(*) from public.apartados a
--         join public.ventas v on v.id = a.venta_id
--        where a.store_id = '1217'
--          and (v.vendida_en at time zone 'America/Mexico_City')::date = '2026-08-16'
--        group by a.tipo;
--
--     Los totales por tipo tienen que coincidir con lo que devuelve la 1.
--
-- ============================================================
--  Odemás · Grupo Gigante — uso interno HES 1217
-- ============================================================
