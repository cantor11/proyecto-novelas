% ==============================================================================
% PROYECTO DE CURSO - PROGRAMACION POR RESTRICCIONES
% Parte 2: Planificacion de ensayos con Disponibilidad, Evitar y Simetrias
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
array[int, 1..2] of int: Disponibilidad;
array[int, 1..2] of ACTORES: Evitar;

set of int: FILAS_DISP = index_set_1of2(Disponibilidad);
set of int: PARES_EVITAR = index_set_1of2(Evitar);

% Flags opcionales sobreescribibles por CLI (-D) sin alterar archivos .dzn
opt bool: opt_usar_simetrias;
opt bool: opt_usar_redundantes;
opt int:  opt_estrategia;
opt bool: opt_salida_pura;

bool: usar_simetrias = opt_usar_simetrias default true;
bool: usar_redundantes = opt_usar_redundantes default true;
int:  estrategia = opt_estrategia default 1;
bool: salida_normalizada_pura = opt_salida_pura default false;

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
    card(FILAS_DISP) == card(ACTORES) /\
    forall(a in ACTORES)(
        sum(r in FILAS_DISP)(bool2int(Disponibilidad[r, 1] == enum2int(a))) == 1
    ),
    "Disponibilidad debe incluir exactamente una entrada para cada actor de ACTORES."
);
constraint assert(
    forall(r in FILAS_DISP)(Disponibilidad[r, 2] >= 0),
    "Los limites temporales en Disponibilidad deben ser >= 0 (0 = tiempo ilimitado)."
);
constraint assert(
    forall(p in PARES_EVITAR)(Evitar[p, 1] != Evitar[p, 2]),
    "Cada fila de Evitar debe relacionar dos actores distintos."
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
array[ACTORES] of int: disp_actor = [
    sum(r in FILAS_DISP where Disponibilidad[r, 1] == enum2int(a))(Disponibilidad[r, 2])
    | a in ACTORES
];

constraint assert(
    forall(a in ACTORES where disp_actor[a] > 0)(dur_min_actor[a] <= disp_actor[a]),
    "Instancia infactible: la duracion propia de las escenas de un actor supera su Disponibilidad."
);

array[ACTORES] of int: dur_max_actor = [
    if num_esc_actor[a] == 0 then 0
    elseif disp_actor[a] > 0 then min(D_total, disp_actor[a])
    else D_total endif
    | a in ACTORES
];

int: costo_fijo = sum(a in ACTORES)(costo_actor[a] * dur_min_actor[a]);
int: costo_max  = sum(a in ACTORES)(costo_actor[a] * dur_max_actor[a]);
int: max_espera_global = max([0] ++ [dur_max_actor[a] - dur_min_actor[a] | a in ACTORES]);

% Cotas exactas a priori para cada par conflictivo en Evitar
array[PARES_EVITAR] of int: solape_min_par = [
    sum(e in ESCENAS where Escenas[Evitar[p, 1], e] == 1 /\ Escenas[Evitar[p, 2], e] == 1)(Duracion[e])
    | p in PARES_EVITAR
];
array[PARES_EVITAR] of int: solape_max_par = [
    min(dur_max_actor[Evitar[p, 1]], dur_max_actor[Evitar[p, 2]])
    | p in PARES_EVITAR
];

int: tc_min = sum(solape_min_par);
int: tc_max = sum(solape_max_par);
int: peso_lex_costo = tc_max + 1;

% Escenas sin participacion de actores
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

array[PARES_EVITAR] of var 0..D_total: solape;

var costo_fijo..costo_max: Costo;
var tc_min..tc_max: TiempoCompartido;
var (peso_lex_costo * costo_fijo + tc_min)..(peso_lex_costo * costo_max + tc_max): ObjetivoLex;

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

constraint forall(p in PARES_EVITAR)(
    solape[p] >= solape_min_par[p] /\
    solape[p] <= solape_max_par[p]
);

% ------------------------------------------------------------------------------
% 5. RESTRICCIONES PRIMARIAS DEL MODELO COP EXTENDIDO (PARTE 2)
% ------------------------------------------------------------------------------
% C1: Biyeccion primal-dual entre secuencia de escenas y posicion por escena
constraint inverse(Orden, Pos);

% C2: Cronologia acumulada continua de rodaje en el estudio
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

% C4: Restriccion de disponibilidad maxima en el estudio (0 = tiempo ilimitado)
constraint forall(a in ACTORES where disp_actor[a] > 0)(
    tiempo[a] <= disp_actor[a]
);

% C5: Tiempo simultaneo en el estudio para pares de actores conflictivos (Evitar)
constraint forall(p in PARES_EVITAR)(
    let {
        ACTORES: a1 = Evitar[p, 1];
        ACTORES: a2 = Evitar[p, 2];
    } in
    if num_esc_actor[a1] > 0 /\ num_esc_actor[a2] > 0 then
        solape[p] = max(0, min(fin[a1], fin[a2]) - max(ini[a1], ini[a2]))
    else
        solape[p] = 0
    endif
);

% Funcion objetivo jerarquica: prioridad 1 Costo, prioridad 2 TiempoCompartido
constraint Costo = sum(a in ACTORES)(costo_actor[a] * tiempo[a]);
constraint TiempoCompartido = sum(solape);
constraint ObjetivoLex = peso_lex_costo * Costo + TiempoCompartido;

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

% R3 y R4: Cotas cardinales inferiores y superiores de amplitud posicional y exceso
constraint if usar_redundantes then
    forall(a in ACTORES where num_esc_actor[a] > 0)(
        ultima[a] - primera[a] >= num_esc_actor[a] - 1 /\
        let {
            int: n_no = M - num_esc_actor[a];
            int: holgura_a = dur_max_actor[a] - dur_min_actor[a];
            array[1..n_no] of int: d_no = sort([Duracion[e] | e in ESCENAS where Escenas[a, e] == 0]);
            array[0..n_no] of int: pref_min = array1d(0..n_no, [0] ++ [sum(j in 1..q)(d_no[j]) | q in 1..n_no]);
            int: w_max_a = sum(q in 1..n_no)(bool2int(pref_min[q] <= holgura_a));
        } in (
            ultima[a] - primera[a] <= num_esc_actor[a] + w_max_a - 1 /\
            if n_no > 0 then
                espera[a] >= pref_min[ultima[a] - primera[a] + 1 - num_esc_actor[a]]
            else true endif
        )
    )
else true endif;

% ------------------------------------------------------------------------------
% 8. ESTRATEGIAS DE BUSQUEDA PARAMETRIZADAS (E1 - E8)
% ------------------------------------------------------------------------------
array[POSICIONES] of var 1..M: OrdenRango = [rango_peso_esc[Orden[k]] | k in POSICIONES];

array[POSICIONES] of var 1..M: OrdenRangoExt = [
    if k mod 2 == 1 then OrdenRango[(k + 1) div 2] else OrdenRango[M - (k div 2) + 1] endif
    | k in POSICIONES
];
array[POSICIONES] of var ESCENAS: OrdenExt = [
    if k mod 2 == 1 then Orden[(k + 1) div 2] else Orden[M - (k div 2) + 1] endif
    | k in POSICIONES
];
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

solve :: anotacion_busqueda minimize ObjetivoLex;

% ------------------------------------------------------------------------------
% 9. INTERFAZ DE SALIDA NORMALIZADA Y VERIFICACION TABULAR DE LA SOLUCION
% ------------------------------------------------------------------------------
output
    if salida_normalizada_pura then
        [
            join(" ", [show(fix(Orden[k])) | k in POSICIONES]) ++
            " " ++ show(fix(Costo)) ++
            " " ++ show(fix(TiempoCompartido)) ++ "\n"
        ]
    else
        [
            join(" ", [show(fix(Orden[k])) | k in POSICIONES]) ++
            " " ++ show(fix(Costo)) ++
            " " ++ show(fix(TiempoCompartido)) ++ "\n",
            "========================================================================\n",
            "PLANIFICACION DE ENSAYOS EN TELENOVELA - PARTE 2\n",
            "========================================================================\n",
            "Orden de las Escenas: ", show(Orden), "\n",
            "Duracion por Posicion: ", show([Duracion[fix(Orden[k])] | k in POSICIONES]), "\n",
            "Costo Total Optimo:   ", show(Costo), " (Costo base sin esperas: ", show(costo_fijo), ")\n",
            "Tiempo Compartido:    ", show(TiempoCompartido), " (Minimo irreductible: ", show(tc_min), ")\n",
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
            "/" ++ (if disp_actor[a] > 0 then show_int(3, disp_actor[a]) else "inf" endif) ++
            " (Esp=" ++ show_int(2, fix(espera[a])) ++ ")" ++
            " | Costo=" ++ show_int(4, costo_actor[a] * fix(tiempo[a])) ++ "\n"
            | a in ACTORES
        ] ++
        [
            "------------------------------------------------------------------------\n",
            "Detalle de Pares en Evitar:\n"
        ] ++
        [
            "  Par (" ++ show(Evitar[p, 1]) ++ ", " ++ show(Evitar[p, 2]) ++ "): " ++
            "solape = " ++ show(fix(solape[p])) ++ " u.t. " ++
            "(escenas comunes = " ++ show(solape_min_par[p]) ++ " u.t.)\n"
            | p in PARES_EVITAR
        ] ++
        ["========================================================================\n"]
    endif;
