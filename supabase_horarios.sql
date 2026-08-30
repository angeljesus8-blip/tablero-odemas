-- ============================================================
--  HORARIOS — traer el planeador a HES Red (4-ago-2026)
-- ============================================================
-- Hasta hoy el planeador vivía en un proyecto de Supabase aparte
-- (lgnyqfstmcqpkbekspte) con su propio login y su propio PIN. El equipo entraba
-- dos veces: su número en el tablero, y otro PIN para ver su horario.
--
-- Esto lo trae al proyecto de HES Red, con las mismas reglas que el resto:
--   · toda tabla lleva store_id
--   · escribe quien administra la tienda -> admin_de(store_id), la misma
--     función que ya cuida `tiendas` y `empleados` (dueño O subgerente con
--     admin = true). Hasta hoy el subgerente NO podía editar horarios.
--   · el asesor no tiene cuenta de Supabase: lee por una función
--     SECURITY DEFINER que valida su número, igual que login_empleado.
--
-- Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
-- Es idempotente: se puede volver a correr sin romper nada.
-- ============================================================


-- ── 1 · La tabla ────────────────────────────────────────────
-- Mismas cuatro claves que ya usaba el planeador, ahora por tienda y no por
-- usuario: así el gerente y el subgerente ven y editan el MISMO horario. Antes
-- colgaba de user_id, o sea que solo existía para quien lo hubiera creado.
CREATE TABLE IF NOT EXISTS public.horarios_config (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  clave      text        NOT NULL,
  contenido  jsonb       NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, clave),
  -- Un typo en el nombre de la clave creaba una fila huérfana que nadie leía y
  -- nadie reportaba. Que falle de frente.
  CONSTRAINT horarios_clave_valida
    CHECK (clave IN ('equipo','historial','excepciones','semanas_guardadas'))
);


-- ── 2 · RLS ─────────────────────────────────────────────────
ALTER TABLE public.horarios_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS horarios_config_admin ON public.horarios_config;
CREATE POLICY horarios_config_admin ON public.horarios_config
  FOR ALL TO authenticated
  USING (public.admin_de(store_id))
  WITH CHECK (public.admin_de(store_id));

-- Nadie anónimo lee esta tabla directo. El asesor pasa por horario_equipo().


-- ── 3 · updated_at ──────────────────────────────────────────
DROP TRIGGER IF EXISTS horarios_config_touch ON public.horarios_config;
CREATE TRIGGER horarios_config_touch
  BEFORE UPDATE ON public.horarios_config
  FOR EACH ROW EXECUTE FUNCTION public.toca_updated_at();


-- ── 4 · Lectura del asesor, con su número de empleado ───────
-- Sustituye a get_horario_publico(p_pin) del proyecto viejo. Ya no hay un PIN
-- compartido que haya que cambiarle a todos cuando alguien se va: se le da de
-- baja en Admin -> Equipo (activo = false) y deja de ver el horario.
--
-- Devuelve las cuatro claves. `semanas_guardadas` va tal cual, así que se acaba
-- el rodeo de publicar una foto dentro de excepciones.__publicadas: eso existía
-- solo porque el RPC viejo no la devolvía y no había permiso para cambiarlo.
CREATE OR REPLACE FUNCTION public.horario_equipo(p_store_id text, p_empno text)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN EXISTS (
      SELECT 1 FROM public.empleados e
      WHERE e.store_id = p_store_id
        AND e.empno    = p_empno
        AND e.activo   = true
    )
    THEN (
      SELECT json_object_agg(
               h.clave,
               -- El PIN viejo del planeador quedó guardado dentro de `equipo`.
               -- No tiene por qué bajar al teléfono de nadie.
               CASE WHEN h.clave = 'equipo' THEN h.contenido - 'pin' ELSE h.contenido END)
      FROM public.horarios_config h
      WHERE h.store_id = p_store_id
    )
    ELSE NULL
  END;
$$;

GRANT EXECUTE ON FUNCTION public.horario_equipo(text, text) TO anon, authenticated;


-- ── 5 · Verificación ────────────────────────────────────────
-- Correr DESPUÉS de restaurar el respaldo desde la app.
--
--   a) La tabla quedó y tiene las cuatro claves de la 1217:
--        SELECT clave, jsonb_typeof(contenido), updated_at
--        FROM horarios_config WHERE store_id = '1217' ORDER BY clave;
--
--   b) Un número activo SÍ recibe horario (los reales, en `_privado/datos_equipo.txt`):
--        SELECT horario_equipo('1217','<empno-activo>') IS NOT NULL;   -- espera true
--
--   c) Un número que no existe NO recibe nada:
--        SELECT horario_equipo('1217','000000');               -- espera NULL
--
--   d) El PIN viejo no viaja en la respuesta:
--        SELECT horario_equipo('1217','<empno-activo>')->'equipo'->'pin';  -- espera NULL
--
--   e) La tabla NO se puede leer sin cuenta. Desde fuera, con la clave
--      publicable que está en el HTML:
--        curl "https://rjdrljtujbwooejrpyqv.supabase.co/rest/v1/horarios_config?select=*" \
--             -H "apikey: <clave publicable>"
--      Espera [] — si devuelve filas, la política no quedó.
