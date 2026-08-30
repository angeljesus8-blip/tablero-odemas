-- ============================================================
--  CORREGIR UNA VENTA CAPTURADA
--  17-ago-2026
-- ============================================================
--
--  Lo último que se hacía en la hoja y desde el 17-ago no se hacía en ningún
--  lado: corregir una captura equivocada. La hoja dejó de recibir ventas (fase
--  6) y con ella se fue la única forma de arreglar un seguro mal marcado o un
--  SKU mal tecleado.
--
--  ------------------------------------------------------------
--  LO QUE MUEVE CADA CAMPO — leer antes de tocar esto
--  ------------------------------------------------------------
--    seguro       -> el Assurant del día (el KPI con meta del 25 %)
--    vendedor     -> comisiones y leaderboard
--    precio       -> comisiones
--    descripcion  -> nada, es cosmético
--    serie        -> choca con UNIQUE (store_id, serie, dia_venta) si se repite
--    fecha        -> el día de la venta. NO mueve stock: `inventario_vivo`
--                    cuenta todas las ventas del SKU sin filtrar por fecha
--    sku          -> EL STOCK DE DOS PRODUCTOS. Ver abajo.
--
--  ------------------------------------------------------------
--  POR QUÉ CAMBIAR EL SKU NECESITA TOCAR EL CORTE
--  ------------------------------------------------------------
--  El stock se despeja así:
--
--      stock = onhand − (ventas totales del SKU − ventas contadas en el corte)
--
--  `inventario_corte` es una FOTO de cuántas ventas había por SKU cuando se
--  subió el informe. Si una venta ya estaba en esa foto con el SKU equivocado y
--  se le cambia el SKU sin más:
--
--    · el SKU correcto resta una pieza que el On Hand del informe YA había
--      descontado (el POS sabía la verdad) -> muestra una de menos
--    · el SKU equivocado queda con total < corte. `greatest(0,…)` lo esconde,
--      así que no se ve nada raro — hasta que se venda otra pieza de verdad,
--      que entonces NO se descontará
--
--  Ninguno de los dos da error. Es el mismo error que las entregas de preventa
--  del 7-ago: restar dos veces la misma pieza.
--
--  El arreglo es mover la unidad EN EL CORTE junto con la venta: −1 al corte
--  del SKU viejo y +1 al del nuevo, en la misma transacción. Así `total − corte`
--  queda intacto para los dos, que es lo correcto: corregir una etiqueta no
--  cambia cuántas cajas hay en bodega.
--
--  Se hace para los DOS cortes (onhand y exhibicion): los dos cuentan ventas.
--
--  ⚠️ Límite conocido: se decide con `vendida_en < tomado_en`. Una venta
--  capturada tarde con fecha vieja no estaba en la foto aunque su fecha lo
--  parezca. Es raro y el desvío es de una pieza hasta el informe siguiente,
--  que reemplaza el On Hand completo (ver cadena 5 del MAPA: el error no se
--  acumula entre días).
--
--  ------------------------------------------------------------
--  QUÉ IMPONE ESTO Y QUÉ NO — sin adornos
--  ------------------------------------------------------------
--  `escritura_ok_` valida el TOKEN DE TIENDA, que es el mismo para todos los
--  que entran. O sea que por sí solo no distingue un gerente de un asesor.
--
--  Por eso se pide `p_quien` (el número de empleado) y se comprueba su puesto
--  contra la tabla. Eso SÍ es una barrera de servidor... salvo en un caso: el
--  gerente dueño entra con el correo de la tienda y NO tiene ficha de empleado
--  (ver cadena 1-bis del MAPA), así que `p_quien` vacío tiene que seguir
--  pasando. Quien manipule la llamada a mano puede mandarlo vacío.
--
--  No se disimula: es el mismo nivel de barrera que Resurtir —se le esconde al
--  asesor, no se le impide— y lo que de verdad protege aquí es que TODA edición
--  queda registrada en `ventas_ediciones` con el antes y el después. Una
--  corrección mal hecha se puede ver y deshacer; eso es lo que no había cuando
--  esto se hacía a mano en la hoja.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · El rastro de quién corrigió qué ─────────────────────
-- Editar una venta reescribe historia y mueve dinero (comisiones). Sin esto,
-- una corrección equivocada es indistinguible de la realidad.
CREATE TABLE IF NOT EXISTS public.ventas_ediciones (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  venta_id   bigint,
  captura_id text,
  quien      text,                    -- empno, o vacío si fue por sesión de gerente
  editado_en timestamptz NOT NULL DEFAULT now(),
  antes      jsonb       NOT NULL,
  despues    jsonb       NOT NULL
);

ALTER TABLE public.ventas_ediciones ENABLE ROW LEVEL SECURITY;
-- Sin políticas: no se llega por REST. Solo escribe la función, que es DEFINER.

CREATE INDEX IF NOT EXISTS ventas_ediciones_dia
  ON public.ventas_ediciones (store_id, editado_en DESC);

COMMENT ON TABLE public.ventas_ediciones IS
  'Auditoria de correcciones de ventas. Una fila por edicion, con el antes y el '
  'despues completos. Es lo que permite deshacer una correccion equivocada.';


-- ── 2 · ¿Esta persona lleva la tienda? ──────────────────────
-- Mismo criterio que `PUESTOS_GESTION` en tablero.html: gerente y subgerente.
-- Vive aquí y no repetido en cada función para que no haya dos ideas de "quién
-- manda" que puedan separarse.
CREATE OR REPLACE FUNCTION public.puede_gestionar_(p_store text, p_empno text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.empleados e
     WHERE e.store_id = p_store
       AND e.empno    = p_empno
       AND e.activo   = true
       AND (lower(coalesce(e.puesto,'')) LIKE 'gerente%'
         OR lower(coalesce(e.puesto,'')) LIKE 'subgerente%')
  );
$$;

REVOKE ALL ON FUNCTION public.puede_gestionar_(text,text) FROM public, anon, authenticated;


-- ── 3 · Corregir la venta ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.venta_editar(
  p_store      text,
  p_token      text,
  p_captura_id text,
  p_serie      text,
  p_sku        text,
  p_desc       text,
  p_precio     numeric,
  p_vendedor   text,
  p_seguro     boolean,
  p_fecha      date,
  p_quien      text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v      public.ventas%ROWTYPE;
  antes  jsonb;
  despues jsonb;
  v_hora time;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;

  -- Con número de empleado se comprueba el puesto; sin él es la sesión del
  -- gerente dueño, que no tiene ficha (cadena 1-bis del MAPA).
  IF coalesce(trim(p_quien),'') <> '' AND NOT public.puede_gestionar_(p_store, trim(p_quien)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'solo el gerente o el subgerente pueden corregir una venta');
  END IF;

  IF coalesce(trim(p_captura_id),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin id');
  END IF;
  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'la serie no puede quedar vacía');
  END IF;

  SELECT * INTO v FROM public.ventas
   WHERE store_id = p_store AND captura_id = trim(p_captura_id);

  IF NOT FOUND THEN
    -- Puede pasar de verdad: la captura quedó en la cola del teléfono y todavía
    -- no ha subido. Decirlo, en vez de "no se pudo guardar".
    RETURN jsonb_build_object('ok', false,
      'error', 'esa venta todavía no ha llegado a la nube: espera a que suba y vuelve a intentarlo');
  END IF;

  -- Igual que en `venta_eliminar`: una entrega de preventa no se toca por aquí.
  -- Su venta la creó `apartado_entregar` y el apartado la sigue apuntando.
  IF EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'esa venta es la entrega de un apartado: corrígela desde Preventa');
  END IF;

  antes := jsonb_build_object('serie', v.serie, 'sku', v.sku,
             'descripcion', v.descripcion, 'precio', v.precio,
             'vendedor', v.vendedor, 'con_seguro', v.con_seguro,
             'dia_venta', v.dia_venta, 'de_exhibicion', v.de_exhibicion);

  /* EL CORTE, ANTES DEL UPDATE. Ver la cabecera: si esta venta ya estaba
     contada en la foto del informe con el SKU viejo, hay que mover esa unidad
     también, o el stock de los dos productos queda mal sin avisar. */
  IF trim(coalesce(p_sku,'')) IS DISTINCT FROM coalesce(v.sku,'') THEN
    UPDATE public.inventario_corte
       SET vendidas = greatest(0, vendidas - 1)
     WHERE store_id = p_store AND sku = v.sku
       AND v.vendida_en < tomado_en;

    UPDATE public.inventario_corte
       SET vendidas = vendidas + 1
     WHERE store_id = p_store AND sku = trim(p_sku)
       AND v.vendida_en < tomado_en;
  END IF;

  -- La hora se conserva: solo se mueve el día. Cambiar la hora sin querer
  -- movería la venta de lado respecto a un corte.
  v_hora := (v.vendida_en AT TIME ZONE 'America/Mexico_City')::time;

  BEGIN
    UPDATE public.ventas
       SET serie       = trim(p_serie),
           sku         = trim(coalesce(p_sku, sku)),
           descripcion = nullif(trim(coalesce(p_desc,'')), ''),
           precio      = p_precio,
           vendedor    = coalesce(nullif(trim(coalesce(p_vendedor,'')),''), vendedor),
           con_seguro  = p_seguro,
           vendida_en  = CASE
                           WHEN p_fecha IS NULL OR p_fecha = v.dia_venta THEN vendida_en
                           -- se rearma en hora de México y se guarda como timestamptz
                           ELSE ((p_fecha + v_hora) AT TIME ZONE 'America/Mexico_City')
                         END
     WHERE id = v.id;
  EXCEPTION WHEN unique_violation THEN
    /* Esa serie ya está vendida ese día. NO es un fallo técnico que haya que
       traducir: casi siempre significa que la venta se capturó dos veces, que
       es justo lo que la restricción existe para impedir. */
    RETURN jsonb_build_object('ok', false,
      'error', 'ya hay otra venta con esa serie ese mismo día');
  END;

  SELECT * INTO v FROM public.ventas WHERE id = v.id;
  despues := jsonb_build_object('serie', v.serie, 'sku', v.sku,
               'descripcion', v.descripcion, 'precio', v.precio,
               'vendedor', v.vendedor, 'con_seguro', v.con_seguro,
               'dia_venta', v.dia_venta, 'de_exhibicion', v.de_exhibicion);

  INSERT INTO public.ventas_ediciones
    (store_id, venta_id, captura_id, quien, antes, despues)
  VALUES (p_store, v.id, trim(p_captura_id), nullif(trim(coalesce(p_quien,'')),''),
          antes, despues);

  RETURN jsonb_build_object('ok', true, 'antes', antes, 'despues', despues,
                            'cambio_sku', (antes->>'sku') IS DISTINCT FROM (despues->>'sku'));
END $fn$;

/* NO se puede cambiar `de_exhibicion` desde aqui, y es deliberado.
   Moverla de bodega a aparador (o al reves) cambia de que contador descuenta la
   pieza, asi que habria que mover tambien la unidad en LOS DOS cortes — igual
   que se hace arriba con el SKU. Sin ese ajuste, corregir la procedencia
   descuadraria el stock en silencio, que es justo lo que este archivo evita.

   El valor SI se guarda en la auditoria (antes/despues), asi que si una venta
   se marco mal se ve. Corregirla hoy es borrar la captura y volver a hacerla
   con la casilla correcta: la app deshace las dos cosas bien.

   Si algun dia hace falta, es el mismo patron que el bloque del SKU. */
REVOKE ALL ON FUNCTION public.venta_editar(text,text,text,text,text,text,numeric,text,boolean,date,text)
  FROM public;
GRANT EXECUTE ON FUNCTION public.venta_editar(text,text,text,text,text,text,numeric,text,boolean,date,text)
  TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) Que la tabla de auditoría existe y está vacía:
--       select count(*) from public.ventas_ediciones;
--
--  2) Que el puesto se lee bien (tiene que dar true para el subgerente):
--       select public.puede_gestionar_('1217','<empno-subgerente>');
--
--  3) El caso que importa, con una venta de prueba: capturar una en la app con
--     un SKU equivocado, anotar el stock de los DOS productos en el tablero,
--     corregir el SKU y comprobar que el stock de los dos queda como estaba
--     antes de la captura. Si el corte no se ajustara, uno mostraría una pieza
--     de menos.
--
--  4) Ver las correcciones hechas:
--       select editado_en, quien, captura_id, antes, despues
--         from public.ventas_ediciones
--        where store_id = '1217' order by editado_en desc limit 20;
--
--  5) Deshacer una corrección equivocada: la fila de arriba trae el `antes`
--     completo, así que se vuelve a llamar a venta_editar con esos valores.
--
-- ============================================================
--  Odemás · Grupo Gigante — uso interno HES 1217
-- ============================================================
