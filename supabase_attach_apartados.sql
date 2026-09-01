-- ============================================================
--  Un apartado cuenta para el attach del día en que se paga
--  8-ago-2026
-- ============================================================
--
--  UNA PREVENTA ES UNA VENTA COBRADA. Lo que pasa es que el día del cobro no hay
--  equipo, ni serie, ni caja — así que no se captura en la app. Y como no se
--  captura, el Assurant del tablero nunca la vio: ni ese día ni ninguno.
--
--  Medido sobre los 10 apartados vivos: 10 ventas, 3 con seguro, repartidas en
--  nueve días. Ninguna contó. El 31-jul se vendió un equipo de $22.999 CON
--  seguro y el tablero de ese día lo ignoró; en Sonar sí aparece.
--
--  Así que el attach del tablero venía quedándose corto justo los días de
--  preventa, que son los de venta más grande.
--
--  Esto NO contradice lo de `supabase_attach_preventa.sql`, lo completa:
--    · el día del APARTADO   -> cuenta (es cuando se cobra y se vende el seguro)
--    · el día de la ENTREGA  -> no cuenta (el equipo solo cambia de manos)
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · Los nombres viejos, a su forma oficial ──────────────
-- Hasta hoy el vendedor del apartado se tecleaba a mano y quedaron nombres
-- sueltos —"Maria", "Jorge"—, mientras las ventas guardan el completo desde la
-- sesión. Sumar unos con otros pondría a la misma persona dos veces en el
-- leaderboard, como si fueran dos.
--
-- Desde v149 el tablero lo toma de la sesión y ya no se puede teclear, así que
-- esto es solo para los que ya existen. Se casa por PRIMER NOMBRE contra la
-- tabla de empleados, que es la lista oficial.
UPDATE public.apartados a
   SET vendedor = e.nombre
  FROM public.empleados e
 WHERE a.store_id = e.store_id
   AND a.vendedor IS NOT NULL
   AND a.vendedor <> e.nombre
   -- primer nombre igual, sin acentos ni mayúsculas de por medio
   AND lower(split_part(trim(a.vendedor), ' ', 1)) = lower(split_part(trim(e.nombre), ' ', 1))
   -- y que no haya dos empleados con ese mismo primer nombre: si los hubiera,
   -- adivinar cuál es peor que dejarlo como está
   AND (SELECT count(*) FROM public.empleados e2
         WHERE e2.store_id = a.store_id
           AND lower(split_part(trim(e2.nombre), ' ', 1))
             = lower(split_part(trim(a.vendedor), ' ', 1))) = 1;


-- ── 2 · El attach del día suma las ventas Y los apartados ───
CREATE OR REPLACE FUNCTION public.ventas_hoy(p_store text)
RETURNS TABLE (vendedor text, con_seguro bigint, sin_seguro bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH hoy AS (
    -- Ventas capturadas en la app, menos las entregas de preventa: ésas se
    -- cobraron semanas antes y ya contaron el día de su apartado.
    SELECT v.vendedor, v.con_seguro
    FROM public.ventas v
    WHERE v.store_id = p_store
      AND v.con_seguro IS NOT NULL
      AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date
          = (now() AT TIME ZONE 'America/Mexico_City')::date
      AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)

    UNION ALL

    -- Y los apartados pagados HOY: son ventas cobradas aunque el equipo no
    -- exista todavía, con su seguro o sin él. Los cancelados no cuentan: esa
    -- venta se deshizo.
    SELECT a.vendedor, a.con_seguro
    FROM public.apartados a
    WHERE a.store_id = p_store
      AND a.estatus <> 'Cancelado'
      AND a.vendedor IS NOT NULL
      AND (a.creado_en AT TIME ZONE 'America/Mexico_City')::date
          = (now() AT TIME ZONE 'America/Mexico_City')::date
  )
  SELECT h.vendedor,
         count(*) FILTER (WHERE h.con_seguro)     AS con_seguro,
         count(*) FILTER (WHERE NOT h.con_seguro) AS sin_seguro
  FROM hoy h
  GROUP BY h.vendedor;
$$;

REVOKE ALL ON FUNCTION public.ventas_hoy(text) FROM public;
GRANT EXECUTE ON FUNCTION public.ventas_hoy(text) TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) Los nombres quedaron completos:
--       select distinct vendedor from public.apartados where store_id='1217';
--     -> nombres completos. Si queda alguno corto, es que ese empleado no está
--        en la tabla `empleados` o hay dos con el mismo primer nombre.
--
--  2) Hoy solo hay una entrega y ninguna venta ni apartado nuevo:
--       select * from public.ventas_hoy('1217');
--     -> 0 filas. La entrega sigue sin contar.
--
--  3) La prueba de verdad — apartar algo hoy desde el tablero y volver a mirar:
--     debe aparecer tu nombre con su con_seguro / sin_seguro, y el Assurant del
--     día debe moverse.
--
--  4) Que un apartado cancelado NO cuente:
--       cancelarlo desde el tablero y comprobar que desaparece de ventas_hoy.
-- ============================================================
