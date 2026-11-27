PROYECTO DE CURSO - PROGRAMACION POR RESTRICCIONES
Planificacion de los ensayos en una telenovela (Parte 1 y Parte 2)
Universidad del Valle - Escuela de Ingenieria de Sistemas y Computacion

Integrantes:
  - Cristian David Cabrera Pantoja
  - Junior Orlando Cantor Arevalo
  - Juan Diego Cardenas Mejia

Profesor:
  - Robinson Duque

1. CONTENIDO DE LA CARPETA

  problemas/
    parte1/TelenovelaParte1.mzn   Modelo COP en MiniZinc para Parte 1: minimizacion
                                  del costo salarial por tiempo en estudio con
                                  inverse(Orden, Pos), simetrias (S1-S3),
                                  redundantes (R1-R4) y busqueda Outside-In (E1).
    parte2/TelenovelaParte2.mzn   Modelo COP para Parte 2: agrega Disponibilidad
                                  por actor, solape de pares en Evitar y funcion
                                  objetivo lexicografica (Costo sobre solape).

  datos/
    parte1/
      Trivial1.dzn                Instancia base oficial Parte 1 (N=3, M=6).
      Instancia01_P1.dzn          Escenas vacias y gemelas (N=5, M=8).
      Instancia02_P1.dzn          Actor de alto costo unitario (N=6, M=10).
      Instancia03_P1.dzn          Duraciones heterogeneas (N=7, M=12).
      Instancia04_P1.dzn          Escala intermedia-alta (N=8, M=15).
      Desenfreno2.dzn             Desenfreno de Pasiones Parte 1 (N=8, M=20).
      Desenfreno3.dzn             Copia oficial de verificacion E/S (N=8, M=20).
    parte2/
      Trivial2.dzn                Instancia base oficial Parte 2 (N=4, M=6).
      Instancia01_P2.dzn          Desempate lexicografico (N=5, M=8).
      Instancia02_P2.dzn          Disponibilidad con holgura cero (N=6, M=10).
      Instancia03_P2.dzn          Sobrecosto por disponibilidad (N=7, M=12).
      Instancia04_P2.dzn          Cinco conflictos en Evitar (N=8, M=15).
      Desenfreno4.dzn             Desenfreno de Pasiones Parte 2 (N=8, M=20).

  salidas/
    parte1/*.txt                  Salidas normalizadas de una linea (orden + costo).
    parte2/*.txt                  Salidas normalizadas de una linea (orden + costo + solape).

  interfaz/
    app_telenovela.py             Interfaz grafica (Tkinter) y CLI: lee *.dzn,
                                  ejecuta MiniZinc, verifica restricciones, dibuja
                                  diagrama de Gantt y exporta *.txt.

  pruebas/
    test_telenovela.py            Pruebas automatizadas (unittest) con oraculo DP y
                                  Branch-and-Bound, equivalencia Gecode/Chuffed,
                                  ablacion y validacion de E/S.

  Informe/
    main.pdf                      Informe compilado en PDF (sin bloques de codigo).
    main.tex                      Documento raiz LaTeX.
    secciones/                    Archivos modulares .tex (01 a 06).
    Imagenes/                     Logo en la raiz y graficas en parte1/ y parte2/.

  ProyectoPPR.pdf                 Enunciado del proyecto.
  readme.txt                      Descripcion de archivos e instrucciones de uso.
  README.md                       Resumen del repositorio.
  GUIA_LATEX.md                   Instrucciones de compilacion LaTeX.

2. INSTRUCCIONES DE EJECUCION

A) MiniZinc CLI (MiniZinc 2.9+, desde la raiz del proyecto):

   - Parte 1:
     minizinc --solver gecode  problemas/parte1/TelenovelaParte1.mzn datos/parte1/Trivial1.dzn
     minizinc --solver chuffed --statistics problemas/parte1/TelenovelaParte1.mzn datos/parte1/Desenfreno2.dzn

   - Parte 2:
     minizinc --solver gecode  problemas/parte2/TelenovelaParte2.mzn datos/parte2/Trivial2.dzn
     minizinc --solver chuffed --statistics problemas/parte2/TelenovelaParte2.mzn datos/parte2/Desenfreno4.dzn

B) MiniZinc IDE:

   1. Abrir problemas/parte1/TelenovelaParte1.mzn (o TelenovelaParte2.mzn).
   2. Seleccionar un archivo .dzn de datos/parte1/ (o datos/parte2/).
   3. Elegir el solver "Chuffed" o "Gecode" y ejecutar (Ctrl+R).

C) Interfaz grafica y CLI (Python 3):

   - Interfaz grafica (Tkinter):
     python interfaz/app_telenovela.py

   - Resolver un .dzn y exportar su salida normalizada (.txt):
     python interfaz/app_telenovela.py --entrada datos/parte1/Desenfreno2.dzn --salida salidas/parte1/Desenfreno2.txt
     python interfaz/app_telenovela.py --entrada datos/parte2/Desenfreno4.dzn --salida salidas/parte2/Desenfreno4.txt

   - Ejecutar variantes de ablacion o estrategias (1..8):
     python interfaz/app_telenovela.py --entrada datos/parte1/Instancia01_P1.dzn --solver gecode --sin-simetrias
     python interfaz/app_telenovela.py --entrada datos/parte2/Instancia02_P2.dzn --solver gecode --sin-redundantes
     python interfaz/app_telenovela.py --entrada datos/parte2/Desenfreno4.dzn --solver chuffed --estrategia 1

   - Regenerar todas las salidas normalizadas:
     python interfaz/app_telenovela.py --lote

D) Pruebas automatizadas:

     python pruebas/test_telenovela.py
