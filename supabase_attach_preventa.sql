-- ============================================================
--  El Assurant del día no cuenta las entregas de preventa
--  8-ago-2026
-- ============================================================
--
--  Detectado en piso el mismo día de la primera entrega: sin haber vendido nada,
--  el tablero ya marcaba «1 venta sin seguro» y el attach del día caía a 0 %.
--
--  La causa es la misma que la del inventario: **una entrega de preventa no es
--  una venta de hoy**. El cliente pagó en julio, y con ella se le vendió —o no—
--  su seguro. Ese attach ya contó el día del apartado, en el reporte de julio.
--  Volver a contarlo hoy es medir dos veces la misma operación.
--
--  Y hace daño en las dos direcciones:
--    · una entrega SIN seguro hunde el attach de un día en el que quizá no se
--      ha vendido nada más — con 9 apartados pendientes, nueve golpes gratis
--    · una entrega CON seguro lo infla igual de falsamente
--
--  El attach es el KPI que se reporta a Demetrio con meta del 25 %. Un número
--  que se mueve por entregas de mercancía vieja no sirve para decidir nada.
--
--  Mismo filtro que `inventario_vivo` y `cargar_cortes`: fuera las ventas que
--  son la entrega de un apartado.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================

CREATE OR REPLACE FUNCTION public.ventas_hoy(p_store text)
RETURNS TABLE (vendedor text, con_seguro bigint, sin_seguro bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT v.vendedor,
         count(*) FILTER (WHERE v.con_seguro)         AS con_seguro,
         count(*) FILTER (WHERE NOT v.con_seguro)     AS sin_seguro
  FROM public.ventas v
  WHERE v.store_id = p_store
    AND v.con_seguro IS NOT NULL
    AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date
        = (now() AT TIME ZONE 'America/Mexico_City')::date
    -- Las entregas de preventa NO son ventas de hoy: se cobraron el día del
    -- apartado y su seguro ya contó entonces. Mismo criterio que el inventario.
    AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
  GROUP BY v.vendedor;
$$;

REVOKE ALL ON FUNCTION public.ventas_hoy(text) FROM public;
GRANT EXECUTE ON FUNCTION public.ventas_hoy(text) TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--  Hoy hay una entrega (Mayra hizamar, sin seguro) y ninguna venta normal:
--
--    select * from public.ventas_hoy('1217');
--      -> 0 filas.  Antes devolvía a "Maria" con sin_seguro = 1.
--
--  Que la venta SIGUE existiendo, solo que no cuenta para el attach del día:
--
--    select v.serie, v.vendedor, v.con_seguro, a.cliente
--      from public.ventas v join public.apartados a on a.venta_id = v.id
--     where v.store_id = '1217';
--      -> la venta de la entrega, con su serie y su vendedor.
--
--  Y que una venta normal SÍ cuenta: capturar una en la app y volver a mirar.
-- ============================================================
