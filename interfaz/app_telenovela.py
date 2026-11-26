#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Interfaz grafica (Tkinter) y de linea de comandos para el Proyecto de Curso:
Planificacion de los ensayos en una telenovela (Parte 1 y Parte 2).

Lee archivos de entrada normalizados (*.dzn), ejecuta los modelos COP en MiniZinc,
verifica matematicamente todas las restricciones del pedido de entrada, visualiza
el diagrama de Gantt de permanencia/esperas/conflictos y escribe el archivo de
texto con la salida normalizada de una linea.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


RAIZ_PROYECTO = Path(__file__).resolve().parent.parent
MODELO_PARTE1 = RAIZ_PROYECTO / "problemas" / "parte1" / "TelenovelaParte1.mzn"
MODELO_PARTE2 = RAIZ_PROYECTO / "problemas" / "parte2" / "TelenovelaParte2.mzn"


def limpiar_comentarios_dzn(texto: str) -> str:
    """Elimina comentarios de linea (%) preservando saltos de linea."""
    lineas = []
    for linea in texto.splitlines():
        pos = linea.find("%")
        if pos != -1:
            linea = linea[:pos]
        lineas.append(linea)
    return "\n".join(lineas)


def parsear_archivo_dzn(ruta_dzn: Path) -> Dict[str, Any]:
    """Parsea un archivo .dzn normalizado de Parte 1 o Parte 2."""
    crudo = ruta_dzn.read_text(encoding="utf-8")
    limpio = limpiar_comentarios_dzn(crudo)

    m_act = re.search(r"ACTORES\s*=\s*\{([^}]*)\}\s*;", limpio, re.DOTALL)
    if not m_act:
        raise ValueError(f"No se encontro la definicion de ACTORES en {ruta_dzn}")
    actores = [tok.strip() for tok in m_act.group(1).split(",") if tok.strip()]
    mapa_actor = {nombre: idx for idx, nombre in enumerate(actores)}

    m_dur = re.search(r"Duracion\s*=\s*\[([^\]]*)\]\s*;", limpio, re.DOTALL)
    if not m_dur:
        raise ValueError(f"No se encontro el arreglo Duracion en {ruta_dzn}")
    duracion = [int(tok.strip()) for tok in m_dur.group(1).split(",") if tok.strip()]
    num_escenas = len(duracion)

    m_esc = re.search(r"Escenas\s*=\s*\[\|(.*?)\|\s*\]\s*;", limpio, re.DOTALL)
    if not m_esc:
        raise ValueError(f"No se encontro la matriz Escenas en {ruta_dzn}")
    filas_esc_txt = [f.strip() for f in m_esc.group(1).split("|") if f.strip()]
    if len(filas_esc_txt) != len(actores):
        raise ValueError(
            f"Escenas tiene {len(filas_esc_txt)} filas pero ACTORES tiene {len(actores)}."
        )

    participa: List[List[int]] = []
    costos: List[int] = []
    for fila_txt in filas_esc_txt:
        vals = [int(v.strip()) for v in fila_txt.split(",") if v.strip()]
        if len(vals) != num_escenas + 1:
            raise ValueError(
                f"Fila de Escenas tiene {len(vals)} columnas; se esperaban {num_escenas + 1}."
            )
        participa.append(vals[:num_escenas])
        costos.append(vals[num_escenas])

    m_disp = re.search(r"Disponibilidad\s*=\s*\[\|(.*?)\|\s*\]\s*;", limpio, re.DOTALL)
    m_evit = re.search(r"Evitar\s*=\s*\[\|(.*?)\|\s*\]\s*;", limpio, re.DOTALL)
    es_parte2 = m_disp is not None

    disponibilidad: Optional[List[int]] = None
    evitar: List[Tuple[int, int]] = []

    if es_parte2:
        disponibilidad = [0] * len(actores)
        filas_disp = [f.strip() for f in m_disp.group(1).split("|") if f.strip()]
        for f_txt in filas_disp:
            partes = [p.strip() for p in f_txt.split(",") if p.strip()]
            idx_a = mapa_actor[partes[0]]
            disponibilidad[idx_a] = int(partes[1])

        if m_evit and m_evit.group(1).strip():
            filas_ev = [f.strip() for f in m_evit.group(1).split("|") if f.strip()]
            for f_txt in filas_ev:
                partes = [p.strip() for p in f_txt.split(",") if p.strip()]
                evitar.append((mapa_actor[partes[0]], mapa_actor[partes[1]]))

    return {
        "ruta": ruta_dzn,
        "texto_crudo": crudo,
        "parte": 2 if es_parte2 else 1,
        "actores": actores,
        "num_actores": len(actores),
        "num_escenas": num_escenas,
        "duracion": duracion,
        "participa": participa,
        "costos": costos,
        "disponibilidad": disponibilidad,
        "evitar": evitar,
    }


def evaluar_cronograma(datos: Dict[str, Any], orden: List[int]) -> Dict[str, Any]:
    """
    Evalua y verifica de forma independiente un orden de grabacion (1-indexado)
    contra todos los parametros y restricciones de Parte 1 o Parte 2.
    """
    m = datos["num_escenas"]
    n = datos["num_actores"]
    dur = datos["duracion"]
    part = datos["participa"]
    costos = datos["costos"]
    disp = datos["disponibilidad"]

    if sorted(orden) != list(range(1, m + 1)):
        raise ValueError(f"El vector Orden={orden} no es una permutacion valida de 1..{m}.")

    # Linea de tiempo acumulada por posicion
    acum = [0] * (m + 1)
    bloques_escena = []
    for k, esc_1based in enumerate(orden, start=1):
        d_e = dur[esc_1based - 1]
        acum[k] = acum[k - 1] + d_e
        bloques_escena.append(
            {
                "posicion": k,
                "escena": esc_1based,
                "duracion": d_e,
                "t_ini": acum[k - 1],
                "t_fin": acum[k],
            }
        )

    pos_de_escena = {esc: k for k, esc in enumerate(orden, start=1)}
    detalle_actores = []
    costo_total = 0
    costo_base = 0
    disponibilidad_ok = True

    for a in range(n):
        esc_propias = [e for e in range(1, m + 1) if part[a][e - 1] == 1]
        dur_min = sum(dur[e - 1] for e in esc_propias)
        costo_base += costos[a] * dur_min

        if esc_propias:
            posiciones = [pos_de_escena[e] for e in esc_propias]
            primera = min(posiciones)
            ultima = max(posiciones)
            t_ini = acum[primera - 1]
            t_fin = acum[ultima]
            tiempo = t_fin - t_ini
            espera = tiempo - dur_min
        else:
            primera, ultima = 0, 0
            t_ini, t_fin, tiempo, espera = 0, 0, 0, 0

        costo_act = costos[a] * tiempo
        costo_total += costo_act
        lim_disp = disp[a] if disp is not None else 0
        cumple = True if (lim_disp == 0 or tiempo <= lim_disp) else False
        if not cumple:
            disponibilidad_ok = False

        detalle_actores.append(
            {
                "indice": a + 1,
                "nombre": datos["actores"][a],
                "costo_unit": costos[a],
                "primera": primera,
                "ultima": ultima,
                "t_ini": t_ini,
                "t_fin": t_fin,
                "dur_min": dur_min,
                "tiempo": tiempo,
                "espera": espera,
                "disponibilidad": lim_disp,
                "cumple_disp": cumple,
                "costo_total": costo_act,
            }
        )

    detalle_evitar = []
    tiempo_compartido = 0
    if datos["parte"] == 2:
        for a1, a2 in datos["evitar"]:
            info1 = detalle_actores[a1]
            info2 = detalle_actores[a2]
            if info1["tiempo"] > 0 and info2["tiempo"] > 0:
                ini_ov = max(info1["t_ini"], info2["t_ini"])
                fin_ov = min(info1["t_fin"], info2["t_fin"])
                solape = max(0, fin_ov - ini_ov)
            else:
                ini_ov, fin_ov, solape = 0, 0, 0
            tiempo_compartido += solape
            esc_comunes = sum(
                dur[e]
                for e in range(m)
                if part[a1][e] == 1 and part[a2][e] == 1
            )
            detalle_evitar.append(
                {
                    "actor1": datos["actores"][a1],
                    "actor2": datos["actores"][a2],
                    "t_ini": ini_ov if solape > 0 else 0,
                    "t_fin": fin_ov if solape > 0 else 0,
                    "solape": solape,
                    "min_irreductible": esc_comunes,
                }
            )

    secuencia_txt = " ".join(str(x) for x in orden)
    if datos["parte"] == 1:
        linea_normalizada = f"{secuencia_txt} {costo_total}"
    else:
        linea_normalizada = f"{secuencia_txt} {costo_total} {tiempo_compartido}"

    return {
        "orden": orden,
        "duracion_total": acum[m],
        "bloques_escena": bloques_escena,
        "detalle_actores": detalle_actores,
        "detalle_evitar": detalle_evitar,
        "costo_base": costo_base,
        "costo_total": costo_total,
        "tiempo_compartido": tiempo_compartido,
        "disponibilidad_ok": disponibilidad_ok,
        "factible": disponibilidad_ok,
        "linea_normalizada": linea_normalizada,
    }


def ejecutar_minizinc(
    ruta_dzn: Path,
    solver: str = "chuffed",
    estrategia: int = 1,
    usar_simetrias: bool = True,
    usar_redundantes: bool = True,
    timeout_ms: int = 30000,
    ruta_salida_txt: Optional[Path] = None,
) -> Dict[str, Any]:
    """Ejecuta el modelo MiniZinc correspondiente y verifica el resultado."""
    datos = parsear_archivo_dzn(ruta_dzn)
    modelo = MODELO_PARTE2 if datos["parte"] == 2 else MODELO_PARTE1

    defs = (
        f"opt_estrategia={estrategia};"
        f"opt_usar_simetrias={'true' if usar_simetrias else 'false'};"
        f"opt_usar_redundantes={'true' if usar_redundantes else 'false'};"
        f"opt_salida_pura=true;"
    )
    cmd = [
        "minizinc",
        "--solver",
        solver,
        "--statistics",
        "--time-limit",
        str(timeout_ms),
        "-D",
        defs,
        str(modelo),
        str(ruta_dzn),
    ]

    t0 = time.perf_counter()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    dt_wall = time.perf_counter() - t0

    if proc.returncode != 0 and not proc.stdout.strip():
        raise RuntimeError(f"Error al ejecutar MiniZinc:\n{proc.stderr}")

    optimo_probado = "==========" in proc.stdout
    insatisfactible = "=====UNSATISFIABLE=====" in proc.stdout
    if insatisfactible:
        raise RuntimeError(f"La instancia {ruta_dzn.name} resulto insatisfactible.")

    stats: Dict[str, Any] = {}
    lineas_solucion: List[str] = []
    for ln in proc.stdout.splitlines():
        s = ln.strip()
        if not s:
            continue
        if s.startswith("%%%mzn-stat:"):
            kv = s.replace("%%%mzn-stat:", "").strip()
            if "=" in kv:
                k, v = kv.split("=", 1)
                stats[k.strip()] = v.strip()
        elif s.startswith("%") or s.startswith("---") or s.startswith("==="):
            continue
        else:
            lineas_solucion.append(s)

    if not lineas_solucion:
        raise RuntimeError(
            f"MiniZinc no produjo solucion dentro del limite ({timeout_ms} ms).\n{proc.stdout}"
        )

    ultima_linea = lineas_solucion[-1]
    enteros = [int(tok) for tok in ultima_linea.split()]
    m = datos["num_escenas"]
    orden = enteros[:m]
    costo_mzn = enteros[m]
    tc_mzn = enteros[m + 1] if datos["parte"] == 2 else 0

    evaluacion = evaluar_cronograma(datos, orden)
    if evaluacion["costo_total"] != costo_mzn:
        raise AssertionError(
            f"Discrepancia de costo: MiniZinc={costo_mzn} vs Verificador={evaluacion['costo_total']}"
        )
    if datos["parte"] == 2 and evaluacion["tiempo_compartido"] != tc_mzn:
        raise AssertionError(
            f"Discrepancia en TiempoCompartido: MiniZinc={tc_mzn} vs Verificador={evaluacion['tiempo_compartido']}"
        )
    if not evaluacion["factible"]:
        raise AssertionError("La solucion reportada viola una restriccion de Disponibilidad.")

    if ruta_salida_txt is not None:
        ruta_salida_txt.parent.mkdir(parents=True, exist_ok=True)
        ruta_salida_txt.write_text(evaluacion["linea_normalizada"] + "\n", encoding="utf-8")

    return {
        "datos": datos,
        "evaluacion": evaluacion,
        "optimo_probado": optimo_probado,
        "stats": stats,
        "tiempo_wall": dt_wall,
        "solver": solver,
        "estrategia": estrategia,
        "usar_simetrias": usar_simetrias,
        "usar_redundantes": usar_redundantes,
        "ruta_salida_txt": ruta_salida_txt,
    }


def descubrir_instancias_proyecto() -> List[Path]:
    """Lista todas las instancias .dzn disponibles en datos/parte1 y datos/parte2."""
    rutas: List[Path] = []
    for sub in ("parte1", "parte2"):
        carpeta = RAIZ_PROYECTO / "datos" / sub
        if carpeta.exists():
            rutas.extend(sorted(carpeta.glob("*.dzn")))
    return rutas


def lanzar_interfaz_grafica(ruta_inicial: Optional[Path] = None) -> None:
    """Inicia la interfaz grafica interactiva en Tkinter."""
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk

    raiz = tk.Tk()
    raiz.title("Planificacion de Ensayos en Telenovela - Interfaz COP (MiniZinc)")
    raiz.geometry("1220x780")
    raiz.minsize(980, 640)

    instancias = descubrir_instancias_proyecto()
    mapa_instancias = {f"[P{ '2' if 'parte2' in str(p) else '1' }] {p.name}": p for p in instancias}

    estado_actual: Dict[str, Any] = {"resultado": None, "ruta_dzn": None}

    # --- Barra superior de controles ---
    marco_ctrl = ttk.LabelFrame(raiz, text="Configuracion de Entrada y Ejecucion", padding=8)
    marco_ctrl.pack(fill=tk.X, padx=10, pady=(8, 4))

    ttk.Label(marco_ctrl, text="Instancia:").grid(row=0, column=0, sticky=tk.W, padx=4)
    var_combo = tk.StringVar()
    combo_inst = ttk.Combobox(
        marco_ctrl,
        textvariable=var_combo,
        values=list(mapa_instancias.keys()),
        width=28,
        state="readonly",
    )
    combo_inst.grid(row=0, column=1, padx=4)

    def al_seleccionar_combo(_evt: Any = None) -> None:
        clave = var_combo.get()
        if clave in mapa_instancias:
            estado_actual["ruta_dzn"] = mapa_instancias[clave]
            var_archivo_lbl.set(str(mapa_instancias[clave].relative_to(RAIZ_PROYECTO)))

    combo_inst.bind("<<ComboboxSelected>>", al_seleccionar_combo)

    def abrir_otro_dzn() -> None:
        elegido = filedialog.askopenfilename(
            title="Seleccionar archivo de entrada (.dzn)",
            initialdir=str(RAIZ_PROYECTO / "datos"),
            filetypes=[("Archivos MiniZinc Data", "*.dzn"), ("Todos los archivos", "*.*")],
        )
        if elegido:
            p = Path(elegido)
            estado_actual["ruta_dzn"] = p
            var_archivo_lbl.set(p.name)

    ttk.Button(marco_ctrl, text="Examinar .dzn...", command=abrir_otro_dzn).grid(
        row=0, column=2, padx=4
    )

    ttk.Label(marco_ctrl, text="Solver:").grid(row=0, column=3, sticky=tk.W, padx=(12, 4))
    var_solver = tk.StringVar(value="chuffed")
    ttk.Combobox(
        marco_ctrl,
        textvariable=var_solver,
        values=["chuffed", "gecode"],
        width=10,
        state="readonly",
    ).grid(row=0, column=4, padx=4)

    ttk.Label(marco_ctrl, text="Estrategia:").grid(row=0, column=5, sticky=tk.W, padx=(12, 4))
    var_est = tk.StringVar(value="1 - Outside-In Peso Asc")
    opciones_est = [
        "1 - Outside-In Peso Asc",
        "2 - Outside-In Orden ID",
        "3 - Izquierda a Derecha",
        "4 - First-Fail + Min",
        "5 - First-Fail + Split",
        "6 - Pos Costo Desc + Mediana",
        "7 - Dom/WDeg Outside-In",
        "8 - Nativa del Solver",
    ]
    ttk.Combobox(
        marco_ctrl,
        textvariable=var_est,
        values=opciones_est,
        width=24,
        state="readonly",
    ).grid(row=0, column=6, padx=4)

    var_sim = tk.BooleanVar(value=True)
    var_red = tk.BooleanVar(value=True)
    ttk.Checkbutton(marco_ctrl, text="Simetrias (S1-S3)", variable=var_sim).grid(
        row=0, column=7, padx=6
    )
    ttk.Checkbutton(marco_ctrl, text="Redundantes (R1-R4)", variable=var_red).grid(
        row=0, column=8, padx=6
    )

    var_archivo_lbl = tk.StringVar(value="Ningun archivo seleccionado")
    ttk.Label(marco_ctrl, textvariable=var_archivo_lbl, foreground="#1f4e78").grid(
        row=1, column=0, columnspan=5, sticky=tk.W, padx=4, pady=(6, 0)
    )

    # --- Panel de indicadores de resumen ---
    marco_kpi = ttk.LabelFrame(raiz, text="Resumen de Optimalidad y Verificacion", padding=8)
    marco_kpi.pack(fill=tk.X, padx=10, pady=4)

    var_resumen = tk.StringVar(
        value="Seleccione una instancia .dzn y presione 'Resolver Modelo' para visualizar la planificacion."
    )
    ttk.Label(marco_kpi, textvariable=var_resumen, font=("Consolas", 10, "bold")).pack(
        anchor=tk.W
    )

    var_salida_norm = tk.StringVar(value="Salida normalizada (.txt): -")
    ttk.Label(marco_kpi, textvariable=var_salida_norm, font=("Consolas", 9)).pack(
        anchor=tk.W, pady=(3, 0)
    )

    # --- Pestanas principales ---
    notebook = ttk.Notebook(raiz)
    notebook.pack(fill=tk.BOTH, expand=True, padx=10, pady=(4, 10))

    # Pestana 1: Diagrama de Gantt
    tab_gantt = ttk.Frame(notebook)
    notebook.add(tab_gantt, text="Diagrama de Gantt y Solapes")

    canvas = tk.Canvas(tab_gantt, bg="#ffffff", highlightthickness=0)
    scroll_y = ttk.Scrollbar(tab_gantt, orient=tk.VERTICAL, command=canvas.yview)
    scroll_x = ttk.Scrollbar(tab_gantt, orient=tk.HORIZONTAL, command=canvas.xview)
    canvas.configure(yscrollcommand=scroll_y.set, xscrollcommand=scroll_x.set)
    scroll_y.pack(side=tk.RIGHT, fill=tk.Y)
    scroll_x.pack(side=tk.BOTTOM, fill=tk.X)
    canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

    # Pestana 2: Tabla de auditoria por actor
    tab_tabla = ttk.Frame(notebook)
    notebook.add(tab_tabla, text="Verificacion Detallada por Actor y Conflictos")

    cols = (
        "actor",
        "costo_u",
        "rango_pos",
        "rango_t",
        "dur_min",
        "espera",
        "tiempo_tot",
        "disp_max",
        "estado",
        "costo_tot",
    )
    tree = ttk.Treeview(tab_tabla, columns=cols, show="headings", height=12)
    encabezados = {
        "actor": "Actor",
        "costo_u": "Costo/u.t.",
        "rango_pos": "Posiciones [1a..Ult]",
        "rango_t": "Intervalo [Ini..Fin]",
        "dur_min": "Actuacion",
        "espera": "Espera",
        "tiempo_tot": "Total Set",
        "disp_max": "Disponibilidad",
        "estado": "Verificacion",
        "costo_tot": "Costo Salarial",
    }
    for c in cols:
        tree.heading(c, text=encabezados[c])
        tree.column(c, anchor=tk.CENTER, width=105)
    tree.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

    txt_evitar = tk.Text(tab_tabla, height=8, font=("Consolas", 9), bg="#f8f9fa")
    txt_evitar.pack(fill=tk.X, padx=6, pady=(0, 6))

    # Pestana 3: Entrada y salida normalizada
    tab_io = ttk.Frame(notebook)
    notebook.add(tab_io, text="Entrada (.dzn) y Salida Normalizada (.txt)")
    txt_io = tk.Text(tab_io, font=("Consolas", 10))
    txt_io.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

    def dibujar_gantt(res: Dict[str, Any]) -> None:
        canvas.delete("all")
        datos = res["datos"]
        ev = res["evaluacion"]
        d_tot = max(1, ev["duracion_total"])
        margen_izq = 175
        margen_top = 55
        ancho_ut = max(28, min(52, int(860 / d_tot)))
        alto_fila = 30
        sep_fila = 8

        # Leyenda superior
        canvas.create_rectangle(margen_izq, 12, margen_izq + 18, 26, fill="#2b6cb0", outline="#1a365d")
        canvas.create_text(margen_izq + 24, 19, text="Actua en escena", anchor=tk.W, font=("Segoe UI", 9))
        canvas.create_rectangle(margen_izq + 150, 12, margen_izq + 168, 26, fill="#f6ad55", outline="#c05621")
        canvas.create_text(margen_izq + 174, 19, text="Espera en estudio", anchor=tk.W, font=("Segoe UI", 9))
        canvas.create_rectangle(margen_izq + 315, 12, margen_izq + 333, 26, fill="#edf2f7", outline="#cbd5e0")
        canvas.create_text(margen_izq + 339, 19, text="Fuera del estudio", anchor=tk.W, font=("Segoe UI", 9))
        if datos["parte"] == 2:
            canvas.create_rectangle(margen_izq + 480, 12, margen_izq + 498, 26, fill="#e53e3e", outline="#9b2c2c")
            canvas.create_text(margen_izq + 504, 19, text="Solape conflictivo (Evitar)", anchor=tk.W, font=("Segoe UI", 9))

        # Encabezado de escenas en el orden de grabacion
        canvas.create_text(
            14,
            margen_top + 14,
            text="Orden de Escenas",
            anchor=tk.W,
            font=("Segoe UI", 9, "bold"),
        )
        for blq in ev["bloques_escena"]:
            x0 = margen_izq + blq["t_ini"] * ancho_ut
            x1 = margen_izq + blq["t_fin"] * ancho_ut
            canvas.create_rectangle(x0, margen_top, x1, margen_top + 28, fill="#e2e8f0", outline="#4a5568")
            canvas.create_text(
                (x0 + x1) / 2,
                margen_top + 14,
                text=f"E{blq['escena']} ({blq['duracion']})",
                font=("Segoe UI", 8, "bold"),
            )

        # Regla de unidades de tiempo
        y_regla = margen_top + 34
        for t in range(d_tot + 1):
            xt = margen_izq + t * ancho_ut
            canvas.create_line(xt, y_regla, xt, y_regla + 6, fill="#718096")
            canvas.create_text(xt, y_regla + 14, text=str(t), font=("Consolas", 8), fill="#4a5568")

        # Filas por actor
        y_base = y_regla + 28
        part = datos["participa"]
        for idx_a, info in enumerate(ev["detalle_actores"]):
            y0 = y_base + idx_a * (alto_fila + sep_fila)
            y1 = y0 + alto_fila
            etiqueta = f"{info['nombre']} (${info['costo_unit']}/u)"
            canvas.create_text(14, (y0 + y1) / 2, text=etiqueta, anchor=tk.W, font=("Segoe UI", 9, "bold"))

            for blq in ev["bloques_escena"]:
                k = blq["posicion"]
                esc = blq["escena"]
                x0 = margen_izq + blq["t_ini"] * ancho_ut
                x1 = margen_izq + blq["t_fin"] * ancho_ut
                actua = part[idx_a][esc - 1] == 1
                en_set = info["tiempo"] > 0 and (info["primera"] <= k <= info["ultima"])
                if actua:
                    color, borde, txt = "#2b6cb0", "#1a365d", "X"
                    color_txt = "#ffffff"
                elif en_set:
                    color, borde, txt = "#f6ad55", "#c05621", "esp"
                    color_txt = "#744210"
                else:
                    color, borde, txt = "#f7fafc", "#e2e8f0", ""
                    color_txt = "#a0aec0"

                canvas.create_rectangle(x0, y0, x1, y1, fill=color, outline=borde)
                if txt:
                    canvas.create_text((x0 + x1) / 2, (y0 + y1) / 2, text=txt, fill=color_txt, font=("Segoe UI", 8, "bold"))

            x_der = margen_izq + d_tot * ancho_ut + 14
            disp_str = f"/{info['disponibilidad']}" if info["disponibilidad"] > 0 else "/inf"
            estado_color = "#2f855a" if info["cumple_disp"] else "#c53030"
            resumen_actor = f"T={info['tiempo']}{disp_str} (Esp={info['espera']}) | Costo={info['costo_total']}"
            canvas.create_text(
                x_der,
                (y0 + y1) / 2,
                text=resumen_actor,
                anchor=tk.W,
                fill=estado_color,
                font=("Consolas", 9, "bold"),
            )

        y_cursor = y_base + len(ev["detalle_actores"]) * (alto_fila + sep_fila) + 14

        # Seccion de solapes de Evitar en Parte 2
        if datos["parte"] == 2 and ev["detalle_evitar"]:
            canvas.create_text(
                14,
                y_cursor,
                text="Solapes en Estudio - Restriccion Evitar:",
                anchor=tk.W,
                font=("Segoe UI", 9, "bold"),
            )
            y_cursor += 16
            for par in ev["detalle_evitar"]:
                y0 = y_cursor
                y1 = y0 + 22
                canvas.create_text(
                    14,
                    (y0 + y1) / 2,
                    text=f"{par['actor1']} vs {par['actor2']}",
                    anchor=tk.W,
                    font=("Segoe UI", 8),
                )
                canvas.create_rectangle(
                    margen_izq,
                    y0,
                    margen_izq + d_tot * ancho_ut,
                    y1,
                    fill="#f7fafc",
                    outline="#cbd5e0",
                )
                if par["solape"] > 0:
                    sx0 = margen_izq + par["t_ini"] * ancho_ut
                    sx1 = margen_izq + par["t_fin"] * ancho_ut
                    canvas.create_rectangle(sx0, y0, sx1, y1, fill="#e53e3e", outline="#9b2c2c")
                    canvas.create_text(
                        (sx0 + sx1) / 2,
                        (y0 + y1) / 2,
                        text=f"{par['solape']} u.t.",
                        fill="#ffffff",
                        font=("Segoe UI", 8, "bold"),
                    )
                canvas.create_text(
                    margen_izq + d_tot * ancho_ut + 14,
                    (y0 + y1) / 2,
                    text=f"Solape={par['solape']} u.t. (comunes={par['min_irreductible']} u.t.)",
                    anchor=tk.W,
                    font=("Consolas", 8),
                )
                y_cursor += 28

        ancho_total = margen_izq + d_tot * ancho_ut + 310
        canvas.configure(scrollregion=(0, 0, ancho_total, y_cursor + 25))

    def actualizar_vistas(res: Dict[str, Any]) -> None:
        datos = res["datos"]
        ev = res["evaluacion"]
        stats = res["stats"]
        nodos = stats.get("nodes", "-")
        fallos = stats.get("failures", "-")
        estado_opt = "OPTIMO CERTIFICADO" if res["optimo_probado"] else "MEJOR FACTIBLE (LIMITE TIEMPO)"
        tc_txt = f" | Tiempo Compartido (Evitar): {ev['tiempo_compartido']}" if datos["parte"] == 2 else ""
        var_resumen.set(
            f"[Parte {datos['parte']} - {estado_opt}] Costo Total: {ev['costo_total']} "
            f"(Base: {ev['costo_base']}, Espera: {ev['costo_total'] - ev['costo_base']})"
            f"{tc_txt} | Nodos: {nodos} | Fallos: {fallos} | Tiempo: {res['tiempo_wall']:.3f}s"
        )
        destino_txt = f" -> Guardado en {res['ruta_salida_txt'].relative_to(RAIZ_PROYECTO)}" if res["ruta_salida_txt"] else ""
        var_salida_norm.set(f"Salida normalizada: {ev['linea_normalizada']}{destino_txt}")

        dibujar_gantt(res)

        for item in tree.get_children():
            tree.delete(item)
        for info in ev["detalle_actores"]:
            disp_s = str(info["disponibilidad"]) if info["disponibilidad"] > 0 else "Ilimitada (0)"
            ver_s = "CUMPLE" if info["cumple_disp"] else "EXCEDE"
            tree.insert(
                "",
                tk.END,
                values=(
                    info["nombre"],
                    info["costo_unit"],
                    f"[{info['primera']}..{info['ultima']}]",
                    f"[{info['t_ini']}..{info['t_fin']}]",
                    info["dur_min"],
                    info["espera"],
                    info["tiempo"],
                    disp_s,
                    ver_s,
                    info["costo_total"],
                ),
            )

        txt_evitar.delete("1.0", tk.END)
        if datos["parte"] == 2:
            txt_evitar.insert(tk.END, "VERIFICACION DE PARES CONFLICTIVOS (EVITAR):\n")
            if ev["detalle_evitar"]:
                for p in ev["detalle_evitar"]:
                    txt_evitar.insert(
                        tk.END,
                        f"  - ({p['actor1']}, {p['actor2']}): solape en estudio = {p['solape']} u.t. "
                        f"en [{p['t_ini']}..{p['t_fin']}], escenas compartidas obligatorias = {p['min_irreductible']} u.t.\n",
                    )
            else:
                txt_evitar.insert(tk.END, "  Sin pares registrados en Evitar.\n")
        else:
            txt_evitar.insert(tk.END, "Instancia de Parte 1 (sin restricciones Disponibilidad ni Evitar).\n")

        txt_io.delete("1.0", tk.END)
        txt_io.insert(tk.END, "=== SALIDA NORMALIZADA DE UNA LINEA ===\n")
        txt_io.insert(tk.END, ev["linea_normalizada"] + "\n\n")
        txt_io.insert(tk.END, f"=== ENTRADA ORIGINAL ({datos['ruta'].name}) ===\n")
        txt_io.insert(tk.END, datos["texto_crudo"])

    def accion_resolver() -> None:
        ruta = estado_actual["ruta_dzn"]
        if ruta is None:
            messagebox.showwarning("Archivo requerido", "Seleccione primero un archivo .dzn.")
            return
        try:
            est_id = int(var_est.get().split("-")[0].strip())
            datos_tmp = parsear_archivo_dzn(ruta)
            sub_sal = f"parte{datos_tmp['parte']}"
            ruta_sal = RAIZ_PROYECTO / "salidas" / sub_sal / f"{ruta.stem}.txt"
            raiz.config(cursor="watch")
            raiz.update_idletasks()
            res = ejecutar_minizinc(
                ruta_dzn=ruta,
                solver=var_solver.get(),
                estrategia=est_id,
                usar_simetrias=var_sim.get(),
                usar_redundantes=var_red.get(),
                timeout_ms=30000,
                ruta_salida_txt=ruta_sal,
            )
            estado_actual["resultado"] = res
            actualizar_vistas(res)
        except Exception as exc:
            messagebox.showerror("Error en ejecucion", str(exc))
        finally:
            raiz.config(cursor="")

    def accion_exportar_txt() -> None:
        res = estado_actual["resultado"]
        if res is None:
            messagebox.showinfo("Sin resultado", "Resuelva primero una instancia antes de exportar.")
            return
        ruta_dest = filedialog.asksaveasfilename(
            title="Guardar salida normalizada (.txt)",
            initialdir=str(RAIZ_PROYECTO / "salidas"),
            initialfile=f"{res['datos']['ruta'].stem}.txt",
            defaultextension=".txt",
            filetypes=[("Archivo de texto", "*.txt")],
        )
        if ruta_dest:
            Path(ruta_dest).write_text(res["evaluacion"]["linea_normalizada"] + "\n", encoding="utf-8")
            messagebox.showinfo("Exportacion exitosa", f"Salida guardada en:\n{ruta_dest}")

    ttk.Button(marco_ctrl, text="Resolver Modelo", command=accion_resolver).grid(
        row=1, column=6, padx=4, pady=(6, 0), sticky=tk.EW
    )
    ttk.Button(marco_ctrl, text="Guardar .txt...", command=accion_exportar_txt).grid(
        row=1, column=7, columnspan=2, padx=4, pady=(6, 0), sticky=tk.EW
    )

    # Seleccion inicial por defecto
    if ruta_inicial and ruta_inicial.exists():
        estado_actual["ruta_dzn"] = ruta_inicial
        var_archivo_lbl.set(str(ruta_inicial))
    elif instancias:
        primera_clave = list(mapa_instancias.keys())[0]
        combo_inst.set(primera_clave)
        al_seleccionar_combo()

    raiz.mainloop()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Interfaz grafica y CLI normalizada para Planificacion de Ensayos en Telenovela."
    )
    parser.add_argument("--entrada", type=str, help="Ruta de un archivo .dzn a resolver en modo CLI.")
    parser.add_argument("--salida", type=str, help="Ruta del archivo .txt de salida normalizada.")
    parser.add_argument("--lote", action="store_true", help="Resuelve todas las instancias de datos/ y genera salidas/.")
    parser.add_argument("--solver", type=str, default="chuffed", choices=["chuffed", "gecode"])
    parser.add_argument("--estrategia", type=int, default=1, choices=range(1, 9))
    parser.add_argument("--sin-simetrias", action="store_true")
    parser.add_argument("--sin-redundantes", action="store_true")
    parser.add_argument("--timeout-ms", type=int, default=30000)
    args = parser.parse_args()

    if args.lote:
        for ruta in descubrir_instancias_proyecto():
            datos = parsear_archivo_dzn(ruta)
            destino = RAIZ_PROYECTO / "salidas" / f"parte{datos['parte']}" / f"{ruta.stem}.txt"
            res = ejecutar_minizinc(
                ruta_dzn=ruta,
                solver=args.solver,
                estrategia=args.estrategia,
                usar_simetrias=not args.sin_simetrias,
                usar_redundantes=not args.sin_redundantes,
                timeout_ms=args.timeout_ms,
                ruta_salida_txt=destino,
            )
            ev = res["evaluacion"]
            marca = "OPT" if res["optimo_probado"] else "SUB"
            print(f"[P{datos['parte']}|{marca}] {ruta.name:18s} -> {ev['linea_normalizada']} ({res['tiempo_wall']:.2f}s)")
        return 0

    if args.entrada:
        ruta_in = Path(args.entrada)
        datos = parsear_archivo_dzn(ruta_in)
        ruta_out = (
            Path(args.salida)
            if args.salida
            else (RAIZ_PROYECTO / "salidas" / f"parte{datos['parte']}" / f"{ruta_in.stem}.txt")
        )
        res = ejecutar_minizinc(
            ruta_dzn=ruta_in,
            solver=args.solver,
            estrategia=args.estrategia,
            usar_simetrias=not args.sin_simetrias,
            usar_redundantes=not args.sin_redundantes,
            timeout_ms=args.timeout_ms,
            ruta_salida_txt=ruta_out,
        )
        print(res["evaluacion"]["linea_normalizada"])
        return 0

    lanzar_interfaz_grafica()
    return 0


if __name__ == "__main__":
    sys.exit(main())
