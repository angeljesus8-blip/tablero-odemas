-- ============================================================
--  APARTADOS: vender con promesa de entrega
--  8-ago-2026
-- ============================================================
--
--  Depende de supabase_preventa_series.sql (guardia y funciones de apartado) y
--  de supabase_attach_apartados.sql (el attach del día del cobro).
--
--  ------------------------------------------------------------
--  POR QUÉ NO ES UNA TABLA NUEVA
--  ------------------------------------------------------------
--  Pedirle un equipo a otra tienda para un cliente es, paso por paso, lo mismo
--  que una preventa: el cliente PAGA COMPLETO, no hay equipo, llega días
--  después y se entrega con su serie. Los estados son los mismos
--  (Apartado → Asignado → Entregado), la entrega genera la misma venta y
--  tampoco descuenta stock, porque el POS ya cobró.
--
--  Construir una tabla aparte sería duplicar los cinco sitios que ya saben
--  tratar un apartado —inventario, cortes, comparación, attach y las etiquetas—
--  y garantizar que uno se quede atrás. Se distingue con un campo.
--
--  ------------------------------------------------------------
--  Y LA PREVENTA DE LA PURA 90S SE ACABÓ
--  ------------------------------------------------------------
--  Los equipos llegaron: 24 piezas en piso. Se vende desde Precios como
--  cualquier producto. Lo que queda son 9 entregas pendientes, que ahora viven
--  en la misma lista que los traspasos porque para quien entrega son lo mismo.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · Qué clase de apartado es, y sus datos propios ───────
-- `tipo` por defecto 'preventa': los 10 que ya existen lo son, y así no hay que
-- rellenarlos a mano.
ALTER TABLE public.apartados
  ADD COLUMN IF NOT EXISTS tipo    text NOT NULL DEFAULT 'preventa',
  -- De qué tienda viene el equipo. Solo para traspasos; en una preventa el
  -- equipo llega del CD y no hay a quién llamar.
  ADD COLUMN IF NOT EXISTS origen  text,
  -- Para cuándo se le prometió al cliente. Es el dato que convierte un retraso
  -- en un aviso: sin fecha no hay forma de saber que algo se pasó.
  ADD COLUMN IF NOT EXISTS promesa date;

ALTER TABLE public.apartados DROP CONSTRAINT IF EXISTS apartados_tipo_valido;
ALTER TABLE public.apartados ADD CONSTRAINT apartados_tipo_valido
  CHECK (tipo IN ('preventa','traspaso'));

COMMENT ON COLUMN public.apartados.promesa IS
  'Fecha prometida al cliente. Si pasa y el apartado sigue sin entregar, el '
  'tablero lo sube arriba y avisa: un cliente esperando sin noticias es lo '
  'unico de este flujo que se convierte en queja.';


-- ── 2 · Guardar, ahora también traspasos ────────────────────
-- Los parámetros nuevos van AL FINAL y con DEFAULT: PostgREST resuelve por
-- nombre, así que una app vieja que no los mande sigue guardando preventas.
DROP FUNCTION IF EXISTS public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text);
DROP FUNCTION IF EXISTS public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text,text,text,date);

CREATE FUNCTION public.apartado_guardar(
  p_store       text,
  p_token       text,
  p_sku         text,
  p_color       text    DEFAULT NULL,   -- producto entero, ver MAPA cadena 2-bis
  p_cliente     text    DEFAULT NULL,
  p_telefono    text    DEFAULT NULL,
  p_precio      numeric DEFAULT NULL,
  p_seguro      boolean DEFAULT false,
  p_vendedor    text    DEFAULT NULL,
  p_transaccion text    DEFAULT NULL,   -- ticket del POS: el enlace con la venta
  p_tipo        text    DEFAULT 'preventa',
  p_origen      text    DEFAULT NULL,   -- de qué tienda viene (solo traspaso)
  p_promesa     date    DEFAULT NULL    -- para cuándo se prometió
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE nuevo bigint; v_tipo text;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_cliente),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin cliente');
  END IF;
  IF coalesce(trim(p_sku),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin sku');
  END IF;
  -- Sin vendedor el apartado no cuenta para el attach de nadie ni se sabe quién
  -- lo hizo. El tablero lo toma de la sesión, así que llegar vacío es señal de
  -- que algo va mal, no algo que se deba guardar igual.
  IF coalesce(trim(p_vendedor),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin vendedor');
  END IF;

  v_tipo := CASE WHEN p_tipo = 'traspaso' THEN 'traspaso' ELSE 'preventa' END;

  INSERT INTO public.apartados
    (store_id, sku, color, cliente, telefono, precio, con_seguro,
     vendedor, transaccion, piezas, estatus, tipo, origen, promesa)
  VALUES
    (p_store, trim(p_sku), nullif(trim(coalesce(p_color,'')),''),
     trim(p_cliente), nullif(trim(coalesce(p_telefono,'')),''), p_precio,
     coalesce(p_seguro, false), trim(p_vendedor),
     nullif(trim(coalesce(p_transaccion,'')),''), 1, 'Apartado',
     v_tipo, nullif(trim(coalesce(p_origen,'')),''), p_promesa)
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo, 'tipo', v_tipo);

EXCEPTION
  -- El trigger apartado_cabe lanza esto cuando un SKU de preventa llegó a su
  -- cupo. Los traspasos no tienen cupo, así que ni lo miran.
  WHEN raise_exception THEN
    RETURN jsonb_build_object('ok', false, 'error', left(SQLERRM, 140));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 3 · La lectura devuelve lo nuevo ────────────────────────
DROP FUNCTION IF EXISTS public.apartados_lista(text);

CREATE FUNCTION public.apartados_lista(p_store text)
RETURNS TABLE (id bigint, sku text, cliente text, telefono text,
               piezas integer, con_seguro boolean, estatus text,
               vendedor text, creado_en timestamptz,
               color text, precio numeric, transaccion text,
               serie text, asignado_en timestamptz, entregado_en timestamptz,
               entregado_por text, venta_id bigint,
               tipo text, origen text, promesa date, dias_tarde integer,
               cupo integer, apartadas integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.sku, a.cliente, a.telefono, a.piezas, a.con_seguro,
         a.estatus, a.vendedor, a.creado_en,
         a.color, a.precio, a.transaccion,
         a.serie, a.asignado_en, a.entregado_en, a.entregado_por, a.venta_id,
         a.tipo, a.origen, a.promesa,
         -- Días de retraso, calculados aquí y no en el navegador: el celular
         -- puede tener la fecha mal y esto decide a qué cliente hay que llamar.
         -- Negativo o nulo = todavía no vence.
         CASE WHEN a.promesa IS NOT NULL AND a.estatus NOT IN ('Entregado','Cancelado')
              THEN ((now() AT TIME ZONE 'America/Mexico_City')::date - a.promesa)::int
              ELSE NULL END AS dias_tarde,
         pc.cupo,
         (SELECT coalesce(sum(x.piezas), 0)::int
            FROM public.apartados x
           WHERE x.store_id = a.store_id AND x.sku = a.sku
             AND x.estatus <> 'Cancelado') AS apartadas
  FROM public.apartados a
  LEFT JOIN public.preventa_cupo pc
         ON pc.store_id = a.store_id AND pc.sku = a.sku
  WHERE a.store_id = p_store
  ORDER BY a.creado_en DESC;
$$;


-- ── 4 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.apartados_lista(text) FROM public;
REVOKE ALL ON FUNCTION public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text,text,text,date) FROM public;
GRANT EXECUTE ON FUNCTION public.apartados_lista(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text,text,text,date) TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--  Token:  select gas_token from public.tiendas where store_id='1217';
--
--  1) Los 10 que ya existen quedaron como 'preventa':
--       select tipo, count(*) from public.apartados
--        where store_id='1217' group by tipo;
--     -> preventa 10
--
--  2) La lectura trae lo nuevo SIN perder lo viejo:
--       select cliente, transaccion, serie, tipo, origen, promesa, dias_tarde
--         from public.apartados_lista('1217') limit 3;
--     -> `transaccion` y `serie` NO pueden venir vacías.
--
--  3) Sin vendedor se rechaza (antes se guardaba huérfano):
--       select public.apartado_guardar('1217','<TOKEN>','100270542','X','Cliente',
--              null, 8999, false, '', null, 'traspaso');
--     -> {"ok": false, "error": "sin vendedor"}
--
--  4) Un traspaso de prueba, con todo:
--       select public.apartado_guardar('1217','<TOKEN>','100270542',
--              'MatePad 11.5 8/128GB +Teclado','PRUEBA BORRAR','2220000000',
--              8999, false, 'Prueba', '999999', 'traspaso', 'Parque Puebla',
--              current_date - 1);
--     -> ok:true, tipo traspaso
--       select cliente, tipo, origen, promesa, dias_tarde
--         from public.apartados_lista('1217') where cliente='PRUEBA BORRAR';
--     -> dias_tarde = 1  (se prometió ayer y sigue sin entregar)
--
--  5) Y que cuente para el attach de hoy:
--       select * from public.ventas_hoy('1217');
--     -> aparece "Prueba" con sin_seguro = 1
--
--  6) Borrar la prueba:
--       delete from public.apartados where cliente = 'PRUEBA BORRAR';
-- ============================================================
