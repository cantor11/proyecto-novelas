# Guía de Compilación de LaTeX

Estructura del informe en `Informe/` y comandos para compilar `Informe/main.pdf`.

## 1. Organización de `Informe/`

```text
Informe/
├── main.tex                                      # Portada, índice e inclusión de secciones
├── main.pdf                                      # Documento compilado
├── Imagenes/
│   ├── logoUV.jpg                                # Escudo Universidad del Valle
│   ├── parte1/                                   # Gráficas de Parte 1
│   └── parte2/                                   # Gráficas de Parte 2
└── secciones/
    ├── 01_modelo_parte1.tex                      # Modelo COP Parte 1
    ├── 02_modelo_parte2.tex                      # Extensión COP Parte 2 y objetivo lexicográfico
    ├── 03_implementacion_simetrias_redundantes.tex # Fundamentos, simetrías S1-S3 y redundantes R1-R4
    ├── 04_estrategias_busqueda.tex               # Estrategias de búsqueda E1-E8
    ├── 05_pruebas_y_analisis.tex                 # Batería de 13 instancias, tablas y gráficas
    └── 06_conclusiones.tex                       # Conclusiones
```

## 2. Compilación

### 2.1. Con Tectonic desde terminal
```powershell
cd Informe
& "C:\Users\Jr Cantor\AppData\Local\Programs\Tectonic\tectonic.exe" -o . main.tex
```

### 2.2. Con LaTeX Workshop en VS Code
1. Abrir `Informe/main.tex` o cualquier archivo en `Informe/secciones/`.
2. Guardar (`Ctrl + S`) o ejecutar `Ctrl + Alt + B`.
3. Abrir la vista previa con `Ctrl + Alt + V`.
