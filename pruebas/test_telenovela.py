#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Suite automatizada de validacion (unittest) para el Proyecto de Curso:
Planificacion de los ensayos en una telenovela (Parte 1 y Parte 2).

Verifica:
1. Existencia, sintaxis y formato normalizado de salidas (.txt) en las 13 instancias.
2. Aserciones ante parametros invalidos o disponibilidades infactibles.
3. Optimalidad global certificada contra un oraculo exacto independiente (Held-Karp DP)
   y equivalencia exacta entre Gecode 6.4.0 y Chuffed 0.14.0, incluyendo Evitar vacio.
4. Preservacion del optimo y reduccion del arbol de busqueda por eliminacion de
   simetrias (S1-S3), restricciones redundantes (R1-R4) y prioridad lexicografica.
5. Ejecucion end-to-end del modulo de interfaz/exportacion normalizada (interfaz/app_telenovela.py).
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Dict, List, Tuple

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "interfaz"))

from app_telenovela import (  # noqa: E402
    MODELO_PARTE1,
    MODELO_PARTE2,
    ejecutar_minizinc,
    evaluar_cronograma,
    parsear_archivo_dzn,
)


def oraculo_dp_parte1(datos: Dict) -> int:
    """
    Oraculo exacto independiente O(M * 2^M) por Programacion Dinamica sobre subconjuntos
    de escenas para certificar el costo optimo global de la Parte 1.
    """
    n = datos["num_actores"]
    m = datos["num_escenas"]
    dur = datos["duracion"]
    part = datos["participa"]
    costos = datos["costos"]

    masc_escena = [0] * m
    masc_actor = [0] * n
    dur_min = [0] * n
    for e in range(m):
        me = 0
        for a in range(n):
            if part[a][e] == 1:
                me |= 1 << a
                masc_actor[a] |= 1 << e
                dur_min[a] += dur[e]
        masc_escena[e] = me

    costo_base = sum(costos[a] * dur_min[a] for a in range(n))
    todo = (1 << m) - 1
    inf = 10**15
    dp = [inf] * (1 << m)
    dp[0] = 0

    for s in range(1 << m):
        actual = dp[s]
        if actual == inf:
            continue
        rem = todo ^ s
        activos_mask = 0
        tasa_activos = 0
        for a in range(n):
            ma = masc_actor[a]
            if (s & ma) and (rem & ma):
                activos_mask |= 1 << a
                tasa_activos += costos[a]

        r = rem
        while r:
            lsb = r & -r
            e = lsb.bit_length() - 1
            r ^= lsb
            tasa_espera = tasa_activos
            comunes = activos_mask & masc_escena[e]
            while comunes:
                b = comunes & -comunes
                tasa_espera -= costos[b.bit_length() - 1]
                comunes ^= b
            cand = actual + dur[e] * tasa_espera
            sig = s | lsb
            if cand < dp[sig]:
                dp[sig] = cand

    return costo_base + dp[todo]


def oraculo_exacto_parte2_pequeno(datos: Dict) -> Tuple[int, int]:
    """
    Oraculo exacto independiente Branch-and-Bound para instancias medianas/pequenas
    de Parte 2 que certifica el par lexicografico optimo (Costo*, TiempoCompartido*).
    """
    n = datos["num_actores"]
    m = datos["num_escenas"]
    dur = datos["duracion"]
    part = datos["participa"]
    costos = datos["costos"]
    disp = datos["disponibilidad"]
    evitar = datos["evitar"]

    masc_escena = [sum((1 << a) for a in range(n) if part[a][e]) for e in range(m)]
    masc_actor = [sum((1 << e) for e in range(m) if part[a][e]) for a in range(n)]
    dur_min = [sum(dur[e] for e in range(m) if part[a][e]) for a in range(n)]
    costo_base = sum(costos[a] * dur_min[a] for a in range(n))
    todo = (1 << m) - 1
    inf = 10**12

    # Heuristica admisible exacta h[S] mediante DP en reversa
    h = [inf] * (1 << m)
    h[todo] = 0
    for s in range(todo - 1, -1, -1):
        rem = todo ^ s
        act_mask = 0
        tasa = 0
        for a in range(n):
            ma = masc_actor[a]
            if (s & ma) and (rem & ma):
                act_mask |= 1 << a
                tasa += costos[a]
        mejor = inf
        r = rem
        while r:
            lsb = r & -r
            e = lsb.bit_length() - 1
            r ^= lsb
            w = tasa
            com = act_mask & masc_escena[e]
            while com:
                b = com & -com
                w -= costos[b.bit_length() - 1]
                com ^= b
            val = dur[e] * w + h[s | lsb]
            if val < mejor:
                mejor = val
        h[s] = mejor

    mejor_par = [inf, inf]

    def dfs(s: int, t_act: int, esp_acum: int, ini: List[int], fin: List[int]) -> None:
        if costo_base + esp_acum + h[s] > mejor_par[0]:
            return
        if s == todo:
            tc = 0
            for a1, a2 in evitar:
                if ini[a1] != -1 and ini[a2] != -1:
                    ov = min(fin[a1], fin[a2]) - max(ini[a1], ini[a2])
                    if ov > 0:
                        tc += ov
            c_tot = costo_base + esp_acum
            if (c_tot < mejor_par[0]) or (c_tot == mejor_par[0] and tc < mejor_par[1]):
                mejor_par[0] = c_tot
                mejor_par[1] = tc
            return

        rem = todo ^ s
        for a in range(n):
            if disp[a] > 0:
                ma = masc_actor[a]
                if (s & ma) and (rem & ma):
                    rem_propia = sum(dur[e] for e in range(m) if ((rem & ma) >> e) & 1)
                    if (t_act - ini[a]) + rem_propia > disp[a]:
                        return

        cands = []
        r = rem
        while r:
            lsb = r & -r
            e = lsb.bit_length() - 1
            r ^= lsb
            w = 0
            for a in range(n):
                ma = masc_actor[a]
                if (s & ma) and (rem & ma) and not ((masc_escena[e] >> a) & 1):
                    w += costos[a]
            dw = dur[e] * w
            if costo_base + esp_acum + dw + h[s | lsb] <= mejor_par[0]:
                cands.append((dw + h[s | lsb], e, dw))
        cands.sort()

        for _, e, dw in cands:
            n_ini = list(ini)
            n_fin = list(fin)
            nt = t_act + dur[e]
            ok = True
            for a in range(n):
                if (masc_escena[e] >> a) & 1:
                    if n_ini[a] == -1:
                        n_ini[a] = t_act
                    n_fin[a] = nt
                    if disp[a] > 0 and (n_fin[a] - n_ini[a]) > disp[a]:
                        ok = False
                        break
            if ok:
                dfs(s | (1 << e), nt, esp_acum + dw, n_ini, n_fin)

    dfs(0, 0, 0, [-1] * n, [-1] * n)
    return mejor_par[0], mejor_par[1]


class TestProyectoTelenovelaCOP(unittest.TestCase):
    """Pruebas integrales de Parte 1, Parte 2, simetrias, redundantes e interfaz."""

    def test_01_inventario_modelos_datos_y_salidas_normalizadas(self) -> None:
        self.assertTrue(MODELO_PARTE1.exists(), "Falta TelenovelaParte1.mzn")
        self.assertTrue(MODELO_PARTE2.exists(), "Falta TelenovelaParte2.mzn")

        dzn_p1 = sorted((RAIZ / "datos" / "parte1").glob("*.dzn"))
        dzn_p2 = sorted((RAIZ / "datos" / "parte2").glob("*.dzn"))
        self.assertEqual(len(dzn_p1), 7, "Se esperaban 7 instancias en datos/parte1")
        self.assertEqual(len(dzn_p2), 6, "Se esperaban 6 instancias en datos/parte2")

        for ruta in dzn_p1:
            datos = parsear_archivo_dzn(ruta)
            self.assertEqual(datos["parte"], 1)
            ruta_txt = RAIZ / "salidas" / "parte1" / f"{ruta.stem}.txt"
            self.assertTrue(ruta_txt.exists(), f"Falta salida normalizada {ruta_txt}")
            lineas = [l.strip() for l in ruta_txt.read_text(encoding="utf-8").splitlines() if l.strip()]
            self.assertEqual(len(lineas), 1, "La salida normalizada debe tener una unica linea.")
            vals = [int(x) for x in lineas[0].split()]
            self.assertEqual(len(vals), datos["num_escenas"] + 1)
            ev = evaluar_cronograma(datos, vals[: datos["num_escenas"]])
            self.assertEqual(ev["costo_total"], vals[-1])

        for ruta in dzn_p2:
            datos = parsear_archivo_dzn(ruta)
            self.assertEqual(datos["parte"], 2)
            ruta_txt = RAIZ / "salidas" / "parte2" / f"{ruta.stem}.txt"
            self.assertTrue(ruta_txt.exists(), f"Falta salida normalizada {ruta_txt}")
            lineas = [l.strip() for l in ruta_txt.read_text(encoding="utf-8").splitlines() if l.strip()]
            self.assertEqual(len(lineas), 1, "La salida normalizada debe tener una unica linea.")
            vals = [int(x) for x in lineas[0].split()]
            self.assertEqual(len(vals), datos["num_escenas"] + 2)
            ev = evaluar_cronograma(datos, vals[: datos["num_escenas"]])
            self.assertTrue(ev["factible"])
            self.assertEqual(ev["costo_total"], vals[-2])
            self.assertEqual(ev["tiempo_compartido"], vals[-1])

    def test_02_aserciones_entradas_invalidas(self) -> None:
        casos_invalidos = [
            # Duracion cero en Parte 1
            (
                MODELO_PARTE1,
                "ACTORES={A1,A2}; Escenas=[|1,0,10|0,1,20|]; Duracion=[0,2];",
            ),
            # Valor fuera de 0..1 en Escenas
            (
                MODELO_PARTE1,
                "ACTORES={A1,A2}; Escenas=[|2,0,10|0,1,20|]; Duracion=[1,2];",
            ),
            # Disponibilidad menor que duracion propia obligatoria en Parte 2
            (
                MODELO_PARTE2,
                "ACTORES={A1,A2}; Escenas=[|1,1,10|0,1,20|]; Duracion=[3,4]; "
                "Disponibilidad=[|A1,5|A2,0|]; Evitar=[|A1,A2|];",
            ),
            # Par reflexivo invalido en Evitar
            (
                MODELO_PARTE2,
                "ACTORES={A1,A2}; Escenas=[|1,0,10|0,1,20|]; Duracion=[2,2]; "
                "Disponibilidad=[|A1,0|A2,0|]; Evitar=[|A1,A1|];",
            ),
        ]
        for modelo, contenido in casos_invalidos:
            with tempfile.NamedTemporaryFile("w", suffix=".dzn", delete=False, encoding="utf-8") as tmp:
                tmp.write(contenido)
                ruta_tmp = Path(tmp.name)
            try:
                proc = subprocess.run(
                    ["minizinc", "--solver", "gecode", str(modelo), str(ruta_tmp)],
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(proc.returncode, 0, f"Debio fallar asercion para: {contenido}")
            finally:
                ruta_tmp.unlink(missing_ok=True)

    def test_03_optimalidad_oraculo_y_equivalencia_gecode_chuffed(self) -> None:
        # Parte 1: equivalencia Gecode == Chuffed == Oraculo DP en instancias hasta M=12
        for nombre in ("Trivial1.dzn", "Instancia01_P1.dzn", "Instancia02_P1.dzn", "Instancia03_P1.dzn"):
            ruta = RAIZ / "datos" / "parte1" / nombre
            datos = parsear_archivo_dzn(ruta)
            opt_dp = oraculo_dp_parte1(datos)
            res_gec = ejecutar_minizinc(ruta, solver="gecode", timeout_ms=20000)
            res_chu = ejecutar_minizinc(ruta, solver="chuffed", timeout_ms=20000)
            self.assertTrue(res_gec["optimo_probado"])
            self.assertTrue(res_chu["optimo_probado"])
            self.assertEqual(res_gec["evaluacion"]["costo_total"], opt_dp)
            self.assertEqual(res_chu["evaluacion"]["costo_total"], opt_dp)

        # Certificacion de casos insignia M=20: Desenfreno2 (871) y Desenfreno4 (880, 37)
        res_d2 = ejecutar_minizinc(RAIZ / "datos" / "parte1" / "Desenfreno2.dzn", solver="chuffed", timeout_ms=25000)
        self.assertTrue(res_d2["optimo_probado"])
        self.assertEqual(res_d2["evaluacion"]["costo_total"], 871)

        res_d4 = ejecutar_minizinc(RAIZ / "datos" / "parte2" / "Desenfreno4.dzn", solver="chuffed", timeout_ms=25000)
        self.assertTrue(res_d4["optimo_probado"])
        self.assertEqual(res_d4["evaluacion"]["costo_total"], 880)
        self.assertEqual(res_d4["evaluacion"]["tiempo_compartido"], 37)

        # Parte 2: equivalencia Gecode == Chuffed == Oraculo Exacto B&B en instancias hasta M=12
        for nombre in ("Trivial2.dzn", "Instancia01_P2.dzn", "Instancia02_P2.dzn", "Instancia03_P2.dzn"):
            ruta = RAIZ / "datos" / "parte2" / nombre
            datos = parsear_archivo_dzn(ruta)
            opt_c, opt_tc = oraculo_exacto_parte2_pequeno(datos)
            res_gec = ejecutar_minizinc(ruta, solver="gecode", timeout_ms=20000)
            res_chu = ejecutar_minizinc(ruta, solver="chuffed", timeout_ms=20000)
            self.assertTrue(res_gec["optimo_probado"])
            self.assertTrue(res_chu["optimo_probado"])
            self.assertEqual(
                (res_gec["evaluacion"]["costo_total"], res_gec["evaluacion"]["tiempo_compartido"]),
                (opt_c, opt_tc),
            )
            self.assertEqual(
                (res_chu["evaluacion"]["costo_total"], res_chu["evaluacion"]["tiempo_compartido"]),
                (opt_c, opt_tc),
            )

        # Caso borde: estructura Evitar vacia (0 restricciones en Evitar)
        dzn_ev_vacio = (
            "ACTORES = {Actor1, Actor2, Actor3};\n"
            "Escenas = [| 1,1,0,10 | 0,1,1,20 | 1,0,1,15 |];\n"
            "Duracion = [2, 1, 3];\n"
            "Disponibilidad = [| Actor1, 0 | Actor2, 5 | Actor3, 0 |];\n"
            "Evitar = [||];\n"
        )
        with tempfile.NamedTemporaryFile("w", suffix=".dzn", delete=False, encoding="utf-8") as tmp:
            tmp.write(dzn_ev_vacio)
            ruta_vacio = Path(tmp.name)
        try:
            res_v = ejecutar_minizinc(ruta_vacio, solver="gecode", timeout_ms=10000)
            self.assertTrue(res_v["optimo_probado"])
            self.assertEqual(res_v["evaluacion"]["tiempo_compartido"], 0)
        finally:
            ruta_vacio.unlink(missing_ok=True)

    def test_04_ablacion_simetrias_redundantes_y_prioridad_lexicografica(self) -> None:
        # Comparacion con y sin simetrias/redundantes en Instancia01_P1 (contiene S1, S2 y S3)
        ruta_s = RAIZ / "datos" / "parte1" / "Instancia01_P1.dzn"
        con_todo = ejecutar_minizinc(ruta_s, solver="gecode", usar_simetrias=True, usar_redundantes=True)
        sin_sim = ejecutar_minizinc(ruta_s, solver="gecode", usar_simetrias=False, usar_redundantes=True)
        sin_ambos = ejecutar_minizinc(ruta_s, solver="gecode", usar_simetrias=False, usar_redundantes=False)

        self.assertEqual(con_todo["evaluacion"]["costo_total"], sin_sim["evaluacion"]["costo_total"])
        self.assertEqual(con_todo["evaluacion"]["costo_total"], sin_ambos["evaluacion"]["costo_total"])
        self.assertLess(int(con_todo["stats"]["nodes"]), int(sin_sim["stats"]["nodes"]))
        self.assertLess(int(con_todo["stats"]["nodes"]), int(sin_ambos["stats"]["nodes"]))

        # Verificacion de que en Instancia03_P2 la restriccion de Disponibilidad eleva estrictamente el costo respecto a Parte 1
        res_p1 = ejecutar_minizinc(RAIZ / "datos" / "parte1" / "Instancia03_P1.dzn", solver="chuffed")
        res_p2 = ejecutar_minizinc(RAIZ / "datos" / "parte2" / "Instancia03_P2.dzn", solver="chuffed")
        self.assertGreater(res_p2["evaluacion"]["costo_total"], res_p1["evaluacion"]["costo_total"])

    def test_05_interfaz_cli_exportacion_normalizada(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sal_p1 = Path(tmpdir) / "out_p1.txt"
            sal_p2 = Path(tmpdir) / "out_p2.txt"

            p1 = subprocess.run(
                [
                    sys.executable,
                    str(RAIZ / "interfaz" / "app_telenovela.py"),
                    "--entrada",
                    str(RAIZ / "datos" / "parte1" / "Trivial1.dzn"),
                    "--salida",
                    str(sal_p1),
                    "--solver",
                    "gecode",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertTrue(sal_p1.exists())
            self.assertEqual(sal_p1.read_text(encoding="utf-8").strip(), p1.stdout.strip())
            self.assertTrue(sal_p1.read_text(encoding="utf-8").strip().endswith(" 255"))

            p2 = subprocess.run(
                [
                    sys.executable,
                    str(RAIZ / "interfaz" / "app_telenovela.py"),
                    "--entrada",
                    str(RAIZ / "datos" / "parte2" / "Trivial2.dzn"),
                    "--salida",
                    str(sal_p2),
                    "--solver",
                    "gecode",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertTrue(sal_p2.exists())
            self.assertEqual(sal_p2.read_text(encoding="utf-8").strip(), p2.stdout.strip())
            self.assertTrue(sal_p2.read_text(encoding="utf-8").strip().endswith(" 450 6"))

    def test_06_adherencia_constructos_fundamentos_y_ocho_estrategias(self) -> None:
        import re

        constructos_prohibidos = [
            r"\bopt\s+(?:bool|int|float|set)\b",
            r"\bdefault\b",
            r"\belseif\b",
            r"\benum2int\s*\(",
            r"\bindex_set_1of2\s*\(",
            r"\barg_sort\s*\(",
            r"\bsort\s*\(",
            r"\bjoin\s*\(",
            r"\bconcat\s*\(",
        ]
        for modelo in (MODELO_PARTE1, MODELO_PARTE2):
            lineas_codigo = [
                ln.split("%", 1)[0]
                for ln in modelo.read_text(encoding="utf-8").splitlines()
            ]
            sin_comentarios = "\n".join(lineas_codigo)
            for pat in constructos_prohibidos:
                self.assertIsNone(
                    re.search(pat, sin_comentarios),
                    f"Constructo ajeno a Fundamentos ({pat}) detectado en {modelo.name}",
                )

        # Invarianza del optimo global bajo las 8 estrategias E1..E8
        for est in range(1, 9):
            r1 = ejecutar_minizinc(
                RAIZ / "datos" / "parte1" / "Trivial1.dzn",
                solver="gecode",
                estrategia=est,
                timeout_ms=10000,
            )
            self.assertTrue(r1["optimo_probado"])
            self.assertEqual(r1["evaluacion"]["costo_total"], 255)

            r2 = ejecutar_minizinc(
                RAIZ / "datos" / "parte2" / "Trivial2.dzn",
                solver="gecode",
                estrategia=est,
                timeout_ms=10000,
            )
            self.assertTrue(r2["optimo_probado"])
            self.assertEqual(
                (r2["evaluacion"]["costo_total"], r2["evaluacion"]["tiempo_compartido"]),
                (450, 6),
            )

    def test_07_recuperacion_simetrias_y_enumeracion_nombres_arbitrarios(self) -> None:
        import itertools

        # 1. Recuperacion algebraica completa de la orbita de soluciones optimas en Instancia01_P1
        #    E_vacias = {2, 7} (q=2), gemelas G1={3,5}, G2={4,6}, canonica = [2, 7, 3, 5, 8, 1, 4, 6] (Costo*=225)
        datos_i1 = parsear_archivo_dzn(RAIZ / "datos" / "parte1" / "Instancia01_P1.dzn")
        res_i1 = ejecutar_minizinc(RAIZ / "datos" / "parte1" / "Instancia01_P1.dzn", solver="gecode")
        canon = res_i1["evaluacion"]["orden"]
        costo_opt = res_i1["evaluacion"]["costo_total"]
        self.assertEqual(costo_opt, 225)

        vacias = canon[:2]
        activo = canon[2:]
        orbita_i1 = set()
        for swap_35 in (False, True):
            for swap_46 in (False, True):
                seq = list(activo)
                if swap_35:
                    seq = [5 if x == 3 else (3 if x == 5 else x) for x in seq]
                if swap_46:
                    seq = [6 if x == 4 else (4 if x == 6 else x) for x in seq]
                for invertir in (False, True):
                    bloque = list(reversed(seq)) if invertir else list(seq)
                    for perm_vac in itertools.permutations(vacias):
                        for k_pref in range(len(vacias) + 1):
                            cand = tuple(list(perm_vac[:k_pref]) + bloque + list(perm_vac[k_pref:]))
                            orbita_i1.add(cand)

        self.assertEqual(len(orbita_i1), 48, "La orbita simetrica S1xS2xS3 debe tener 2*2*2*(2!*3)=48 soluciones")
        for perm in orbita_i1:
            ev = evaluar_cronograma(datos_i1, list(perm))
            self.assertEqual(ev["costo_total"], costo_opt)

        # 2. Recuperacion de la solucion comentada en Trivial2.dzn ([4, 3, 6, 2, 1, 5]) desde [3, 4, 6, 2, 1, 5]
        datos_t2 = parsear_archivo_dzn(RAIZ / "datos" / "parte2" / "Trivial2.dzn")
        for perm_t2 in ([3, 4, 6, 2, 1, 5], [4, 3, 6, 2, 1, 5], [5, 1, 2, 6, 4, 3], [5, 1, 2, 6, 3, 4]):
            ev_t2 = evaluar_cronograma(datos_t2, perm_t2)
            self.assertTrue(ev_t2["factible"])
            self.assertEqual((ev_t2["costo_total"], ev_t2["tiempo_compartido"]), (450, 6))

        # 3. Preservacion del orden de declaracion en enum ACTORES con nombres arbitrarios y Disponibilidad desordenada
        dzn_nombres = (
            "ACTORES = {NarcisoPerfiles, Catalina, Armando, Beatriz};\n"
            "Escenas = [| 1,1,0,0,0,0,10\n"
            "           | 0,1,1,1,0,1,20\n"
            "           | 0,0,0,0,1,1,15\n"
            "           | 1,1,0,0,1,1,13 |];\n"
            "Duracion = [2,1,1,1,3,4];\n"
            "Disponibilidad = [| Armando, 0\n"
            "                  | Beatriz, 10\n"
            "                  | NarcisoPerfiles, 5\n"
            "                  | Catalina, 8 |];\n"
            "Evitar = [| NarcisoPerfiles, Catalina\n"
            "          | Catalina, Armando |];\n"
        )
        with tempfile.NamedTemporaryFile("w", suffix=".dzn", delete=False, encoding="utf-8") as tmp:
            tmp.write(dzn_nombres)
            ruta_nom = Path(tmp.name)
        try:
            res_nom = ejecutar_minizinc(ruta_nom, solver="chuffed", timeout_ms=10000)
            self.assertTrue(res_nom["optimo_probado"])
            self.assertEqual(
                (res_nom["evaluacion"]["costo_total"], res_nom["evaluacion"]["tiempo_compartido"]),
                (450, 6),
            )
        finally:
            ruta_nom.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
