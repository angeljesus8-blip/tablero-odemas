-- ============================================================
-- Dar de alta una tienda con un código de invitación — 20-sep-2026
-- ============================================================
-- POR QUÉ
--
-- El alta dependía de que el gerente abriera un enlace en su correo. Al
-- registrar la 1217 se vio que en esta red eso no llega: los correos
-- @radioshack.com.mx pasan por el reescritor del filtro corporativo
-- (`urlwatch.com/urlwatch?b=<base64>`), que envolvió el enlace y murió con
-- ERR_CONNECTION_RESET. No es un caso raro: le va a pasar a TODOS.
--
-- Y el enlace tenía una segunda atadura: obliga a volver en el MISMO navegador
-- donde se llenó el formulario, porque hasta que hay sesión la tienda solo
-- existe en su `localStorage`. Si alguien confirma en el celular y entra desde
-- la computadora de la tienda, se queda sin tienda y sin nada que lo explique.
--
-- El código de invitación quita el correo del camino: lo genera quien lleva la
-- red, se lo pasa al gerente por WhatsApp, y con él se registra y entra. Sin
-- filtros, sin límites de envío, y con la lista de quién puede abrir una tienda
-- decidida a propósito en vez de «cualquiera que encuentre la URL».
--
-- QUÉ ENTRA AQUÍ
--   · `invitaciones`  — los códigos. NADIE los lee desde la app.
--   · `invitacion_nueva()`   — generar uno. Solo desde el SQL Editor.
--   · `invitacion_valida()`  — ¿sirve este código? Se pregunta ANTES de crear
--                              la cuenta, para no dejar cuentas huérfanas.
--   · `alta_tienda()`        — crea la tienda, da de alta al gerente y quema el
--                              código. Todo o nada, en una sola transacción.
--
-- Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 0 · Que no falte ninguna pieza ────────────────────────────
DO $chk$
BEGIN
  IF to_regclass('public.tiendas')   IS NULL THEN RAISE EXCEPTION 'Falta la tabla tiendas. Pega primero supabase_TODO.sql.'; END IF;
  IF to_regclass('public.empleados') IS NULL THEN RAISE EXCEPTION 'Falta la tabla empleados. Pega primero supabase_TODO.sql.'; END IF;
END
$chk$;


-- ── 1 · Los códigos ───────────────────────────────────────────
-- Sin una sola política de RLS a propósito: con RLS encendida y ninguna
-- política, `anon` y `authenticated` no ven NADA de esta tabla. Se entra solo
-- por las funciones de abajo, que son SECURITY DEFINER. Si algún día alguien
-- añade una política de lectura «para depurar», estará publicando la lista de
-- códigos válidos en un repo cuya clave viaja dentro del HTML.
CREATE TABLE IF NOT EXISTS public.invitaciones (
  codigo      text PRIMARY KEY,
  -- Si va puesto, el código SOLO sirve para esa tienda. Es lo que impide que
  -- una invitación para la 1218 acabe abriendo la 1217.
  store_id    text,
  nota        text,
  vence_en    timestamptz NOT NULL DEFAULT now() + interval '30 days',
  usado_en    timestamptz,
  usado_por   uuid,
  usado_store text,
  creado_en   timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.invitaciones ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.invitaciones FROM anon, authenticated;


-- ── 2 · Generar un código ─────────────────────────────────────
-- Alfabeto sin las parejas que se confunden al dictarlas por teléfono o al
-- teclearlas de una foto: nada de O/0 ni I/1/L. Un código que se lee mal es una
-- llamada al gerente, y son 8 caracteres de 32 → 1.1 billones de
-- combinaciones: no se adivina probando.
CREATE OR REPLACE FUNCTION public.invitacion_nueva(
  p_store_id text DEFAULT NULL,
  p_nota     text DEFAULT NULL,
  p_dias     int  DEFAULT 30
)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  alfabeto constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  c text;
  i int;
BEGIN
  LOOP
    c := '';
    FOR i IN 1..8 LOOP
      c := c || substr(alfabeto, 1 + floor(random() * length(alfabeto))::int, 1);
    END LOOP;
    -- Repetido no es un error: es tirar otra vez. Con este alfabeto no pasa
    -- nunca, pero un choque silencioso dejaría dos tiendas con el mismo código.
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.invitaciones WHERE codigo = c);
  END LOOP;

  INSERT INTO public.invitaciones (codigo, store_id, nota, vence_en)
  VALUES (c, nullif(trim(coalesce(p_store_id,'')), ''), p_nota,
          now() + make_interval(days => greatest(p_dias, 1)));
  RETURN c;
END
$fn$;

-- Esto lo corre quien lleva la red, desde el SQL Editor. Que pudiera llamarlo
-- la app sería regalar la llave: cualquiera se generaría su propia invitación.
REVOKE ALL ON FUNCTION public.invitacion_nueva(text,text,int) FROM public, anon, authenticated;


-- ── 3 · ¿Sirve este código? ───────────────────────────────────
-- Se pregunta ANTES del registro. Sin esto, un código mal tecleado deja una
-- cuenta creada y sin tienda —y la siguiente vez el correo «ya está
-- registrado»—, que es exactamente el lío del que se viene.
--
-- Devuelve el MOTIVO, no un sí/no: «ese código ya se usó» y «ese código no
-- existe» mandan a hacer cosas distintas. No devuelve nada más de la fila: para
-- quien pregunta sin sesión, esto es solo una puerta.
CREATE OR REPLACE FUNCTION public.invitacion_valida(p_codigo text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
  SELECT CASE
    WHEN i.codigo IS NULL           THEN jsonb_build_object('ok', false, 'error', 'no_existe')
    WHEN i.usado_en IS NOT NULL     THEN jsonb_build_object('ok', false, 'error', 'usado')
    WHEN i.vence_en < now()         THEN jsonb_build_object('ok', false, 'error', 'vencido')
    ELSE jsonb_build_object('ok', true, 'store_id', i.store_id)
  END
  FROM (SELECT 1) z
  LEFT JOIN public.invitaciones i
    ON i.codigo = upper(trim(coalesce(p_codigo, '')))
$fn$;

GRANT EXECUTE ON FUNCTION public.invitacion_valida(text) TO anon, authenticated;


-- ── 4 · El alta, entera o nada ────────────────────────────────
-- Antes esto eran dos INSERT sueltos desde el navegador, y entre uno y otro
-- cabía todo: la tienda creada sin gerente dentro, el código quemado sin
-- tienda, o la fila rechazada por la política porque todavía no había sesión.
-- Aquí es una sola llamada: o queda todo, o no queda nada.
--
-- Pide sesión —`auth.uid()`— porque `tiendas.user_id` es quien manda en la
-- tienda. Con la confirmación de correo apagada, `signUp` ya la deja abierta.
CREATE OR REPLACE FUNCTION public.alta_tienda(
  p_codigo     text,
  p_store_id   text,
  p_nombre     text,
  p_ciudad     text,
  p_empno      text,
  p_emp_nombre text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_uid   uuid := auth.uid();
  v_cod   text := upper(trim(coalesce(p_codigo, '')));
  v_store text := trim(coalesce(p_store_id, ''));
  v_inv   public.invitaciones%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin_sesion');
  END IF;
  IF v_store = '' OR trim(coalesce(p_nombre,'')) = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'faltan_datos');
  END IF;

  -- FOR UPDATE: dos altas a la vez con el mismo código se ponen en fila, y la
  -- segunda se encuentra la fila ya marcada. Sin esto, las dos pasarían la
  -- comprobación y el código valdría por dos tiendas.
  SELECT * INTO v_inv FROM public.invitaciones WHERE codigo = v_cod FOR UPDATE;

  IF NOT FOUND                       THEN RETURN jsonb_build_object('ok', false, 'error', 'no_existe'); END IF;
  IF v_inv.usado_en IS NOT NULL      THEN RETURN jsonb_build_object('ok', false, 'error', 'usado');     END IF;
  IF v_inv.vence_en < now()          THEN RETURN jsonb_build_object('ok', false, 'error', 'vencido');   END IF;
  IF v_inv.store_id IS NOT NULL AND v_inv.store_id <> v_store THEN
    RETURN jsonb_build_object('ok', false, 'error', 'otra_tienda', 'store_id', v_inv.store_id);
  END IF;

  BEGIN
    -- `vendedores` es jsonb en esta base, no text[]: el array de JS entra por
    -- PostgREST en cualquiera de los dos y la diferencia solo se ve aquí.
    -- `gas_token` NO se pone: lo pone la base sola (supabase_token_alta.sql), y
    -- escrito desde fuera acabaría siendo algo adivinable.
    INSERT INTO public.tiendas (user_id, store_id, nombre, ciudad, vendedores, admin_pin)
    VALUES (v_uid, v_store, trim(p_nombre), trim(coalesce(p_ciudad,'')), '[]'::jsonb, v_store);
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'tienda_existe');
  END;

  -- El gerente, dado de alta en su propia tienda: los vendedores SON los
  -- empleados, así que sin esta fila la tienda nace sin nadie a quien
  -- acreditarle una venta. Si el número ya existía, se respeta lo que hay.
  IF coalesce(trim(p_empno),'') <> '' AND coalesce(trim(p_emp_nombre),'') <> '' THEN
    INSERT INTO public.empleados (store_id, empno, nombre, puesto, admin, activo)
    VALUES (v_store, trim(p_empno), trim(p_emp_nombre), 'Gerente de Tienda', true, true)
    ON CONFLICT DO NOTHING;
  END IF;

  UPDATE public.invitaciones
     SET usado_en = now(), usado_por = v_uid, usado_store = v_store
   WHERE codigo = v_cod;

  RETURN jsonb_build_object('ok', true, 'store_id', v_store);
END
$fn$;

GRANT EXECUTE ON FUNCTION public.alta_tienda(text,text,text,text,text,text) TO authenticated;
-- `anon` no: sin sesión no hay dueño que ponerle a la tienda, y dejar la puerta
-- abierta invitaría a crear tiendas sin cuenta detrás.
REVOKE ALL ON FUNCTION public.alta_tienda(text,text,text,text,text,text) FROM anon;

COMMENT ON FUNCTION public.alta_tienda(text,text,text,text,text,text) IS
  'Da de alta una tienda con un codigo de invitacion: valida el codigo, crea la '
  'tienda con quien llama como duenno, lo da de alta como Gerente de Tienda y '
  'quema el codigo. Todo en una transaccion. Devuelve {ok:true,store_id} o '
  '{ok:false,error:...} con el motivo.';


-- ============================================================
-- CÓMO SE USA
-- ============================================================
--
-- 1) Generar un código para una tienda nueva (esto lo corres TÚ aquí):
--      select public.invitacion_nueva('1218', 'Tienda de Cholula');
--      -- devuelve algo como  K7M2QPXR   ← eso se le manda al gerente
--
--    Sin atarlo a una tienda concreta (sirve para el ID que él escriba):
--      select public.invitacion_nueva();
--
-- 2) Ver cuáles siguen sin usarse:
--      select codigo, store_id, nota, vence_en
--        from public.invitaciones
--       where usado_en is null and vence_en > now()
--       order by creado_en desc;
--
-- 3) Quién usó cuál:
--      select codigo, store_id, usado_store, usado_en from public.invitaciones
--       where usado_en is not null order by usado_en desc;
--
-- 4) Cancelar uno que se mandó por error (sin borrarlo, para que quede el
--    rastro de que existió):
--      update public.invitaciones set vence_en = now() where codigo = 'K7M2QPXR';
--
-- ============================================================
-- COMPROBAR
-- ============================================================
--
-- a) Un código inventado no sirve:
--      select public.invitacion_valida('NOEXISTE');
--      -- espera {"ok": false, "error": "no_existe"}
--
-- b) Uno recién creado sí:
--      select public.invitacion_valida(public.invitacion_nueva('9998','prueba'));
--      -- espera {"ok": true, ...}
--
-- c) Sin sesión no se puede dar de alta nada — esto es lo que sostiene todo:
--      select public.alta_tienda('LOQUESEA','9998','Prueba','Puebla','1','Ana Ramirez Solis');
--      -- espera {"ok": false, "error": "sin_sesion"}   (en el SQL Editor no hay auth.uid())
--
-- d) Y la tabla no se lee desde la app:
--      set role anon;
--      select count(*) from public.invitaciones;   -- tiene que FALLAR
--      reset role;
