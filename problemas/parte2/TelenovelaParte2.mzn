% Proyecto de Curso - Programacion por Restricciones
% Parte 2: Planificacion de ensayos con Disponibilidad, Evitar y Simetrias
% Escuela de Ingenieria de Sistemas y Computacion - Universidad del Valle
% Integrantes: Cristian David Cabrera Pantoja, Junior Orlando Cantor Arevalo,
%              Juan Diego Cardenas Mejia
% Profesor: Robinson Duque

include "globals.mzn";

% --- 1. Parametros de entrada ---
enum ACTORES;
array[int] of int: Duracion;

int: M = length(Duracion);
set of int: ESCENAS = 1..M;
set of int: POSICIONES = 1..M;

array[ACTORES, 1..M+1] of int: Escenas;
array[int, 1..2] of int: Disponibilidad;
array[int, 1..2] of ACTORES: Evitar;

int: num_filas_disp   = length(Disponibilidad) div 2;
int: num_pares_evitar = length(Evitar) div 2;
set of int: FILAS_DISP   = 1..num_filas_disp;
set of int: PARES_EVITAR = 1..num_pares_evitar;

array[ACTORES] of int: indice_actor = [
    sum(b in ACTORES where b <= a)(1) | a in ACTORES
];

% --- 2. Validacion de parametros ---
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
constraint assert(
    num_filas_disp == card(ACTORES) /\
    forall(a in ACTORES)(
        sum(r in FILAS_DISP)(bool2int(Disponibilidad[r, 1] == indice_actor[a])) == 1
    ),
    "Error de entrada: Disponibilidad debe contener exactamente una fila por actor."
);
constraint assert(
    forall(r in FILAS_DISP)(Disponibilidad[r, 2] >= 0),
    "Error de entrada: Disponibilidad no puede ser negativa (0 = ilimitada)."
);
constraint assert(
    forall(p in PARES_EVITAR)(Evitar[p, 1] != Evitar[p, 2]),
    "Error de entrada: cada par en Evitar debe relacionar dos actores distintos."
);

% --- 3. Parametros derivados y cotas ---
int: D_total = sum(e in ESCENAS)(Duracion[e]);

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
array[ACTORES] of int: disp_actor = [
    sum(r in FILAS_DISP where Disponibilidad[r, 1] == indice_actor[a])(Disponibilidad[r, 2])
    | a in ACTORES
];

constraint assert(
    forall(a in ACTORES where disp_actor[a] > 0)(dur_min_actor[a] <= disp_actor[a]),
    "Instancia infactible: la duracion propia de un actor supera su Disponibilidad."
);

array[ACTORES] of int: dur_max_actor = [
    if num_esc_actor[a] == 0 then 0
    else if disp_actor[a] > 0 then min(D_total, disp_actor[a])
    else D_total endif endif
    | a in ACTORES
];

int: costo_fijo = sum(a in ACTORES)(costo_actor[a] * dur_min_actor[a]);
int: costo_max  = sum(a in ACTORES)(costo_actor[a] * dur_max_actor[a]);

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

array[PARES_EVITAR] of int: solape_min_par = [
    sum(e in ESCENAS where Escenas[Evitar[p, 1], e] == 1 /\ Escenas[Evitar[p, 2], e] == 1)(Duracion[e])
    | p in PARES_EVITAR
];
array[PARES_EVITAR] of int: solape_max_par = [
    min(dur_max_actor[Evitar[p, 1]], dur_max_actor[Evitar[p, 2]])
    | p in PARES_EVITAR
];

int: min_solape_par = if num_pares_evitar > 0 then min(solape_min_par) else 0 endif;
int: max_solape_par = if num_pares_evitar > 0 then max(solape_max_par) else 0 endif;
int: tc_min = sum(p in PARES_EVITAR)(solape_min_par[p]);
int: tc_max = sum(p in PARES_EVITAR)(solape_max_par[p]);
int: peso_lex_costo = tc_max + 1;

array[int] of ESCENAS: escenas_vacias = [
    e | e in ESCENAS where forall(a in ACTORES)(Escenas[a, e] == 0)
];
int: q_vacias = length(escenas_vacias);

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
array[ACTORES] of int: max_intermedias_actor = [
    sum(q in 1..(M - num_esc_actor[a]))(
        bool2int(pref_min_ajenas[a, q] <= dur_max_actor[a] - dur_min_actor[a])
    )
    | a in ACTORES
];

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

% --- 4. Variables de decision y dominios ---
array[POSICIONES] of var ESCENAS: Orden;
array[ESCENAS]    of var POSICIONES: Pos;
array[0..M]       of var 0..D_total: Acum;

array[ACTORES] of var 1..max_primera_global: primera;
array[ACTORES] of var min_ultima_global..M:  ultima;
array[ACTORES] of var 0..max_ini_global:     ini;
array[ACTORES] of var min_fin_global..D_total: fin;
array[ACTORES] of var min_tiempo_global..max_tiempo_global: tiempo;
array[ACTORES] of var 0..max_espera_global:  espera;

array[PARES_EVITAR] of var min_solape_par..max_solape_par: solape;

var costo_fijo..costo_max: Costo;
var tc_min..tc_max: TiempoCompartido;
var (peso_lex_costo * costo_fijo + tc_min)..(peso_lex_costo * costo_max + tc_max): ObjetivoLex;

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

constraint forall(p in PARES_EVITAR)(
    solape[p] >= solape_min_par[p] /\
    solape[p] <= solape_max_par[p]
);

% --- 5. Restricciones primarias ---
% C1: Biyeccion entre secuencia de escenas y posicion por escena
constraint inverse(Orden, Pos);

% C2: Tiempo acumulado de rodaje
constraint Acum[0] = 0 /\ Acum[M] = D_total;
constraint forall(k in POSICIONES)(
    Acum[k] = Acum[k - 1] + Duracion[Orden[k]]
);

% C3: Intervalo de permanencia por actor
constraint forall(a in ACTORES where num_esc_actor[a] > 0)(
    primera[a] = min([Pos[e] | e in ESCENAS where Escenas[a, e] == 1]) /\
    ultima[a]  = max([Pos[e] | e in ESCENAS where Escenas[a, e] == 1]) /\
    ini[a]     = Acum[primera[a] - 1] /\
    fin[a]     = Acum[ultima[a]] /\
    tiempo[a]  = fin[a] - ini[a] /\
    espera[a]  = tiempo[a] - dur_min_actor[a]
);

% C4: Disponibilidad maxima en el estudio (0 = ilimitada)
constraint forall(a in ACTORES where disp_actor[a] > 0)(
    tiempo[a] <= disp_actor[a]
);

% C5: Tiempo compartido en el estudio para pares en Evitar
constraint forall(p in PARES_EVITAR)(
    if num_esc_actor[Evitar[p, 1]] > 0 /\ num_esc_actor[Evitar[p, 2]] > 0 then
        solape[p] = max(0,
            min(fin[Evitar[p, 1]], fin[Evitar[p, 2]]) -
            max(ini[Evitar[p, 1]], ini[Evitar[p, 2]])
        )
    else
        solape[p] = 0
    endif
);

% Funcion objetivo jerarquica: prioridad 1 Costo, prioridad 2 TiempoCompartido
constraint Costo = sum(a in ACTORES)(costo_actor[a] * tiempo[a]);
constraint TiempoCompartido = sum(p in PARES_EVITAR)(solape[p]);
constraint ObjetivoLex = peso_lex_costo * Costo + TiempoCompartido;

% --- 6. Eliminacion de simetrias (S1, S2, S3) ---
% S3: Escenas vacias fijadas en prefijo
constraint forall(j in 1..q_vacias)(
    Orden[j] = escenas_vacias[j]
);

% S1: Ruptura de inversion temporal sobre escenas activas
constraint if M - q_vacias >= 2 then
    Orden[q_vacias + 1] < Orden[M]
else true endif;

% S2: Orden canonico entre escenas gemelas
constraint forall(e1, e2 in ESCENAS where
    e1 < e2 /\
    Duracion[e1] == Duracion[e2] /\
    forall(a in ACTORES)(Escenas[a, e1] == Escenas[a, e2])
)(
    Pos[e1] < Pos[e2]
);

% --- 7. Restricciones redundantes (R1 - R4) ---
% R1: Descomposicion lineal de espera sobre escenas ajenas intermedias
constraint Costo = costo_fijo + sum(a in ACTORES)(costo_actor[a] * espera[a]);
constraint forall(a in ACTORES where num_esc_actor[a] > 0)(
    espera[a] = sum(e in ESCENAS where Escenas[a, e] == 0)(
        Duracion[e] * bool2int(primera[a] < Pos[e] /\ Pos[e] < ultima[a])
    )
);

% R2: Cotas de diferencias temporales entre pares de turnos
constraint forall(k1 in 1..M-2, k2 in k1+1..M-1)(
    Acum[k2] - Acum[k1] >= sum(j in 1..(k2 - k1))(dur_ord[j]) /\
    Acum[k2] - Acum[k1] <= sum(j in M-(k2 - k1)+1..M)(dur_ord[j])
);

% R3 y R4: Cotas de amplitud posicional y espera minima por exceso
constraint forall(a in ACTORES where num_esc_actor[a] > 0)(
    ultima[a] - primera[a] >= num_esc_actor[a] - 1 /\
    ultima[a] - primera[a] <= num_esc_actor[a] + max_intermedias_actor[a] - 1 /\
    if num_esc_actor[a] < M then
        espera[a] >= pref_min_ajenas[a, ultima[a] - primera[a] + 1 - num_esc_actor[a]]
    else true endif
);

% --- 8. Estrategia de busqueda ---
array[POSICIONES] of var 1..M: OrdenRango = [
    rango_peso_esc[Orden[k]] | k in POSICIONES
];
array[POSICIONES] of var 1..M: OrdenRangoExt = [
    if k mod 2 == 1 then OrdenRango[(k + 1) div 2] else OrdenRango[M - (k div 2) + 1] endif
    | k in POSICIONES
];

% Variantes evaluadas en la Seccion 4 del informe:
% E2: int_search([if k mod 2 == 1 then Orden[(k+1) div 2] else Orden[M-(k div 2)+1] endif | k in POSICIONES], input_order, indomain_min, complete)
% E3: int_search(Orden, input_order, indomain_min, complete)
% E4: int_search(Orden, first_fail, indomain_min, complete)
% E5: int_search(Orden, first_fail, indomain_split, complete)
% E6: int_search([Pos[sum(e in ESCENAS where rango_peso_esc[e] == M-k+1)(e)] | k in 1..M], input_order, indomain_median, complete)
% E7: int_search(OrdenRangoExt, dom_w_deg, indomain_min, complete)
% E8: solve minimize ObjetivoLex;
solve :: int_search(OrdenRangoExt, input_order, indomain_min, complete)
    minimize ObjetivoLex;

% --- 9. Salida ---
output
    [
        show(Orden[k]) ++
        if k < M then " "
        else " " ++ show(Costo) ++ " " ++ show(TiempoCompartido) ++ "\n"
        endif
        | k in POSICIONES
    ] ++
    [
        "------------------------------------------------------------\n",
        "PLANIFICACION DE ENSAYOS EN TELENOVELA - PARTE 2\n",
        "------------------------------------------------------------\n",
        "Orden de las Escenas: ", show(Orden), "\n",
        "Duracion por Posicion: ", show([Duracion[fix(Orden[k])] | k in POSICIONES]), "\n",
        "Costo Total Optimo:   ", show(Costo), " (Costo base sin esperas: ", show(costo_fijo), ")\n",
        "Tiempo Compartido:    ", show(TiempoCompartido), " (Minimo irreductible: ", show(tc_min), ")\n",
        "------------------------------------------------------------\n",
        "Cronograma por Actor ([X]=Actua, [.]=Espera, [ ]=Fuera):\n"
    ] ++
    [
        (if k == 1 then show(a) ++ "\t: " else "" endif) ++
        (if num_esc_actor[a] == 0 then "   "
         else if Escenas[a, fix(Orden[k])] == 1 then "[X]"
         else if k >= fix(primera[a]) /\ k <= fix(ultima[a]) then "[.]"
         else "   " endif endif endif) ++
        (if k == M then
            " | T=" ++ show_int(2, tiempo[a]) ++
            "/" ++ (if disp_actor[a] > 0 then show_int(3, disp_actor[a]) else "inf" endif) ++
            " (Esp=" ++ show_int(2, espera[a]) ++ ")" ++
            " | Costo=" ++ show_int(4, costo_actor[a] * tiempo[a]) ++ "\n"
         else "" endif)
        | a in ACTORES, k in POSICIONES
    ] ++
    [
        "------------------------------------------------------------\n",
        "Detalle de Pares en Evitar:\n"
    ] ++
    [
        "  Par (" ++ show(Evitar[p, 1]) ++ ", " ++ show(Evitar[p, 2]) ++ "): " ++
        "solape = " ++ show(solape[p]) ++ " u.t. " ++
        "(escenas comunes = " ++ show(solape_min_par[p]) ++ " u.t.)\n"
        | p in PARES_EVITAR
    ] ++
    ["------------------------------------------------------------\n"];
