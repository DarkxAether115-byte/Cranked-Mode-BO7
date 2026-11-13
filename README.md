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

## Estado Actual de Desarrollo

El proyecto se encuentra en transicion desde la fase conceptual hacia una arquitectura modular estable.

- [x] **Fase 1 (UI e integracion inicial):** Registro de categoria en el menu local del lobby y asignacion de identificadores visuales en LUI.
- [ ] **Fase 2 (Motor de Gameplay):** Implementacion de la maquina de estados de Cranked, hooks de eliminacion de entidades y temporizador regresivo.
- [ ] **Fase 3 (Interfaz y Feedback):** Indicadores visuales en pantalla (HUD) del tiempo restante, alertas audibles y efectos de detonacion.
- [ ] **Fase 4 (Ajuste y Dificultad):** Modificadores dinamicos segun la ronda y escalado de dificultad por cantidad de jugadores.

---

## Requisitos y Entorno

- Cliente de juego compatible con la arquitectura Saturn.
- Entorno de inyeccion Kronos / Lumen con soporte para CLUA y llamadas nativas.
- Herramienta de compilacion y despliegue local de scripts.

---

## Instalacion Local (Pruebas)

1. Clonar el repositorio en tu espacio de trabajo local:
   `git clone https://github.com/DarkxAether115-byte/Cranked-Mode-BO7.git`
2. Situar el script principal en la carpeta de configuracion de partidas locales de Kronos.
3. Iniciar el juego en modo local y verificar la disponibilidad de la tarjeta del modo en el menu de Zombies.

---

## Flujo de Trabajo y Colaboracion

Para evitar fallos de memoria, cierres inesperados del cliente y mantener el repositorio limpio:

- **Estructura modular:** Prohibido inyectar bloques masivos sin desacoplar la logica de juego del cargador base.
- **Control de cambios:** Todo cambio debe probarse localmente antes de enviarse. Prohibido subir archivos desordenados directamente por la interfaz web sin pruebas de ejecucion.
- **Registro de depuracion:** Utilizar sondas controladas con limites estrictos de salida en consola para no saturar el bucle principal.
