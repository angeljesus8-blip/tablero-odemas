-- ============================================================
--  NOTIFICACIONES PUSH — de Apps Script a Supabase
--  Etapa 5 de "apagar la hoja"  ·  7-ago-2026
-- ============================================================
--
--  Depende de supabase_preventa_series.sql (guardia `escritura_ok_`).
--
--  ------------------------------------------------------------
--  POR QUÉ ESTE ERA "EL NUDO", Y POR QUÉ AL FINAL NO LO FUE
--  ------------------------------------------------------------
--  `notificar_` era lo único del Apps Script que no se podía traducir sin más:
--  la REST API key de OneSignal es SECRETA y no puede vivir en el HTML, que es
--  público. Todo lo demás del cliente se protege con el token de tienda, pero
--  ese token también viaja al navegador — sirve para decir "esta tienda puede
--  escribir", no para guardar un secreto de terceros.
--
--  La respuesta obvia era una Edge Function. Pero resulta que la extensión
--  `http` de Postgres YA está habilitada en este proyecto —`cargar_catalogo` la
--  usa con `extensions.http_get`—, así que la llamada a OneSignal se puede hacer
--  desde una función SQL `SECURITY DEFINER`:
--
--    · la llave vive en una tabla con RLS que `anon` no puede leer
--    · la función sí la lee, porque corre como su dueño
--    · el cliente manda el mensaje y su token, nunca la llave
--
--  Sin CLI, sin despliegue y sin una pieza más que mantener. La Edge Function
--  sigue siendo la vía canónica si algún día hace falta algo más (reintentos,
--  segmentar por usuario), pero para mandar un push no aporta nada.
--
--  ------------------------------------------------------------
--  ANTES DE PEGAR: TEN A MANO LAS DOS CLAVES
--  ------------------------------------------------------------
--  Están en el editor del Apps Script → ⚙ Configuración del proyecto →
--  Propiedades del script:  ONESIGNAL_APP_ID  y  ONESIGNAL_KEY
--
--  Se pegan en el PASO 3 de este archivo, directamente en el SQL Editor.
--  NO se escriben en ningún archivo del repo: es público.
-- ============================================================


-- ── 1 · Dónde vive la llave ─────────────────────────────────
-- Tabla aparte de `tiendas` a propósito: `login_asesor` devuelve campos de
-- `tiendas` al navegador, y una llave de OneSignal ahí acabaría saliendo por esa
-- puerta el día que alguien añada un `SELECT *`.
CREATE TABLE IF NOT EXISTS public.notif_config (
  store_id    text        PRIMARY KEY REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  app_id      text        NOT NULL,
  api_key     text        NOT NULL,
  actualizado timestamptz NOT NULL DEFAULT now()
);

-- RLS sin ninguna política = nadie llega por REST, ni anon ni authenticated.
-- Solo la ven las funciones SECURITY DEFINER de abajo.
ALTER TABLE public.notif_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.notif_config FROM anon, authenticated;

COMMENT ON TABLE public.notif_config IS
  'Credenciales de OneSignal. NUNCA exponer por una funcion que devuelva '
  'sus filas: la api_key es un secreto de terceros, no un token de tienda.';


-- ── 2 · Mandar la notificación  ←  reemplaza modo=notificar ─
CREATE OR REPLACE FUNCTION public.notificar(
  p_store  text,
  p_token  text,
  p_msg    text,
  p_titulo text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $fn$
DECLARE
  cfg      public.notif_config%ROWTYPE;
  v_titulo text;
  v_url    text;
  resp     extensions.http_response;
  cuerpo   jsonb;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_msg),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin mensaje');
  END IF;

  SELECT * INTO cfg FROM public.notif_config WHERE store_id = p_store;
  IF NOT FOUND THEN
    -- Mismo texto que daba el Apps Script, para que quien lo vea sepa buscar
    -- en el sitio de siempre.
    RETURN jsonb_build_object('ok', false, 'error', 'OneSignal no configurado');
  END IF;

  -- El título sale de la tienda, no escrito a mano: el Apps Script tenía
  -- 'HES Angelópolis 1217' incrustado, y con una segunda tienda mandaría
  -- notificaciones firmadas por la primera.
  SELECT 'HES ' || t.store_id || ' · ' || coalesce(t.nombre,'')
    INTO v_titulo FROM public.tiendas t WHERE t.store_id = p_store;
  v_titulo := coalesce(nullif(trim(coalesce(p_titulo,'')),''), v_titulo, 'HES');

  -- La URL va fija, igual que en el Apps Script. Se pensó en sacarla de una
  -- columna de `tiendas`, pero esa columna NO EXISTE: se comprobó antes de
  -- escribirla y habría reventado la función en la primera llamada, con el
  -- mismo error que dio `carga_catalogo` hace un rato («column ... does not
  -- exist»). Cuando haya una segunda tienda, se añade la columna y se cambia
  -- esta línea — no antes.
  v_url := 'https://angeljesus8-blip.github.io/tablero-hes1217/tablero.html';

  -- La extensión corta sola; sin esto una caída de OneSignal dejaría la
  -- transacción esperando y con ella al gerente mirando un botón girando.
  PERFORM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '15');

  SELECT * INTO resp FROM extensions.http((
    'POST',
    'https://onesignal.com/api/v1/notifications',
    ARRAY[extensions.http_header('Authorization', 'Basic ' || cfg.api_key)],
    'application/json',
    jsonb_build_object(
      'app_id',            cfg.app_id,
      -- `target_channel` es obligatorio desde el modelo de usuarios nuevo de
      -- OneSignal: una app puede tener push, email y SMS, y sin decirlo responde
      -- 400 «Message Notifications must have At Least One Target Channel».
      -- El Apps Script no lo mandaba —se escribió cuando aún se asumía push— y
      -- por eso sus notificaciones tampoco habrían salido aunque hubiera habido
      -- suscriptores. (7-ago-2026)
      'target_channel',    'push',
      'included_segments', jsonb_build_array('All'),
      -- `en` es OBLIGATORIO: OneSignal lo usa como idioma de respaldo y sin él
      -- responde 400 «Message Notifications must have Any/English language».
      -- Va el mismo texto en español en las dos claves: el equipo lee español y
      -- traducir de verdad no aportaría nada. `es` se queda para que a quien
      -- tenga el teléfono en español le llegue por su idioma, no por el
      -- respaldo. (El Apps Script mandaba solo `es`, así que también habría
      -- fallado con este mismo 400.)
      'headings',          jsonb_build_object('en', v_titulo, 'es', v_titulo),
      'contents',          jsonb_build_object('en', trim(p_msg), 'es', trim(p_msg)),
      'url',               v_url
    )::text
  )::extensions.http_request);

  BEGIN
    cuerpo := resp.content::jsonb;
  EXCEPTION WHEN OTHERS THEN
    cuerpo := jsonb_build_object('respuesta_no_json', left(coalesce(resp.content,''), 200));
  END;

  -- "All included players are not subscribed" NO es un fallo: la llamada llegó,
  -- la llave es buena y OneSignal contestó 200. Lo que dice es que no hay NADIE
  -- suscrito al push todavía.
  --
  -- Se separa a propósito. Tratarlo como error haría que Admin dijera "la
  -- notificación no salió" cada vez que se sube un combo, y el gerente acabaría
  -- ignorando un aviso que un día sí significará algo. Lo que hay que hacer con
  -- esto no es arreglar código: es que el equipo toque la campana del tablero.
  -- (Medido el 7-ago-2026: cero suscriptores. Las notificaciones que mandaba el
  -- Apps Script no le llegaban a nadie, y nadie lo sabía porque
  -- `notificarEquipo` se tragaba el resultado con un console.warn.)
  IF resp.status = 200 AND cuerpo::text ILIKE '%not subscribed%' THEN
    RETURN jsonb_build_object('ok', true, 'destinatarios', 0,
                              'sin_suscriptores', true);
  END IF;

  -- OneSignal responde 200 con un array `errors` cuando rechaza algo, así que
  -- mirar solo el código HTTP daría por buena una notificación que nunca salió.
  IF resp.status <> 200 OR cuerpo ? 'errors' THEN
    RETURN jsonb_build_object('ok', false, 'http', resp.status,
                              'error', left(coalesce(cuerpo->>'errors', cuerpo::text), 200));
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', cuerpo->>'id',
                            'destinatarios', cuerpo->>'recipients');
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.notificar(text,text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.notificar(text,text,text,text) TO anon, authenticated;


-- ── 3 · PEGAR AQUÍ LA LLAVE ─────────────────────────────────
-- El `app_id` ya va puesto: NO es secreto. Está en tablero.html (l. 2246)
-- porque el navegador lo necesita para suscribirse al push, y ese archivo es
-- público. Escribirlo aquí no añade riesgo ninguno.
--
-- La REST API Key SÍ es secreta y es lo único que hay que pegar. Se saca de:
--
--   a) Apps Script → ⚙ Configuración del proyecto → Propiedades del script,
--      la fila `ONESIGNAL_KEY`. Si la interfaz no enseña el valor, ejecuta
--      `verClaveOneSignal` desde el editor (está en GAS_Codigo.gs) y sale en
--      el registro.
--
--   b) O de la fuente original: onesignal.com → tu app → Settings →
--      Keys & IDs → "REST API Key".
--
-- Se pega DIRECTAMENTE en el SQL Editor, nunca en un archivo del repo.
/*
INSERT INTO public.notif_config (store_id, app_id, api_key)
VALUES ('1217', 'db32a1ef-d484-4be3-adfc-2a9e17f7e4f1', 'PEGA_AQUI_LA_REST_API_KEY')
ON CONFLICT (store_id) DO UPDATE
  SET app_id = excluded.app_id, api_key = excluded.api_key, actualizado = now();
*/


-- ============================================================
--  COMPROBAR
-- ============================================================
--  Token de tienda:  select gas_token from public.tiendas where store_id='1217';
--
--  1) Sin token no se manda nada:
--       select public.notificar('1217','','hola');
--     -> {"ok": false, "error": "no_autorizado"}
--
--  2) Nadie puede leer la llave por REST. Desde el SQL Editor (que es dueño) sí
--     se ve; lo que importa es que la app NO. Se comprueba desde fuera:
--       curl -s -X POST '<url>/rest/v1/rpc/...' — no hay función que la devuelva.
--     Y por tabla:
--       select * from public.notif_config;   -- desde el editor: 1 fila
--     Con la anon key, la misma consulta por REST devuelve 0 filas (RLS).
--
--  3) LA PRUEBA DE VERDAD — manda una notificación real a los teléfonos:
--       select public.notificar('1217','<TOKEN>','Prueba desde Supabase, ignorar');
--     -> {"ok": true, "id": "...", "destinatarios": "N"}
--
--     Si `destinatarios` es 0, la llamada funcionó pero no hay nadie suscrito:
--     no es un fallo de esto.
--
--     Si devuelve `no configurado`, falta el PASO 3.
--     Si devuelve un error con `errors`, la llave o el app_id no son correctos:
--     se vuelven a copiar de las Propiedades del script.
-- ============================================================
