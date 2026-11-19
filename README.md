# Cranked Mode - Call of Duty Zombies (Saturn)

Alpha y desarrollo del clasico modo Frenetico (Cranked) adaptado para partidas locales en el entorno de Call of Duty (Saturn / Kronos).

---

## Descripcion del Proyecto

El modo Cranked transforma el ritmo tradicional de supervivencia en una carrera contrarreloj continua:

- **Cronometro de supervivencia:** Al eliminar al primer zombie, se activa una cuenta regresiva.
- **Mantenimiento del ritmo:** Cada baja exitosa reinicia o anade segundos al temporizador.
- **Penalizacion letal:** Si el temporizador llega a cero sin registrar bajas, el jugador explota instantaneamente.
- **Mejoras activas:** Mientras el modo este activo, el jugador obtiene aumentos progresivos en velocidad de movimiento, recarga de armamento y cadencia de disparo.

---

## Variantes Disponibles

El catalogo integra dos modalidades diferenciadas dentro del selector de juego:

- **Modo Standard:** Experiencia clasica de Cranked con temporizador base de 30 segundos en ronda 1, escalado dinamico por rondas y bonificacion de tiempo segun el tamano del escuadron cooperativo.
- **Modo Cursed (Maldito):** Modalidad de maxima exigencia con base reducida a 20 segundos en ronda 1, reduccion temporal agresiva, activacion de reliquias especiales y desafio implacable para jugadores experimentados.

---

## Estado Actual de Desarrollo

El proyecto cuenta con una arquitectura completamente desacoplada y modular:

- [x] **Fase 1 (UI e integracion inicial):** Registro de categoria en el menu local del lobby y asignacion de identificadores visuales en LUI.
- [x] **Fase 2 (Motor de Gameplay):** Implementacion de la maquina de estados de Cranked, hooks de eliminacion de entidades y temporizador regresivo.
- [x] **Fase 3 (Interfaz y Feedback):** Indicadores visuales en pantalla (HUD) del tiempo restante, alertas audibles y efectos de detonacion.
- [x] **Fase 4 (Ajuste y Dificultad):** Modificadores dinamicos segun la ronda y escalado de dificultad por cantidad de jugadores.
- [x] **Fase 5 (Desacoplamiento y Variante Cursed):** Arranque reactivo guiado por modelo de datos bajo la categoria CRANKED, catalogo dual (Standard y Cursed con playlists dedicadas) y proteccion de partidas guardadas contra corrupcion cruzada.

---

## Requisitos y Entorno

- Cliente de juego compatible con la arquitectura Saturn.
- Entorno de inyeccion Kronos / Lumen con soporte para CLUA y llamadas nativas.
- Herramienta de compilacion y despliegue local de scripts.

---

## Instalacion y Despliegue

### Metodo 1: Instalacion Rapida (Releases Oficiales)
1. Descargar el paquete mas reciente desde la seccion de Releases:
   `cranked-mode-bo7-v0.6.0-alpha.zip`
2. Extraer los archivos del paquete:
   - `zm_local_start_post.lua`
   - `cranked-core.lua`
   - `cranked-hud.lua`
3. Copiar los tres archivos dentro del directorio de scripts de Kronos:
   `<Directorio de Kronos>/Assets/Lua/`
4. Iniciar Call of Duty en modo local.

### Metodo 2: Instalacion desde Repositorio (Desarrollo)
1. Clonar el repositorio en tu espacio de trabajo local:
   `git clone https://github.com/DarkxAether115-byte/Cranked-Mode-BO7.git`
2. Copiar los archivos `.lua` a la carpeta de modding de Kronos:
   - Linux / Wine: Copiar hacia el prefijo correspondiente de juego.
   - Windows: Mover a `kronos/Assets/Lua/`.

---

## Como Jugar

1. Entrar al menu principal de Zombies en Kronos.
2. Navegar hasta la categoria **CRANKED** en el carrusel de modos del lobby.
3. Seleccionar la variante deseada (**Standard** o **Cursed**).
4. Escoger el mapa de combate (Liberty Falls, Terminus o cualquier mapa local compatible).
5. Configurar la sesion e iniciar la partida.
6. Al aparecer en el mapa, el temporizador permanecera congelado en espera de tu primera baja.
7. Al registrar la primera eliminacion, el cronometro despertara y comenzara la cuenta regresiva. Mantente en combate continuo para evitar la detonacion.

---

## Flujo de Trabajo y Colaboracion

Para mantener la estabilidad del entorno y evitar fallos de ejecucion:

- **Estructura modular:** Separacion estricta entre el cargador de arranque (`zm_local_start_post.lua`), el motor de logica (`cranked-core.lua`) y la interfaz visual (`cranked-hud.lua`).
- **Control de cambios:** Todo cambio de codigo debe validarse sintacticamente y probarse localmente antes de crear un nuevo release formal.
- **Aislamiento de estado:** Prohibido interferir con los canales y modelos de datos de partidas clasicas para asegurar la persistencia original.
