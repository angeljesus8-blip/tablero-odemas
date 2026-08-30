-- ============================================================
--  DIAGNÓSTICO DE NOTIFICACIONES  ·  7-ago-2026
-- ============================================================
--
--  Le pregunta a OneSignal dos cosas que desde fuera no se ven:
--    · cuántas suscripciones tiene la app de verdad
--    · qué pasó con una notificación concreta (entregada, fallida, a cuántos)
--
--  Existe porque `ok:true` con `destinatarios:null` no dice nada: la
--  notificación se aceptó, pero no si llegó a alguien. Sin esto solo queda
--  probar a ciegas, y eso ya costó una hora hoy.
--
--  Usa la llave de `notif_config`, así que no hay que copiarla a ningún sitio.
--  Se pega completo en el SQL Editor.
-- ============================================================

CREATE OR REPLACE FUNCTION public.notif_diagnostico(
  p_store text,
  p_token text,
  p_notif text DEFAULT NULL     -- id de una notificación, para ver su entrega
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $fn$
DECLARE
  cfg  public.notif_config%ROWTYPE;
  r    extensions.http_response;
  subs jsonb;
  noti jsonb := NULL;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;

  SELECT * INTO cfg FROM public.notif_config WHERE store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'OneSignal no configurado');
  END IF;

  PERFORM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');

  -- ── cuántas suscripciones hay ──
  SELECT * INTO r FROM extensions.http((
    'GET',
    'https://onesignal.com/api/v1/players?app_id=' || cfg.app_id || '&limit=1',
    ARRAY[extensions.http_header('Authorization', 'Basic ' || cfg.api_key)],
    NULL, NULL
  )::extensions.http_request);

  BEGIN subs := r.content::jsonb;
  EXCEPTION WHEN OTHERS THEN subs := jsonb_build_object('crudo', left(coalesce(r.content,''),200));
  END;

  -- ── qué pasó con esa notificación ──
  IF coalesce(trim(p_notif),'') <> '' THEN
    SELECT * INTO r FROM extensions.http((
      'GET',
      'https://onesignal.com/api/v1/notifications/' || trim(p_notif) || '?app_id=' || cfg.app_id,
      ARRAY[extensions.http_header('Authorization', 'Basic ' || cfg.api_key)],
      NULL, NULL
    )::extensions.http_request);
    BEGIN noti := r.content::jsonb;
    EXCEPTION WHEN OTHERS THEN noti := jsonb_build_object('crudo', left(coalesce(r.content,''),200));
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'suscripciones_totales', subs->'total_count',
    -- Lo que importa de cada suscripción: si está suscrita de verdad y a qué
    -- dispositivo. `invalid_identifier` en true = el navegador revocó el push.
    'primera_suscripcion', CASE
        WHEN jsonb_array_length(coalesce(subs->'players','[]'::jsonb)) > 0
        THEN jsonb_build_object(
               'tipo',    subs->'players'->0->>'device_type',
               'modelo',  subs->'players'->0->>'device_model',
               'activa',  subs->'players'->0->>'notification_types',
               'invalida',subs->'players'->0->>'invalid_identifier',
               'url',     subs->'players'->0->>'url')
        ELSE NULL END,
    'notificacion', CASE WHEN noti IS NULL THEN NULL ELSE jsonb_build_object(
        'exitosas',   noti->'successful',
        'fallidas',   noti->'failed',
        'con_error',  noti->'errored',
        'pendientes', noti->'remaining',
        'error',      noti->'errors') END
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.notif_diagnostico(text,text,text) FROM public, anon, authenticated;
-- NO se concede a anon: esto expone datos de dispositivos y solo se usa desde
-- el SQL Editor, con cuenta de dueño.


-- ============================================================
--  CÓMO USARLO
-- ============================================================
--   select public.notif_diagnostico(
--     '1217',
--     (select gas_token from public.tiendas where store_id='1217'),
--     'e7fe34b2-e039-4a8c-931a-a40b27a16da6');   -- id de la notificación
--
--  Cómo leerlo:
--
--   suscripciones_totales = 0
--     -> el alta nunca se completó. La campana se puso roja pero OneSignal no
--        registró el dispositivo. El problema está en el navegador.
--
--   suscripciones_totales > 0  pero  notificacion.exitosas = 0
--     -> hay dispositivos, pero el envío no llegó a ellos: casi siempre el
--        segmento. Las apps nuevas de OneSignal ya no traen "All"; se llama
--        "Subscribed Users" o "Total Subscriptions".
--
--   exitosas > 0 y aun así no sonó
--     -> salió de OneSignal y llegó al teléfono: es cosa del dispositivo
--        (batería, modo silencio, notificaciones de Chrome apagadas en Android).
--
--   primera_suscripcion.invalida = true
--     -> el navegador revocó el push. Hay que borrar datos del sitio y
--        volver a suscribirse.
-- ============================================================
