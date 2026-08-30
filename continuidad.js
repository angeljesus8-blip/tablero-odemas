/* ============================================================
   Volver donde estabas — 8-ago-2026 (v152)
   ============================================================

   EL PROBLEMA
   -----------
   El asesor busca un producto en el tablero, toca «📲 Compartir», manda el
   precio por WhatsApp y regresa. Aparece en el MENÚ, con la búsqueda vacía, y
   tiene que encontrar el producto otra vez. Cada vez que manda un precio.

   No es un fallo del tablero: Android descarta la PWA cuando lleva un rato en
   segundo plano, y al volver el sistema la relanza desde `start_url`, que es
   `index.html`. La pantalla donde estaba nunca se guardó en ningún lado.

   Lo dispara cualquier cambio de app —WhatsApp, la cámara, la galería, una
   llamada—, y el propio tablero manda a WhatsApp desde cuatro botones. O sea
   que rompe justo el flujo de venta normal.

   LO QUE HACE ESTE ARCHIVO
   ------------------------
   1. En cada app: apunta dónde estás (página + sección + búsqueda) y hasta
      dónde habías bajado.
   2. En el menú: si venías de algo hace poco, te devuelve ahí.

   LAS DOS FORMAS DE NO ESTORBAR
   -----------------------------
   · Si tocas «‹ Menú» a propósito, se borra la marca. Salir por tu cuenta
     cuenta como haber terminado, y que te devuelva sería una trampa.
   · Si llegas con el botón ATRÁS del teléfono, tampoco te devuelve. Sin esto
     el «atrás» quedaría inservible: te regresaría a la misma pantalla de la
     que intentas salir, una y otra vez.

   Se carga con <script src="./continuidad.js"> ANTES del resto: así apunta la
   página aunque el script grande de la app falle.
   ============================================================ */
(function(){
  'use strict';

  var K = 'hes_donde';
  /* Media hora. Más arriba empieza a devolverte a la pantalla de ayer al abrir
     la app por la mañana, que ya no es "seguir", es estorbar. Más abajo no
     cubre una plática larga de WhatsApp con un cliente. */
  var VENTANA_MS = 30 * 60 * 1000;

  function pagina(){ return (location.pathname.split('/').pop() || 'index.html').toLowerCase(); }
  var ESTOY_EN_EL_MENU = pagina() === 'index.html' || pagina() === '';

  /* Se puso a true al tocar «‹ Menú». Sin esta bandera la app quedaba SIN SALIDA
     (v152, encontrado en piso el mismo día):

       1. el clic borra la marca
       2. el navegador empieza a navegar y dispara `pagehide`
       3. `pagehide` guarda otra vez — la marca revive, recién puesta
       4. el menú carga, la ve, y te devuelve a la pantalla de la que salías

     Borrar no basta: hay que dejar de guardar. */
  var yaMeVoy = false;

  function leer(){
    try { return JSON.parse(localStorage.getItem(K) || 'null'); } catch(e){ return null; }
  }
  function olvidar(){
    yaMeVoy = true;
    try { localStorage.removeItem(K); } catch(e){}   // sin almacenamiento no había nada que olvidar
  }
  function guardar(){
    if(ESTOY_EN_EL_MENU || yaMeVoy) return;   // el menú no es un sitio donde uno "estaba"
    try {
      localStorage.setItem(K, JSON.stringify({
        url: pagina() + location.search + location.hash,
        y: Math.round(window.scrollY || 0),
        ts: Date.now()
      }));
    } catch(e){}   // cuota llena: se pierde la marca, no la sesión
  }

  /* ── Traer la versión nueva sin que nadie haga nada ─────────
     9-ago-2026. Un teléfono del equipo llevaba CUATRO versiones atrás y por
     eso no le llegaba ningún arreglo: se publicaba, se comprobaba que el
     servidor lo servía, y en la tienda seguían con lo viejo.

     El motivo: registrar el service worker no es pedirle que se actualice.
     Chrome comprueba si hay uno nuevo por su cuenta, pero en una PWA que se
     queda abierta días eso puede no pasar en toda la semana. Nadie llamaba a
     `update()` ni escuchaba cuando el nuevo tomaba el control.

     Ahora se pregunta al abrir y cada vez que la app vuelve a primer plano.
     Cuando el nuevo toma el control se recarga UNA vez —la marca de dónde
     estabas ya está guardada, así que se vuelve al mismo sitio— y la bandera
     evita que dos recargas se persigan. */
  if(typeof navigator !== 'undefined' && navigator.serviceWorker){
    var pedirActualizacion = function(){
      navigator.serviceWorker.getRegistration()
        .then(function(reg){ if(reg) reg.update(); })
        .catch(function(){});   // sin registro no hay nada que actualizar
    };
    pedirActualizacion();
    document.addEventListener('visibilitychange', function(){
      if(document.visibilityState === 'visible') pedirActualizacion();
    });
    navigator.serviceWorker.addEventListener('controllerchange', function(){
      try {
        if(sessionStorage.getItem('hes_recargando') === '1') return;
        sessionStorage.setItem('hes_recargando', '1');
      } catch(e){ return; }   // sin bandera no se recarga: peor un bucle que una versión vieja
      location.reload();
    });
  }

  // ── En una app: apuntar dónde estoy ─────────────────────────
  if(!ESTOY_EN_EL_MENU){
    /* Se LEE antes de guardar. Al revés —que es como estaba— el `guardar()` de
       arranque escribe el scroll actual, que siempre es 0 porque la página
       acaba de cargar, y pisa la altura que se venía a restaurar. La marca
       quedaba correcta y aun así el asesor volvía arriba del todo. */
    var d = leer();
    var aqui = pagina() + location.search + location.hash;
    var mismaPantalla = !!d && d.url === aqui && Date.now() - d.ts < VENTANA_MS;
    var alturaGuardada = mismaPantalla ? (d.y || 0) : 0;

    guardar();
    /* Se apunta al OCULTARSE, que es el único momento garantizado: cuando
       Android mata la app no hay aviso, y `unload` no llega en móvil. */
    document.addEventListener('visibilitychange', function(){
      if(document.visibilityState === 'hidden') guardar();
    });
    window.addEventListener('pagehide', guardar);
    // Y cada pocos segundos mientras se usa, para que el scroll y la sección
    // no se queden viejos si el proceso muere sin pasar por 'hidden'.
    setInterval(function(){ if(document.visibilityState === 'visible') guardar(); }, 5000);

    /* Salir al menú a propósito borra la marca. En captura porque el enlace se
       pinta dentro del HTML, se escucha en fase de captura sobre el documento:
       corre antes de que el navegador siga el enlace. */
    document.addEventListener('click', function(e){
      var a = e.target && e.target.closest && e.target.closest('a[href*="index.html"]');
      if(a) olvidar();
    }, true);
    window.HES_salirAlMenu = olvidar;   // por si alguna app navega con JS

    // Devolver el scroll. El tablero pinta en varios pasos (caché primero, nube
    // después), así que se intenta un rato en vez de una sola vez.
    if(alturaGuardada > 0){
      var intentos = 0;
      var t = setInterval(function(){
        intentos++;
        if(document.body && document.body.scrollHeight > alturaGuardada + window.innerHeight){
          window.scrollTo(0, alturaGuardada);
          clearInterval(t);
        } else if(intentos > 20){ clearInterval(t); }   // nunca creció tanto: se queda arriba
      }, 100);
    }
    return;
  }

  // ── En el menú: devolver a donde estaba ─────────────────────

  /* EL CANDADO VA PRIMERO, antes que cualquier otra comprobación. El menú puede
     devolverte UNA vez por arranque de la app y ni una más.

     Tiene que sellarse aunque esta vez no se reanude, porque el encierro venía
     justo de ahí: abres la app, el menú no reanuda nada (no hay marca todavía),
     entras a Captura, y al volver con el atrás el menú se encuentra la marca
     que Captura acaba de dejar y te manda de vuelta. Sellando al pasar por el
     menú la primera vez, la segunda visita ya está cubierta llegues como
     llegues — con el botón, con el atrás o escribiendo la dirección.

     `sessionStorage` dura lo que dura la pestaña: se vacía solo cuando Android
     mata la app y la relanza, que es cuando SÍ hay que reanudar. */
  try {
    if(sessionStorage.getItem('hes_ya_reanude')) return;
    sessionStorage.setItem('hes_ya_reanude', '1');
  } catch(e){ return; }   // sin sessionStorage no hay candado, y sin candado no se reanuda

  var d = leer();
  if(!d || !d.url) return;
  if(Date.now() - d.ts > VENTANA_MS){ olvidar(); return; }
  if(/^index\.html/.test(d.url)) return;   // nunca reenviar al propio menú

  /* Sin sesión, al menú. Las apps sin `hes_store` no enseñan datos: muestran un
     «vuelve a entrar» con un enlace. Devolver ahí a alguien cuya sesión se cayó
     sería cambiarle el login por un callejón sin salida. */
  try {
    if(!localStorage.getItem('hes_store')){ olvidar(); return; }
  } catch(e){ return; }   // sin localStorage no se puede saber: mejor el menú

  /* Aquí había una comprobación de `performance.navigation.type === back_forward`
     para que el botón atrás no reabriera lo cerrado. Se quitó el 8-ago-2026:
     el candado de arriba hace ese trabajo mejor, y ésta estropeaba el caso más
     frecuente de todos.

     Al volver desde la lista de apps recientes después de que Android matara la
     PWA, Chrome restaura la pestaña y la reporta como `back_forward` — aunque
     sea un arranque nuevo. La comprobación lo tomaba por un «atrás» y dejaba al
     asesor en el menú, que es justo lo que esto venía a evitar.

     El candado sí sabe distinguirlos: si Android mató la app, `sessionStorage`
     viene vacío y hay que reanudar; si fue un atrás dentro de la misma sesión,
     el sello está puesto desde que se abrió el menú la primera vez.

     Lo encontró una prueba de las 64 combinaciones de salir y volver. Ninguna
     de las pruebas sueltas anteriores lo vio. */

  /* `href` y NO `replace`. Con replace el menú desaparecía del historial y el
     botón atrás del teléfono sacaba de la app entera en vez de llevar al menú
     — la segunda mitad del encierro de v152.
     Empujando la entrada, el historial queda [menú, pantalla] y el atrás hace
     lo que cualquiera espera. Volver al menú ya no reanuda, por el candado. */
  location.href = d.url;
})();
