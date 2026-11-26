% ==============================================================================
% PROYECTO DE CURSO - PROGRAMACION POR RESTRICCIONES
% Parte 1: Planificacion de los ensayos en una telenovela (Minimizacion de Costo)
% Escuela de Ingenieria de Sistemas y Computacion - Universidad del Valle
% ==============================================================================

include "globals.mzn";

% ------------------------------------------------------------------------------
% 1. PARAMETROS DE ENTRADA NORMALIZADOS (*.dzn) Y SELECTORES DE EXPERIMENTACION
% ------------------------------------------------------------------------------
enum ACTORES;
array[int] of int: Duracion;

int: M = length(Duracion);
set of int: ESCENAS = 1..M;
set of int: POSICIONES = 1..M;

array[ACTORES, 1..M+1] of int: Escenas;

% Flags opcionales para estudios de ablacion, estrategias y formato de salida
bool: usar_simetrias = true;
bool: usar_redundantes = true;
int: estrategia = 1;
bool: salida_normalizada_pura = false;

% ------------------------------------------------------------------------------
% 2. VALIDACION DE CONSISTENCIA DE PARAMETROS (ASERCIONES)
% ------------------------------------------------------------------------------
constraint assert(M >= 1, "El numero de escenas M debe ser al menos 1.");
constraint assert(card(ACTORES) >= 1, "Debe existir al menos un actor en ACTORES.");
constraint assert(
    forall(e in ESCENAS)(Duracion[e] > 0),
    "Todas las duraciones en Duracion deben ser enteros estrictamente positivos."
);
constraint assert(
    forall(a in ACTORES, e in ESCENAS)(Escenas[a, e] in 0..1),
    "La matriz Escenas[a, 1..M] solo admite indicadores binarios 0 o 1."
);
constraint assert(
    forall(a in ACTORES)(Escenas[a, M+1] >= 0),
    "El costo por unidad de tiempo Escenas[a, M+1] debe ser no negativo."
);
constraint assert(
    estrategia in 1..8,
    "El parametro estrategia debe pertenecer al rango 1..8."
);

% ------------------------------------------------------------------------------
% 3. PARAMETROS DERIVADOS Y COTAS EXACTAS DE DOMINIO A PRIORI
% ------------------------------------------------------------------------------
int: D_total = sum(Duracion);
array[1..M] of int: dur_ord = sort(Duracion);

array[ACTORES] of int: costo_actor = [Escenas[a, M+1] | a in ACTORES];
array[ACTORES] of int: num_esc_actor = [sum(e in ESCENAS)(Escenas[a, e]) | a in ACTORES];
array[ACTORES] of int: dur_min_actor = [
    sum(e in ESCENAS where Escenas[a, e] == 1)(Duracion[e]) | a in ACTORES
];
array[ACTORES] of int: dur_max_actor = [
    if num_esc_actor[a] > 0 then D_total else 0 endif | a in ACTORES
];

int: costo_fijo = sum(a in ACTORES)(costo_actor[a] * dur_min_actor[a]);
int: costo_max  = sum(a in ACTORES)(costo_actor[a] * dur_max_actor[a]);
int: max_espera_global = max([0] ++ [dur_max_actor[a] - dur_min_actor[a] | a in ACTORES]);

% Escenas sin participacion de actores (para simetria S3 y ruptura S1)
array[int] of ESCENAS: escenas_vacias = [
    e | e in ESCENAS where forall(a in ACTORES)(Escenas[a, e] == 0)
];
int: q_vacias = length(escenas_vacias);

% Ranking estatico de escenas por peso salarial ascendente de actores participantes
array[ESCENAS] of int: peso_salarial_esc = [
    sum(a in ACTORES where Escenas[a, e] == 1)(costo_actor[a]) * (M + 1) + e
    | e in ESCENAS
];
array[ESCENAS] of ESCENAS: esc_por_peso_asc = arg_sort(peso_salarial_esc);
array[ESCENAS] of 1..M: rango_peso_esc = [
    sum(k in ESCENAS where esc_por_peso_asc[k] == e)(k) | e in ESCENAS
];

% ------------------------------------------------------------------------------
% 4. VARIABLES DE DECISION Y AUXILIARES CON DOMINIOS ACOTADOS
% ------------------------------------------------------------------------------
array[POSICIONES] of var ESCENAS: Orden;
array[ESCENAS] of var POSICIONES: Pos;
array[0..M] of var 0..D_total: Acum;

array[ACTORES] of var 1..M: primera;
array[ACTORES] of var 1..M: ultima;
array[ACTORES] of var 0..D_total: ini;
array[ACTORES] of var 0..D_total: fin;
array[ACTORES] of var 0..D_total: tiempo;
array[ACTORES] of var 0..max_espera_global: espera;

var costo_fijo..costo_max: Costo;

% Acotamiento individual estricto de dominios (consistencia de nodo inicial)
constraint forall(a in ACTORES)(
    if num_esc_actor[a] > 0 then
        primera[a] <= M - num_esc_actor[a] + 1 /\
        ultima[a]  >= num_esc_actor[a] /\
        ini[a]     <= D_total - dur_min_actor[a] /\
        fin[a]     >= dur_min_actor[a] /\
        tiempo[a]  >= dur_min_actor[a] /\
        tiempo[a]  <= dur_max_actor[a] /\
        espera[a]  <= dur_max_actor[a] - dur_min_actor[a]
    else
        primera[a] = 1 /\ ultima[a] = 1 /\
        ini[a] = 0 /\ fin[a] = 0 /\
        tiempo[a] = 0 /\ espera[a] = 0
    endif
);

% ------------------------------------------------------------------------------
% 5. RESTRICCIONES PRIMARIAS DEL MODELO COP (PARTE 1)
% ------------------------------------------------------------------------------
% C1: Biyeccion primal-dual entre secuencia de escenas y posicion por escena
constraint inverse(Orden, Pos);

% C2: Cronologia acumulada continua de rodaje en el estudio
constraint Acum[0] = 0 /\ Acum[M] = D_total;
constraint forall(k in POSICIONES)(
    Acum[k] = Acum[k - 1] + Duracion[Orden[k]]
);

% C3: Intervalo de permanencia en el set por actor (primera a ultima escena)
constraint forall(a in ACTORES where num_esc_actor[a] > 0)(
    primera[a] = min([Pos[e] | e in ESCENAS where Escenas[a, e] == 1]) /\
    ultima[a]  = max([Pos[e] | e in ESCENAS where Escenas[a, e] == 1]) /\
    ini[a]     = Acum[primera[a] - 1] /\
    fin[a]     = Acum[ultima[a]] /\
    tiempo[a]  = fin[a] - ini[a] /\
    espera[a]  = tiempo[a] - dur_min_actor[a]
);

% Funcion objetivo: costo salarial total de permanencia en el estudio
constraint Costo = sum(a in ACTORES)(costo_actor[a] * tiempo[a]);

% ------------------------------------------------------------------------------
% 6. ELIMINACION DE SIMETRIAS (S1, S2, S3)
% ------------------------------------------------------------------------------
% S3: Fijacion canonica en prefijo de escenas sin participacion de actores
constraint if usar_simetrias /\ q_vacias > 0 then
    forall(j in 1..q_vacias)(Orden[j] = escenas_vacias[j])
else true endif;

% S1: Ruptura de simetria global de inversion temporal sobre escenas activas
constraint if usar_simetrias /\ (M - q_vacias >= 2) then
    Orden[q_vacias + 1] < Orden[M]
else true endif;

% S2: Ordenamiento canonico entre escenas gemelas (mismos actores y duracion)
constraint if usar_simetrias then
    forall(e1, e2 in ESCENAS where
        e1 < e2 /\
        Duracion[e1] == Duracion[e2] /\
        forall(a in ACTORES)(Escenas[a, e1] == Escenas[a, e2])
    )(
        Pos[e1] < Pos[e2]
    )
else true endif;

% ------------------------------------------------------------------------------
% 7. RESTRICCIONES REDUNDANTES DE FORTALECIMIENTO DE PROPAGACION (R1 - R4)
% ------------------------------------------------------------------------------
% R1: Descomposicion lineal exacta de espera sobre escenas ajenas intermedias
%     y ecuacion equivalente de costo con termino base constante
constraint if usar_redundantes then
    Costo = costo_fijo + sum(a in ACTORES)(costo_actor[a] * espera[a]) /\
    forall(a in ACTORES where num_esc_actor[a] > 0)(
        espera[a] = sum(e in ESCENAS where Escenas[a, e] == 0)(
            Duracion[e] * bool2int(primera[a] < Pos[e] /\ Pos[e] < ultima[a])
        )
    )
else true endif;

% R2: Cotas exactas de prefijos acumulados con vector ordenado de duraciones
constraint if usar_redundantes then
    forall(k in POSICIONES)(
        Acum[k] >= sum(j in 1..k)(dur_ord[j]) /\
        Acum[k] <= sum(j in M-k+1..M)(dur_ord[j])
    )
else true endif;

% R3 y R4: Cardinalidad minima de amplitud posicional y cota de espera por exceso
constraint if usar_redundantes then
    forall(a in ACTORES where num_esc_actor[a] > 0)(
        ultima[a] - primera[a] >= num_esc_actor[a] - 1 /\
        let {
            int: n_no = M - num_esc_actor[a];
            array[1..n_no] of int: d_no = sort([Duracion[e] | e in ESCENAS where Escenas[a, e] == 0]);
            array[0..n_no] of int: pref_min = array1d(0..n_no, [0] ++ [sum(j in 1..q)(d_no[j]) | q in 1..n_no]);
        } in (
            if n_no > 0 then
                espera[a] >= pref_min[ultima[a] - primera[a] + 1 - num_esc_actor[a]]
            else true endif
        )
    )
else true endif;

% ------------------------------------------------------------------------------
% 8. ESTRATEGIAS DE BUSQUEDA PARAMETRIZADAS (E1 - E8)
% ------------------------------------------------------------------------------
% Vista reindexada por peso salarial ascendente para seleccion de valor ligera
array[POSICIONES] of var 1..M: OrdenRango = [rango_peso_esc[Orden[k]] | k in POSICIONES];

% Intercalado Outside-In (extremos hacia el centro: 1, M, 2, M-1, ...)
array[POSICIONES] of var 1..M: OrdenRangoExt = [
    if k mod 2 == 1 then OrdenRango[(k + 1) div 2] else OrdenRango[M - (k div 2) + 1] endif
    | k in POSICIONES
];
array[POSICIONES] of var ESCENAS: OrdenExt = [
    if k mod 2 == 1 then Orden[(k + 1) div 2] else Orden[M - (k div 2) + 1] endif
    | k in POSICIONES
];

% Posiciones ordenadas por peso salarial descendente de escena
array[1..M] of var POSICIONES: PosCostoDesc = [
    Pos[esc_por_peso_asc[M - k + 1]] | k in 1..M
];

ann: anotacion_busqueda =
    if estrategia == 1 then
        int_search(OrdenRangoExt, input_order, indomain_min, complete)
    elseif estrategia == 2 then
        int_search(OrdenExt, input_order, indomain_min, complete)
    elseif estrategia == 3 then
        int_search(Orden, input_order, indomain_min, complete)
    elseif estrategia == 4 then
        int_search(Orden, first_fail, indomain_min, complete)
    elseif estrategia == 5 then
        int_search(Orden, first_fail, indomain_split, complete)
    elseif estrategia == 6 then
        int_search(PosCostoDesc, input_order, indomain_median, complete)
    elseif estrategia == 7 then
        int_search(OrdenRangoExt, dom_w_deg, indomain_min, complete)
    else
        int_search([], input_order, indomain_min, complete)
    endif;

solve :: anotacion_busqueda minimize Costo;

% ------------------------------------------------------------------------------
% 9. INTERFAZ DE SALIDA NORMALIZADA Y VERIFICACION TABULAR DE LA SOLUCION
% ------------------------------------------------------------------------------
output
    if salida_normalizada_pura then
        [join(" ", [show(fix(Orden[k])) | k in POSICIONES]) ++ " " ++ show(fix(Costo)) ++ "\n"]
    else
        [
            join(" ", [show(fix(Orden[k])) | k in POSICIONES]) ++ " " ++ show(fix(Costo)) ++ "\n",
            "========================================================================\n",
            "PLANIFICACION DE ENSAYOS EN TELENOVELA - PARTE 1\n",
            "========================================================================\n",
            "Orden de las Escenas: ", show(Orden), "\n",
            "Duracion por Posicion: ", show([Duracion[fix(Orden[k])] | k in POSICIONES]), "\n",
            "Costo Total Optimo:   ", show(Costo), " (Costo base sin esperas: ", show(costo_fijo), ")\n",
            "------------------------------------------------------------------------\n",
            "Cronograma por Actor ([X]=Actua, [.]=Espera en estudio, [ ]=Fuera):\n"
        ] ++
        [
            show_int(-8, enum2int(a)) ++ " (" ++ show(a) ++ "): " ++
            concat([
                if fix(num_esc_actor[a]) == 0 then "   "
                elseif Escenas[a, fix(Orden[k])] == 1 then "[X]"
                elseif k >= fix(primera[a]) /\ k <= fix(ultima[a]) then "[.]"
                else "   " endif
                | k in POSICIONES
            ]) ++
            " | T=" ++ show_int(2, fix(tiempo[a])) ++
            " (Esp=" ++ show_int(2, fix(espera[a])) ++ ")" ++
            " | Costo=" ++ show_int(4, costo_actor[a] * fix(tiempo[a])) ++ "\n"
            | a in ACTORES
        ] ++
        ["========================================================================\n"]
    endif;
