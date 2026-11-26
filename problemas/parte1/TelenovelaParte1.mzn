% ==============================================================================
% PROYECTO DE CURSO - PROGRAMACION POR RESTRICCIONES
% Parte 1: Planificacion de los ensayos en una telenovela (Minimizacion de Costo)
% Escuela de Ingenieria de Sistemas y Computacion - Universidad del Valle
%
% Integrantes:
%   - Cristian David Cabrera Pantoja
%   - Junior Orlando Cantor Arevalo
%   - Juan Diego Cardenas Mejia
% Profesor:
%   - Robinson Duque
% ==============================================================================

include "globals.mzn";

% ------------------------------------------------------------------------------
% 1. PARAMETROS DE ENTRADA NORMALIZADOS (*.dzn)
% ------------------------------------------------------------------------------
enum ACTORES;
array[int] of int: Duracion;

int: M = length(Duracion);
set of int: ESCENAS = 1..M;
set of int: POSICIONES = 1..M;

array[ACTORES, 1..M+1] of int: Escenas;

% ------------------------------------------------------------------------------
% 2. VALIDACION DE CONSISTENCIA DE PARAMETROS (ASERCIONES)
% ------------------------------------------------------------------------------
constraint assert(M >= 1,
    "Error de entrada: el numero de escenas M debe ser al menos 1.");
constraint assert(card(ACTORES) >= 1,
    "Error de entrada: debe existir al menos un actor en ACTORES.");
constraint assert(
    forall(e in ESCENAS)(Duracion[e] > 0),
    "Error de entrada: todas las duraciones en Duracion deben ser positivas."
);
constraint assert(
    forall(a in ACTORES, e in ESCENAS)(Escenas[a, e] >= 0 /\ Escenas[a, e] <= 1),
    "Error de entrada: Escenas[a, 1..M] solo admite valores binarios 0 o 1."
);
constraint assert(
    forall(a in ACTORES)(Escenas[a, M+1] >= 0),
    "Error de entrada: el costo salarial Escenas[a, M+1] no puede ser negativo."
);

% ------------------------------------------------------------------------------
% 3. PARAMETROS DERIVADOS Y COTAS EXACTAS DE DOMINIO A PRIORI
% ------------------------------------------------------------------------------
int: D_total = sum(e in ESCENAS)(Duracion[e]);

% Ordenamiento ascendente de Duracion mediante conteo de rango estricto
array[ESCENAS] of 1..M: rango_dur = [
    1 + sum(e2 in ESCENAS where
        Duracion[e2] < Duracion[e] \/ (Duracion[e2] == Duracion[e] /\ e2 < e)
    )(1)
    | e in ESCENAS
];
array[1..M] of int: dur_ord = [
    sum(e in ESCENAS where rango_dur[e] == k)(Duracion[e]) | k in 1..M
];

array[ACTORES] of int: costo_actor = [Escenas[a, M+1] | a in ACTORES];
array[ACTORES] of int: num_esc_actor = [
    sum(e in ESCENAS)(Escenas[a, e]) | a in ACTORES
];
array[ACTORES] of int: dur_min_actor = [
    sum(e in ESCENAS where Escenas[a, e] == 1)(Duracion[e]) | a in ACTORES
];
array[ACTORES] of int: dur_max_actor = [
    if num_esc_actor[a] > 0 then D_total else 0 endif | a in ACTORES
];

int: costo_fijo = sum(a in ACTORES)(costo_actor[a] * dur_min_actor[a]);
int: costo_max  = sum(a in ACTORES)(costo_actor[a] * dur_max_actor[a]);

% Cotas globales ajustadas para las declaraciones de arreglos de variables
int: max_primera_global = max([
    if num_esc_actor[a] > 0 then M - num_esc_actor[a] + 1 else 1 endif | a in ACTORES
]);
int: min_ultima_global = min([
    if num_esc_actor[a] > 0 then num_esc_actor[a] else 1 endif | a in ACTORES
]);
int: max_ini_global = max([
    if num_esc_actor[a] > 0 then D_total - dur_min_actor[a] else 0 endif | a in ACTORES
]);
int: min_fin_global    = min(dur_min_actor);
int: min_tiempo_global = min(dur_min_actor);
int: max_tiempo_global = max(dur_max_actor);
int: max_espera_global = max([dur_max_actor[a] - dur_min_actor[a] | a in ACTORES]);

% Escenas sin participacion de actores (para simetria S3 y ruptura S1)
array[int] of ESCENAS: escenas_vacias = [
    e | e in ESCENAS where forall(a in ACTORES)(Escenas[a, e] == 0)
];
int: q_vacias = length(escenas_vacias);

% Sumas prefijas minimas de escenas ajenas por actor (para cota redundante R4)
array[ACTORES, ESCENAS] of int: rango_ajena = array2d(ACTORES, ESCENAS, [
    if Escenas[a, e] == 0 then
        1 + sum(e2 in ESCENAS where
            Escenas[a, e2] == 0 /\
            (Duracion[e2] < Duracion[e] \/ (Duracion[e2] == Duracion[e] /\ e2 < e))
        )(1)
    else 0 endif
    | a in ACTORES, e in ESCENAS
]);
array[ACTORES, 0..M] of int: pref_min_ajenas = array2d(ACTORES, 0..M, [
    sum(e in ESCENAS where Escenas[a, e] == 0 /\ rango_ajena[a, e] <= q)(Duracion[e])
    | a in ACTORES, q in 0..M
]);

% Ranking estatico de escenas por peso salarial ascendente (para busqueda E1)
array[ESCENAS] of int: peso_salarial_esc = [
    sum(a in ACTORES where Escenas[a, e] == 1)(costo_actor[a]) | e in ESCENAS
];
array[ESCENAS] of 1..M: rango_peso_esc = [
    1 + sum(e2 in ESCENAS where
        peso_salarial_esc[e2] < peso_salarial_esc[e] \/
        (peso_salarial_esc[e2] == peso_salarial_esc[e] /\ e2 < e)
    )(1)
    | e in ESCENAS
];

% ------------------------------------------------------------------------------
% 4. VARIABLES DE DECISION Y DOMINIOS ACOTADOS (CONSISTENCIA DE NODO INICIAL)
% ------------------------------------------------------------------------------
array[POSICIONES] of var ESCENAS: Orden;
array[ESCENAS]    of var POSICIONES: Pos;
array[0..M]       of var 0..D_total: Acum;

array[ACTORES] of var 1..max_primera_global: primera;
array[ACTORES] of var min_ultima_global..M:  ultima;
array[ACTORES] of var 0..max_ini_global:     ini;
array[ACTORES] of var min_fin_global..D_total: fin;
array[ACTORES] of var min_tiempo_global..max_tiempo_global: tiempo;
array[ACTORES] of var 0..max_espera_global:  espera;

var costo_fijo..costo_max: Costo;

% Acotamiento unario exacto por posicion k y por actor a
constraint forall(k in POSICIONES)(
    Acum[k] >= sum(j in 1..k)(dur_ord[j]) /\
    Acum[k] <= sum(j in M-k+1..M)(dur_ord[j])
);

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
constraint forall(j in 1..q_vacias)(
    Orden[j] = escenas_vacias[j]
);

% S1: Ruptura de simetria global de inversion temporal sobre escenas activas
constraint if M - q_vacias >= 2 then
    Orden[q_vacias + 1] < Orden[M]
else true endif;

% S2: Ordenamiento canonico entre escenas gemelas (mismos actores y duracion)
constraint forall(e1, e2 in ESCENAS where
    e1 < e2 /\
    Duracion[e1] == Duracion[e2] /\
    forall(a in ACTORES)(Escenas[a, e1] == Escenas[a, e2])
)(
    Pos[e1] < Pos[e2]
);

% ------------------------------------------------------------------------------
% 7. RESTRICCIONES REDUNDANTES DE FORTALECIMIENTO DE PROPAGACION (R1 - R4)
% ------------------------------------------------------------------------------
% R1: Descomposicion lineal exacta de espera sobre escenas ajenas intermedias
constraint Costo = costo_fijo + sum(a in ACTORES)(costo_actor[a] * espera[a]);
constraint forall(a in ACTORES where num_esc_actor[a] > 0)(
    espera[a] = sum(e in ESCENAS where Escenas[a, e] == 0)(
        Duracion[e] * bool2int(primera[a] < Pos[e] /\ Pos[e] < ultima[a])
    )
);

% R2: Acotamiento combinatorio de diferencias temporales entre pares de turnos
constraint forall(k1 in 1..M-2, k2 in k1+1..M-1)(
    Acum[k2] - Acum[k1] >= sum(j in 1..(k2 - k1))(dur_ord[j]) /\
    Acum[k2] - Acum[k1] <= sum(j in M-(k2 - k1)+1..M)(dur_ord[j])
);

% R3 y R4: Cardinalidad minima de amplitud posicional y cota de espera por exceso
constraint forall(a in ACTORES where num_esc_actor[a] > 0)(
    ultima[a] - primera[a] >= num_esc_actor[a] - 1 /\
    if num_esc_actor[a] < M then
        espera[a] >= pref_min_ajenas[a, ultima[a] - primera[a] + 1 - num_esc_actor[a]]
    else true endif
);

% ------------------------------------------------------------------------------
% 8. ESTRATEGIA DE BUSQUEDA Y DISTRIBUCION
% ------------------------------------------------------------------------------
% Vista reindexada por peso salarial ascendente e intercalada Outside-In
array[POSICIONES] of var 1..M: OrdenRango = [
    rango_peso_esc[Orden[k]] | k in POSICIONES
];
array[POSICIONES] of var 1..M: OrdenRangoExt = [
    if k mod 2 == 1 then OrdenRango[(k + 1) div 2] else OrdenRango[M - (k div 2) + 1] endif
    | k in POSICIONES
];

% Estrategias alternativas exploradas experimentalmente (Seccion 4 del Informe):
% E2: int_search([if k mod 2 == 1 then Orden[(k+1) div 2] else Orden[M-(k div 2)+1] endif | k in POSICIONES], input_order, indomain_min, complete)
% E3: int_search(Orden, input_order, indomain_min, complete)
% E4: int_search(Orden, first_fail, indomain_min, complete)
% E5: int_search(Orden, first_fail, indomain_split, complete)
% E6: int_search([Pos[sum(e in ESCENAS where rango_peso_esc[e] == M-k+1)(e)] | k in 1..M], input_order, indomain_median, complete)
% E7: int_search(OrdenRangoExt, dom_w_deg, indomain_min, complete)
% E8: solve minimize Costo; (busqueda libre nativa del solver)
solve :: int_search(OrdenRangoExt, input_order, indomain_min, complete)
    minimize Costo;

% ------------------------------------------------------------------------------
% 9. INTERFAZ DE SALIDA NORMALIZADA Y VERIFICACION TABULAR DE LA SOLUCION
% ------------------------------------------------------------------------------
output
    [
        show(Orden[k]) ++ if k < M then " " else " " ++ show(Costo) ++ "\n" endif
        | k in POSICIONES
    ] ++
    [
        "************************************************************************\n",
        "PLANIFICACION DE ENSAYOS EN TELENOVELA - PARTE 1\n",
        "************************************************************************\n",
        "Orden de las Escenas: ", show(Orden), "\n",
        "Duracion por Posicion: ", show([Duracion[fix(Orden[k])] | k in POSICIONES]), "\n",
        "Costo Total Optimo:   ", show(Costo), " (Costo base sin esperas: ", show(costo_fijo), ")\n",
        "........................................................................\n",
        "Cronograma por Actor ([X]=Actua, [.]=Espera en estudio, [ ]=Fuera):\n"
    ] ++
    [
        (if k == 1 then show(a) ++ "\t: " else "" endif) ++
        (if num_esc_actor[a] == 0 then "   "
         elseif Escenas[a, fix(Orden[k])] == 1 then "[X]"
         elseif k >= fix(primera[a]) /\ k <= fix(ultima[a]) then "[.]"
         else "   " endif) ++
        (if k == M then
            " | T=" ++ show_int(2, tiempo[a]) ++
            " (Esp=" ++ show_int(2, espera[a]) ++ ")" ++
            " | Costo=" ++ show_int(4, costo_actor[a] * tiempo[a]) ++ "\n"
         else "" endif)
        | a in ACTORES, k in POSICIONES
    ] ++
    ["************************************************************************\n"];
