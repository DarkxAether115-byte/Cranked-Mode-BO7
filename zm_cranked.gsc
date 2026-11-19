// ============================================================================
//  zm_cranked.gsc (Mod Modo Frenetico / Cranked - Black Ops 7 / Saturn)
//  Arquitectura: Servidor GSC autoritativo para gestion de tiempo,
//  deteccion de bajas, bonificaciones y detonacion explosiva letal.
// ============================================================================

#using scripts\common\utility;
#using scripts\common\callbacks;
#using scripts\common\values;

// ============================================================================
//  1. Punto de entrada autoexec
// ============================================================================

autoexec zm_cranked_init()
{
    // Solo inicializar si estamos dentro del modo Zombies
    if ( !utility::iszm() )
    {
        return;
    }

    if ( isdefined( level.zm_cranked_initialized ) )
    {
        return;
    }
    level.zm_cranked_initialized = 1;

    // Apertura y configuracion de Dvars de control
    zm_cranked_set_dvars();

    // Registro del callback de aparicion del jugador
    level callback::add( #"player_spawned", &zm_cranked_player_spawned );

    logstring( "ZM_CRANKED: Servidor GSC Modo Frenetico inicializado correctamente." );
}

function zm_cranked_set_dvars()
{
    // Dvar maestro de activacion (1 = activo por defecto, 0 = desactivado)
    if ( getdvarstring( @"scr_cranked" ) == "" )
    {
        setdvar( @"scr_cranked", 1 );
    }

    // Inicializar Dvars de estado sincronizadas con LUI
    setdvar( @"cranked_state", 0 );
    setdvar( @"cranked_time", 30.0 );
    setdvar( @"cranked_max", 30.0 );
    setdvar( @"cranked_kills", 0 );
    setdvar( @"cranked_round", 1 );
}

// ============================================================================
//  2. Calculo dinamico de tiempo limite por ronda y escuadron
// ============================================================================

function zm_cranked_get_max_time( round_num, party_count )
{
    base_t = 30.0;

    if ( round_num <= 5 )
    {
        base_t = 30.0;
    }
    else if ( round_num <= 10 )
    {
        base_t = 25.0;
    }
    else if ( round_num <= 15 )
    {
        base_t = 20.0;
    }
    else if ( round_num <= 20 )
    {
        base_t = 15.0;
    }
    else if ( round_num <= 30 )
    {
        base_t = 10.0;
    }
    else
    {
        base_t = 7.5; // Ronda 31+: Ultra Cranked
    }

    // Escalado por tamano de escuadron
    squad_bonus = 0.0;
    if ( party_count == 2 )
    {
        squad_bonus = 3.0;
    }
    else if ( party_count >= 3 )
    {
        squad_bonus = 5.0;
    }

    final_t = base_t + squad_bonus;
    if ( final_t < 5.0 )
    {
        final_t = 5.0;
    }

    return final_t;
}

// ============================================================================
//  3. Callback de Spawn y Ciclo de Vida del Jugador
// ============================================================================

function zm_cranked_player_spawned( params )
{
    if ( !isdefined( self ) || !isplayer( self ) || isbot( self ) )
    {
        return;
    }

    // Verificar si el modo esta habilitado por Dvar
    if ( getdvarint( @"scr_cranked", 1 ) == 0 )
    {
        return;
    }

    self thread zm_cranked_player_thread();
}

function zm_cranked_player_thread()
{
    self notify( "zm_cranked_player_thread_singleton" );
    self endon( "zm_cranked_player_thread_singleton" );
    self endon( #"disconnect" );
    self endon( #"death" );

    // Estado 1: Esperando primera baja
    setdvar( @"cranked_state", 1 );
    setdvar( @"cranked_time", 30.0 );
    setdvar( @"cranked_max", 30.0 );
    setdvar( @"cranked_kills", 0 );

    last_kills = isdefined( self.kills ) ? self.kills : ( isdefined( self.pers["kills"] ) ? self.pers["kills"] : 0 );
    last_score = isdefined( self.score ) ? self.score : 0;
    total_cranked_kills = 0;

    // Fase 1: Bucle de espera del primer kill
    while ( isalive( self ) )
    {
        wait 0.1;

        if ( getdvarint( @"scr_cranked", 1 ) == 0 )
        {
            setdvar( @"cranked_state", 0 );
            return;
        }

        cur_kills = isdefined( self.kills ) ? self.kills : ( isdefined( self.pers["kills"] ) ? self.pers["kills"] : 0 );
        cur_score = isdefined( self.score ) ? self.score : 0;

        if ( cur_kills > last_kills || cur_score >= ( last_score + 50 ) )
        {
            last_kills = cur_kills;
            last_score = cur_score;
            total_cranked_kills++;
            break;
        }
    }

    if ( !isalive( self ) )
    {
        return;
    }

    // Fase 2: Modo Cranked Activado
    setdvar( @"cranked_state", 2 );
    self iprintlnbold( "^5¡MODO FRENETICO ACTIVADO!" );

    round_num = isdefined( level.round_number ) ? level.round_number : 1;
    party_count = isdefined( level.players ) ? level.players.size : 1;
    max_t = zm_cranked_get_max_time( round_num, party_count );
    timer = max_t;

    setdvar( @"cranked_time", timer );
    setdvar( @"cranked_max", max_t );
    setdvar( @"cranked_kills", total_cranked_kills );
    setdvar( @"cranked_round", round_num );

    // Fase 3: Bucle de cuenta regresiva y reseteo por baja (Paso 0.1s / 10Hz)
    while ( isalive( self ) )
    {
        wait 0.1;

        if ( getdvarint( @"scr_cranked", 1 ) == 0 )
        {
            setdvar( @"cranked_state", 0 );
            return;
        }

        round_num = isdefined( level.round_number ) ? level.round_number : 1;
        party_count = isdefined( level.players ) ? level.players.size : 1;
        max_t = zm_cranked_get_max_time( round_num, party_count );

        cur_kills = isdefined( self.kills ) ? self.kills : ( isdefined( self.pers["kills"] ) ? self.pers["kills"] : 0 );
        cur_score = isdefined( self.score ) ? self.score : 0;

        if ( cur_kills > last_kills || cur_score >= ( last_score + 50 ) )
        {
            // Baja confirmada: resetear timer al maximo de la ronda
            last_kills = cur_kills;
            last_score = cur_score;
            total_cranked_kills++;
            timer = max_t;
            setdvar( @"cranked_kills", total_cranked_kills );
        }
        else
        {
            timer = timer - 0.1;
        }

        // Sincronizar Dvars con LUI HUD
        setdvar( @"cranked_time", timer );
        setdvar( @"cranked_max", max_t );
        setdvar( @"cranked_round", round_num );

        // Aviso critico en los ultimos segundos
        if ( timer <= 3.0 && timer > 2.8 )
        {
            self iprintln( "^1¡ALERTA: 3 SEGUNDOS!" );
        }

        // Condicion de detonacion letal por tiempo agotado
        if ( timer <= 0.0 )
        {
            setdvar( @"cranked_state", 3 );
            setdvar( @"cranked_time", 0.0 );
            self iprintlnbold( "^1¡TIEMPO AGOTADO! DETONACION" );

            // Detonacion explosiva: dana y aniquila zombies cercanos
            radiusdamage( self.origin, 400, 800, 300, self );

            // Muerte letal incondicional del jugador
            self dodamage( self.health + 5000, self.origin );
            self suicide();
            return;
        }
    }
}
