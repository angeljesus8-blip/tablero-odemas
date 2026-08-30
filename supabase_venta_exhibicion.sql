-- ============================================================
--  VENDER LA PIEZA DE EXHIBICIÓN DE UN EOL
--  17-ago-2026
-- ============================================================
--
--  ------------------------------------------------------------
--  EL HUECO
--  ------------------------------------------------------------
--  `eol_precio_venta` exige `stock = 0`, así que el 50 % solo aparece cuando ya
--  NO queda nada en bodega. Un producto EOL con dos cajas nuevas más la de
--  aparador se cobra entero — incluida la de aparador, que es la que va al 50 %.
--
--  Y hay una segunda mitad que no se ve. `inventario_vivo` imputa TODA venta a
--  bodega, y solo el excedente a exhibición. Vender la de aparador teniendo
--  cajas nuevas dejaba esto:
--
--      bodega       2 cajas intactas   ->  el tablero decía 1
--      exhibición   vacía, ya se fue   ->  el tablero decía 1
--
--  Se equivoca en los dos sentidos a la vez y no da error. El de bodega se
--  corrige solo con el informe del día siguiente (cadena 5: el error no se
--  acumula). **El de exhibición no**: la exhibición se sube solo de vez en
--  cuando, así que ese "1 en piso" puede quedarse semanas — y es justo el que
--  hace que el tablero ofrezca al 50 % una pieza que ya no existe.
--
--  ------------------------------------------------------------
--  CÓMO SE ARREGLA
--  ------------------------------------------------------------
--  Una venta puede decir de dónde salió la pieza: `ventas.de_exhibicion`.
--  Las de bodega descuentan del On Hand; las de exhibición, del aparador.
--
--  TODO EL HISTÓRICO QUEDA EN `false`, y es correcto: hasta hoy no se podía
--  marcar, así que ninguna venta vieja era declaradamente de exhibición.
--
--  ------------------------------------------------------------
--  LO QUE NO SE PUEDE PERDER AL CAMBIARLO
--  ------------------------------------------------------------
--  El modelo viejo NO era arbitrario: decía que las ventas por encima del On
--  Hand se habían comido la exhibición. Eso sigue siendo cierto para las ventas
--  no marcadas, y si se tirara, el tablero volvería a ofrecer al 50 % piezas de
--  piso ya vendidas — una regresión silenciosa sobre datos reales.
--
--  Por eso `exh_vendida` suma las DOS cosas:
--
--      las marcadas de exhibición   +   el excedente sobre el On Hand
--      (lo nuevo)                       (lo que ya hacía, conservado)
--
--  ------------------------------------------------------------
--  Y LOS CORTES SE SEPARAN
--  ------------------------------------------------------------
--  El corte de On Hand pasa a contar solo ventas de bodega, y el de exhibición
--  solo las de exhibición. Los cortes YA GUARDADOS se tomaron con el total, y
--  siguen siendo correctos para On Hand porque todo el histórico es de bodega.
--
--  ------------------------------------------------------------
--  CÓMO SE APLICA — son DOS archivos, en este orden
--  ------------------------------------------------------------
--    1) ESTE archivo (define `corte_tomar_`, que el otro necesita)
--    2) `supabase_cargas_admin.sql` completo, otra vez: ahí viven
--       `carga_catalogo` y `carga_exhibicion`, ya cambiadas para usarlo
--
--  Al revés falla: el segundo llamaría a una función que aún no existe.
--
--  Los dos son idempotentes. Antes de empezar, guardar la foto del inventario
--  para poder comprobar que nada se movió (punto 2 de COMPROBAR, al final).
-- ============================================================


-- ── 1 · De dónde salió la pieza ─────────────────────────────
ALTER TABLE public.ventas
  ADD COLUMN IF NOT EXISTS de_exhibicion boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.ventas.de_exhibicion IS
  'true = se vendio la pieza del aparador (EOL al 50%). Descuenta de exhibicion '
  'y NO del On Hand. Todo lo anterior al 17-ago-2026 es false: no se podia marcar.';


-- ── 2 · El inventario, con las dos procedencias ─────────────
CREATE OR REPLACE FUNCTION public.inventario_vivo(p_store text)
RETURNS TABLE (
  sku text, descripcion text, precio numeric,
  onhand integer, vendido integer, stock integer,
  exhibicion integer, exh_vendida integer
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH bodega AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
      AND NOT v.de_exhibicion
      -- Las entregas de preventa NO cuentan: el POS ya descontó esas piezas el
      -- día que el cliente pagó el apartado. Mismo filtro que en los cortes,
      -- en `comparar_ventas` y en `ventas_hoy` — si se toca, se tocan los cuatro.
      AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
    GROUP BY v.sku
  ),
  aparador AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
      AND v.de_exhibicion
      AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
    GROUP BY v.sku
  ),
  base AS (
    SELECT
      c.sku, c.descripcion, c.precio,
      coalesce(i.onhand, 0)     AS onhand,
      coalesce(i.exhibicion, 0) AS exhibicion,
      greatest(0, coalesce(b.total,0) - coalesce(co.vendidas,0))::int AS vendido,
      greatest(0, coalesce(a.total,0) - coalesce(ce.vendidas,0))::int AS exh_marcada
    FROM public.catalogo c
    LEFT JOIN public.inventario i ON i.store_id = c.store_id AND i.sku = c.sku
    LEFT JOIN bodega   b  ON b.sku  = c.sku
    LEFT JOIN aparador a  ON a.sku  = c.sku
    LEFT JOIN public.inventario_corte co
           ON co.store_id = c.store_id AND co.sku = c.sku AND co.tipo = 'onhand'
    LEFT JOIN public.inventario_corte ce
           ON ce.store_id = c.store_id AND ce.sku = c.sku AND ce.tipo = 'exhibicion'
    WHERE c.store_id = p_store
  )
  SELECT
    sku, descripcion, precio,
    onhand,
    vendido,
    -- stock vendible = solo almacén. La exhibición NO se suma ni se resta.
    greatest(0, onhand - vendido)::int AS stock,
    exhibicion,
    /* Las marcadas de exhibición MÁS el excedente sobre el On Hand. Lo segundo
       es lo que ya hacía el modelo viejo y se conserva a propósito: sin ello,
       las ventas que se comieron una pieza de piso ANTES de que existiera la
       marca volverían a aparecer como piezas disponibles. */
    (exh_marcada + greatest(0, vendido - onhand))::int AS exh_vendida
  FROM base;
$$;


-- ── 3 · Los cortes, cada uno con lo suyo ────────────────────
-- El de On Hand cuenta ventas de BODEGA; el de exhibición, las del APARADOR.
-- Sin esto, el corte de exhibición seguiría guardando el total y `exh_vendida`
-- daría siempre cero: el aparador se vería lleno para siempre.
CREATE OR REPLACE FUNCTION public.corte_tomar_(p_store text, p_tipo text, p_sku text)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT count(*)::int FROM public.ventas v
   WHERE v.store_id = p_store AND v.sku = p_sku
     AND v.de_exhibicion = (p_tipo = 'exhibicion')
     AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id);
$$;

REVOKE ALL ON FUNCTION public.corte_tomar_(text,text,text) FROM public, anon, authenticated;

COMMENT ON FUNCTION public.corte_tomar_(text,text,text) IS
  'El conteo que va al corte, segun el tipo. Existe para que carga_catalogo y '
  'carga_exhibicion no tengan cada una su propia idea de que ventas contar.';


-- ── 3-bis · Que las cargas tomen el corte que les toca ──────
--
-- ESTO ES LO QUE HACE QUE LO DEMÁS FUNCIONE, y era fácil de olvidar. Las dos
-- cargas cuentan hoy TODAS las ventas del SKU. Si se quedan así, el corte de
-- exhibición seguiría guardando el total, `exh_marcada` daría siempre cero por
-- el `greatest(0, …)` y **el aparador no bajaría nunca**: la marca nueva no
-- serviría de nada, sin dar un solo error.
--
-- Y el de On Hand al revés: si contara también las ventas de aparador, quedaría
-- alto y la siguiente venta de bodega no descontaría stock.
--
-- LAS DOS CARGAS SE ARREGLAN EN SU PROPIO ARCHIVO, no aquí.
-- `carga_catalogo` y `carga_exhibicion` viven en `supabase_cargas_admin.sql` y
-- ya quedaron cambiadas ahí para usar `corte_tomar_`. Copiarlas a este archivo
-- habría dejado dos versiones de la carga más delicada del sistema, y una se
-- quedaría atrás: es justo el fallo que este archivo viene a evitar en el
-- inventario. POR ESO HAY QUE PEGAR LOS DOS ARCHIVOS — ver "CÓMO SE APLICA".

-- Los cortes de EXHIBICIÓN ya guardados traen el total de ventas, que con el
-- modelo nuevo dejaría `exh_marcada` clavado en cero hasta la siguiente subida
-- de piso. Se recalculan una vez, aquí: hoy todas las ventas son de bodega, así
-- que quedan en cero — que es la verdad, no ha habido ventas de aparador.
UPDATE public.inventario_corte c
   SET vendidas = public.corte_tomar_(c.store_id, 'exhibicion', c.sku)
 WHERE c.tipo = 'exhibicion';


-- ── 4 · El precio de la pieza de piso ───────────────────────
--
-- Cambia la FORMA: ahora dice además si el 50 % se aplica solo o si hace falta
-- que el asesor marque que está vendiendo la de exhibición.
--
--   solo_exhibicion = true   -> no queda bodega: es la única pieza que hay, y
--                               el precio se pone automático (lo de siempre)
--   solo_exhibicion = false  -> hay cajas nuevas Y una de piso. El 50 % SOLO si
--                               el asesor lo marca; si no, precio normal
--
-- Quitar el filtro de stock sin este campo habría puesto al 50 % todos los EOL
-- con bodega, o sea regalando producto nuevo.
DROP FUNCTION IF EXISTS public.eol_precio_venta(text);

CREATE OR REPLACE FUNCTION public.eol_precio_venta(p_store text)
RETURNS TABLE (sku text, precio50 numeric, solo_exhibicion boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT iv.sku,
         round(coalesce(nullif(e.precio, 0), iv.precio) / 2.0, 2) AS precio50,
         (iv.stock = 0)                                           AS solo_exhibicion
  FROM public.inventario_vivo(p_store) iv
  JOIN public.eol e ON e.store_id = p_store AND e.sku = iv.sku AND NOT e.pausado
  -- Que quede pieza de piso de verdad. Sin esto se ofrecería al 50% un aparador
  -- vacío, que es mandar al asesor a buscar una caja que no está.
  WHERE greatest(0, iv.exhibicion - iv.exh_vendida) > 0
    AND coalesce(nullif(e.precio, 0), iv.precio) > 0;
$$;

REVOKE ALL ON FUNCTION public.eol_precio_venta(text) FROM public;
GRANT EXECUTE ON FUNCTION public.eol_precio_venta(text) TO anon, authenticated;


-- ── 5 · Guardar la venta sabiendo de dónde salió ────────────
-- La firma cambia, así que DROP explícito: `CREATE OR REPLACE` dejaría las dos
-- y PostgREST respondería PGRST203 — o sea, dejaría de guardar ventas. Ya pasó
-- con esta misma función.
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text);
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text);

CREATE OR REPLACE FUNCTION public.venta_guardar(
  p_store      text,
  p_serie      text,
  p_sku        text    DEFAULT NULL,
  p_desc       text    DEFAULT NULL,
  p_precio     numeric DEFAULT NULL,
  p_vendedor   text    DEFAULT NULL,
  p_seguro     boolean DEFAULT NULL,
  p_fecha      text    DEFAULT NULL,
  p_hora       text    DEFAULT NULL,
  p_foto_url   text    DEFAULT NULL,
  p_captura_id text    DEFAULT NULL,
  -- Con DEFAULT para que una app que aún no se ha actualizado siga guardando.
  p_de_exhibicion boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cuando timestamptz;
  v_d int; v_m int; v_a int; v_h int := 12; v_min int := 0;
  m text[];
  nuevo bigint;
BEGIN
  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie');
  END IF;

  -- La fecha llega como d/M/yyyy (así la escribía la hoja y así la manda la app).
  m := regexp_match(coalesce(p_fecha,''), '^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$');
  IF m IS NOT NULL THEN
    v_d := m[1]::int; v_m := m[2]::int; v_a := m[3]::int;
    m := regexp_match(coalesce(p_hora,''), '^\s*(\d{1,2}):(\d{2})\s*([ap])');
    IF m IS NOT NULL THEN
      v_h := m[1]::int; v_min := m[2]::int;
      IF lower(m[3]) = 'p' AND v_h < 12 THEN v_h := v_h + 12; END IF;
      IF lower(m[3]) = 'a' AND v_h = 12 THEN v_h := 0; END IF;
    END IF;
    v_cuando := make_timestamp(v_a, v_m, v_d, v_h, v_min, 0) AT TIME ZONE 'America/Mexico_City';
  ELSE
    v_cuando := now();
  END IF;

  INSERT INTO public.ventas
    (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro,
     foto_url, captura_id, de_exhibicion)
  VALUES (p_store, v_cuando, trim(p_serie), nullif(trim(coalesce(p_sku,'')),''),
          nullif(trim(coalesce(p_desc,'')),''), p_precio,
          coalesce(nullif(trim(coalesce(p_vendedor,'')),''), '(sin nombre)'),
          p_seguro, nullif(trim(coalesce(p_foto_url,'')),''),
          nullif(trim(coalesce(p_captura_id,'')),''),
          coalesce(p_de_exhibicion, false))
  ON CONFLICT (store_id, serie, dia_venta) DO NOTHING
  RETURNING id INTO nuevo;

  IF nuevo IS NULL THEN
    -- Reintentar es seguro: la misma serie el mismo día ya está guardada.
    RETURN jsonb_build_object('ok', true, 'duplicada', true);
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean)
  TO anon, authenticated;


-- ============================================================
--  COMPROBAR — el punto 3 es el que de verdad importa
-- ============================================================
--
--  1) La columna existe y todo el histórico es de bodega:
--       select de_exhibicion, count(*) from public.ventas
--        where store_id='1217' group by 1;
--     Esperado: una sola fila, false.
--
--  2) El inventario NO cambió al aplicar esto. Con cero ventas marcadas, la
--     fórmula nueva tiene que dar exactamente lo mismo que la vieja. Antes de
--     pegar el archivo, guardar una foto:
--       create table _inv_antes as select * from public.inventario_vivo('1217');
--     y después comparar:
--       select * from public.inventario_vivo('1217') n
--         join _inv_antes a using (sku)
--        where n.stock <> a.stock or n.exh_vendida <> a.exh_vendida;
--     Esperado: CERO filas. Si sale alguna, no seguir.
--       drop table _inv_antes;   -- al terminar
--
--  3) La prueba de verdad, en piso, con un EOL que tenga bodega Y aparador:
--       · anotar stock y exhibición en el tablero
--       · capturar la venta marcando «es la pieza de exhibición»
--       · el stock de bodega tiene que quedar IGUAL
--       · la exhibición tiene que bajar una
--     Sin la marca, la venta descuenta de bodega, como siempre.
--
--  4) Qué SKU ofrecen hoy pieza de piso, y cuáles automáticamente:
--       select * from public.eol_precio_venta('1217');
--
-- ============================================================
--  Odemás · Grupo Gigante — uso interno HES 1217
-- ============================================================
