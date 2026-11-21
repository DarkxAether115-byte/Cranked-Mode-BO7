# Cranked Mode - Call of Duty Zombies (Saturn / Kronos)

Desarrollo y consolidacion del modo Frenetico (Cranked) para Call of Duty Zombies en el entorno Saturn / Kronos (BO7).

---

## Descripcion del Proyecto

El modo Cranked transforma el ritmo tradicional de supervivencia en una carrera contrarreloj continua:

- **Cronometro de supervivencia:** Al eliminar al primer zombie, se activa una cuenta regresiva.
- **Mantenimiento del ritmo:** Cada baja exitosa reinicia o anade segundos al temporizador.
- **Penalizacion letal:** Si el temporizador llega a cero sin registrar bajas, el jugador explota instantaneamente causando dano en area.
- **Mejoras activas:** Mientras el modo este activo, el jugador obtiene aumentos progresivos en velocidad de movimiento, recarga de armamento y cadencia de disparo.

---

## Arquitectura Hibrida GSC-Lua

El proyecto implementa una arquitectura desacoplada y autoritativa libre de codigo zombie (archivo redundante `cranked_mode_post.lua` erradicado):

```
                        +---------------------------+
                        |  zm_cranked.gsc (Servidor)|
                        |  Control autoritativo     |
                        |  scr_cranked, cranked_*   |
                        +-------------+-------------+
                                      | Dvars sincronizadas (10Hz)
                                      v
+-----------------------------+-----------------------------+
|  cranked-core.lua (Logica)  |   Acceso Seguro a Dvars:    |
|  - Sincronizacion GSC       |   - Dvar.GetDvarString      |
|  - Standalone Contingency   |<--|   - Dvar.GetDvarInt       |
|  - DataSources LUI fallback |   - Hash 0x254084d7ca2317bb |
+-----------------------------+-----------------------------+
                                      | Estado unificado
                                      v
                        +---------------------------+
                        |  cranked-hud.lua (LUI)    |
                        |  - Respeto a scr_cranked  |
                        |  - Gradientes de amenaza  |
                        |  - Render sin parpadeos   |
                        +---------------------------+
```

### 1. Servidor GSC Autoritativo (`zm_cranked.gsc`)
- Gestiona el ciclo de vida del jugador y la maquina de estados:
  - `0`: Inactivo / Lobby / Pre-spawn
  - `1`: Esperando primera baja
  - `2`: Frenetico Activo (cuenta regresiva y reseteo por baja)
  - `3`: Detonado / Tiempo agotado (explosion letal en area y suicidio)
- Expone y actualiza Dvars autoritativas: `scr_cranked`, `cranked_state`, `cranked_time`, `cranked_max`, `cranked_kills`, `cranked_round`.

### 2. Motor Central Gameplay (`cranked-core.lua`)
- **Sincronizacion autoritativa GSC:** Cuando `scr_cranked == 1` y `cranked_state` es valido (1, 2 o 3), sincroniza tiempo, maximo, bajas y ronda directamente desde el servidor GSC.
- **Acceso seguro a Dvars con fallback multi-estrategia:**
  1. `Dvar.GetDvarString` (con clave resuelta o nombre literal).
  2. `Dvar.GetDvarInt` (lectura numerica directa).
  3. Hash CLUA nativo `0x254084d7ca2317bb` (`DV_GET_HASH`).
  4. Indexacion generica protegida bajo `pcall`.
- **Modo contingencia / Standalone:** Si las Dvars del servidor no existen o `scr_cranked` es nulo, mantiene la ejecucion autonoma cliente mediante DataSources de LUI (`_DataSources.inGame` y `_DataSources.alwaysLoaded`).
- **Validacion estricta de tipos:** Sanitizacion contra valores `nil`, strings invalidos, negativos, division por cero, `NaN` (`0/0`) e `Inf` (`1/0`).

### 3. Interfaz Visual HUD (`cranked-hud.lua`)
- **Respeto a Dvar `scr_cranked`:** Si `scr_cranked == 0`, oculta/destruye inmediatamente el widget HUD de pantalla.
- **Sincronizacion de cronometro y barra sin parpadeos ni desincronizacion:** Clamp seguro del ratio `0.0 <= ratio <= 1.0` y calculo preciso de posicion horizontal.
- **Gradiente de amenaza y feedback auditivo:**
  - *Seguro (> 10s):* Cian electrico / Blanco.
  - *Advertencia (5s - 10s):* Ambar / Naranja.
  - *Critico (< 5s):* Rojo parpadeante con pulso sonoro a 1Hz (`uin_alert_lockon`).
  - *Ultra Cranked (Ronda 31+):* Titulo dinamico "ULTRA CRANKED" con parpadeo acelerado.

### 4. Cargador e Inyector (`zm_local_start_post.lua`)
- Registra la categoria `CRANKED` y `CRANKED CURSED` en el carrusel de juego local y enlaza los modulos mediante `require("cranked-core")` y `require("cranked-hud")`.

---

## Variantes Disponibles

- **Modo Standard:** Temporizador base de 30 segundos en ronda 1, escalado dinamico por rondas y bonificacion de tiempo segun el tamano del escuadron cooperativo (+3s para 2 jugadores, +5s para 3+).
- **Modo Cursed (Maldito):** Modalidad de maxima exigencia con base reducida a 20 segundos en ronda 1, reduccion temporal agresiva (-5s por tier, minimo 10s) y desafio implacable.

---

## Suite de Pruebas Rigurosa y Destructiva

El proyecto incorpora una suite de pruebas exhaustiva en `tests/test_cranked.lua` sin mocks ni stubs complacientes:

- **Suite 1:** Estrategias de fallback de Dvars (`GetDvarString`, `GetDvarInt`, hash CLUA `0x254084d7ca2317bb`) y resiliencia ante excepciones nativas simuladas (`error()` dentro de los getters atrapado por `pcall`).
- **Suite 2:** Pruebas destructivas con payloads corruptos: strings no numericos, `NaN`, `Inf`, tiempos negativos y `max_time <= 0`.
- **Suite 3:** Sincronizacion de maquina de estados autoritativa GSC (estados 0, 1, 2, 3, ultra cranked en ronda 31+ y reseteo por `scr_cranked == 0`).
- **Suite 4:** Modo de contingencia standalone guiado por DataSources de LUI, detonacion letal local y recuperacion tras respawn o timeout.
- **Suite 5:** Motor HUD LUI: visibilidad, gradientes de amenaza, alertas sonoras y prevencion de division por cero.

### Ejecucion de Pruebas

Para validar la sintaxis de todos los scripts:
```bash
luac -p *.lua tests/*.lua
```

Para ejecutar la suite completa de pruebas unitarias y destructivas:
```bash
lua tests/test_cranked.lua
```

Resultado verificado:
```
ALL TESTS PASSED: 28 tests, 108 assertions verified.
Exit code: 0
```

---

## Instalacion y Despliegue

1. Copiar los archivos limpios al directorio de scripts de Kronos:
   - `zm_local_start_post.lua`
   - `cranked-core.lua`
   - `cranked-hud.lua`
   hacia `<Directorio de Kronos>/Assets/Lua/`.
2. Colocar `zm_cranked.gsc` en la carpeta de scripts GSC del servidor local.
3. Iniciar Call of Duty en modo local y seleccionar **CRANKED** en el carrusel de modos.
