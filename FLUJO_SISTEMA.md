# FLUJO COMPLETO DEL SISTEMA - Image Downscaling

## Arquitectura General del Proyecto

Este proyecto implementa un sistema de reducción de imágenes (downscaling) con interpolación bilineal en FPGA, con dos modos de operación:

1. **Modo Secuencial**: Procesa píxel por píxel
2. **Modo SIMD**: Procesa N píxeles en paralelo

## Jerarquía de Módulos

```
Top_General
├── JTAG_Interface (Interfaz Avalon-MM)
├── Top_Downscale_Secuencial
│   ├── ImageMemory (BRAM)
│   └── Downscale_Secuencial
│       └── ModoSecuencial (Interpolador bilineal)
└── Top_Downscale_SIMD
    ├── ImageMemory_SIMDPort (BRAM con cache)
    └── Downscale_SIMD
        └── Top_SIMD
            ├── FSM_SIMD
            ├── SIMD_Registros
            └── ModoSIMD
                └── N × ModoSecuencial
```

---

## 1. TOP_GENERAL - Módulo Raíz

### Puertos Externos
```systemverilog
input  logic clk, rst
input  logic avs_read, avs_write       // Señales Avalon-MM
input  logic [7:0] avs_address         // Dirección de registro
input  logic [31:0] avs_writedata      // Dato a escribir
output logic [31:0] avs_readdata       // Dato leído
```

### Mapa de Registros JTAG
| Dirección | Nombre          | R/W | Descripción                                    |
|-----------|-----------------|-----|------------------------------------------------|
| 0x00      | Control         | W   | bit[0]=start, bit[1]=step, bit[2]=mode        |
| 0x01      | param_x_ratio   | W   | Ratio de escalado X (no usado en versión fija)|
| 0x02      | param_y_ratio   | W   | Ratio de escalado Y (no usado en versión fija)|
| 0x03      | img_write_addr  | W   | Dirección de píxel a escribir                 |
| 0x04      | img_write_data  | W   | Dato del píxel (8 bits)                       |
| 0x05      | img_read_data   | R   | Dato de debug (dbg_data del módulo activo)    |
| 0x06      | status          | R   | bit[0]=done_flag                              |
| 0x07      | perf_counter    | R   | Contador de ciclos desde start                |

### Señal de Escritura a Memoria
```systemverilog
img_we = avs_write && (avs_address == 8'h04)
```
Solo cuando se escribe al registro 0x04 se activa la escritura a BRAM.

### Multiplexación por Modo

**mode_reg = 0 (Secuencial):**
```systemverilog
Top_Downscale_Secuencial recibe:
  - cfg_we   = img_we && !mode_reg
  - start_req = start && !mode_reg
  - cfg_addr, cfg_data
Salidas:
  - done_seq → done_flag
  - dbg_seq → rd_data_reg
```

**mode_reg = 1 (SIMD):**
```systemverilog
Top_Downscale_SIMD recibe:
  - cfg_we   = img_we && mode_reg
  - start_req = start && mode_reg
  - cfg_addr, cfg_data
Salidas:
  - done_simd → done_flag
  - dbg_simd → rd_data_reg
```

### Contador de Performance
- Se resetea cuando `rst || start`
- Incrementa cada ciclo de reloj
- Permite medir ciclos totales de procesamiento

---

## 2. FLUJO MODO SECUENCIAL

### Top_Downscale_Secuencial

#### Estados de la FSM
```
S_IDLE → S_LOAD_IMAGE → S_START_DOWNSCALE → S_WAIT_DOWNSCALE → S_DONE → S_IDLE
```

#### Flujo Detallado

**ESTADO: S_IDLE**
- Espera `start_req = 1`
- Inicializa `load_addr = 0`
- `done = 0`, `downscale_start = 0`
- Transición: Si `start_req` → `S_LOAD_IMAGE`

**ESTADO: S_LOAD_IMAGE**
- **Objetivo**: Cargar toda la imagen desde BRAM a `image_in[SRC_H][SRC_W]`
- **Protocolo de lectura sincrónica**:
  ```
  Ciclo N:   bram_addr = N
  Ciclo N+1: bram_rd_data contiene dato de dirección N
             Almacenar en image_in[row][col] donde:
               row = N / SRC_W
               col = N % SRC_W
  ```
- **Manejo de escritura JTAG simultánea**:
  ```systemverilog
  bram_addr = cfg_we ? cfg_addr : load_addr
  ```
  Si `cfg_we=1`, usa `cfg_addr` (escritura JTAG tiene prioridad)
  Si `cfg_we=0`, usa `load_addr` (lectura para cargar imagen)

- **Lógica de carga**:
  1. Primer ciclo: `load_addr = 0`, no almacena (no hay dato aún)
  2. Ciclos 1 a DEPTH-1: Almacena dato del ciclo anterior, incrementa `load_addr`
  3. Ciclo DEPTH: Almacena último dato
  4. Ciclo DEPTH+1: Transición a `S_START_DOWNSCALE`

- **Total de ciclos**: DEPTH + 2 ciclos

**ESTADO: S_START_DOWNSCALE**
- Activa `downscale_start = 1` (pulso de 1 ciclo)
- Transición inmediata a `S_WAIT_DOWNSCALE`

**ESTADO: S_WAIT_DOWNSCALE**
- Baja `downscale_start = 0`
- Espera `downscale_done = 1` del módulo `Downscale_Secuencial`
- Cuando `downscale_done = 1`:
  - Activa `done = 1`
  - Transición a `S_DONE`

**ESTADO: S_DONE**
- Mantiene `done = 1`
- Espera que `start_req = 0` (usuario baja la señal)
- Cuando `start_req = 0` → vuelve a `S_IDLE`

### Downscale_Secuencial

#### Estados de la FSM
```
S_IDLE → S_SETUP → S_WAIT_RESULT → S_SETUP (bucle) → S_DONE → S_IDLE
```

#### Flujo por Píxel

**ESTADO: S_IDLE**
- Espera `start = 1`
- Inicializa `i_dst = 0`, `j_dst = 0`
- Transición: Si `start` → `S_SETUP`

**ESTADO: S_SETUP**
- **Calcula coordenadas fuente** (Q8.8 punto fijo):
  ```systemverilog
  xr = (SRC_W-1) / (DST_W-1)  // Ratio de escalado
  yr = (SRC_H-1) / (DST_H-1)

  x_src_fp = j_dst * xr  // Posición X en fuente (Q8.8)
  y_src_fp = i_dst * yr  // Posición Y en fuente (Q8.8)

  x_l = floor(x_src_fp)  // Parte entera
  y_l = floor(y_src_fp)
  x_h = ceil(x_src_fp)   // x_l + 1 (saturado en borde)
  y_h = ceil(y_src_fp)
  ```

- **Obtiene 4 píxeles vecinos**:
  ```systemverilog
  I00 = image_in[y_l][x_l]  // Superior izquierdo
  I10 = image_in[y_l][x_h]  // Superior derecho
  I01 = image_in[y_h][x_l]  // Inferior izquierdo
  I11 = image_in[y_h][x_h]  // Inferior derecho
  ```

- **Calcula pesos fraccionales** (Q0.8):
  ```systemverilog
  alpha = x_src_fp[7:0]  // Parte fraccional de X
  beta  = y_src_fp[7:0]  // Parte fraccional de Y
  ```

- Activa `valid_in = 1` para `ModoSecuencial`
- Transición: `S_WAIT_RESULT`

**ESTADO: S_WAIT_RESULT**
- Baja `valid_in = 0`
- Espera `valid_out = 1` del interpolador
- Cuando `valid_out = 1`:
  ```systemverilog
  image_out[i_dst][j_dst] = pixel_out
  ```

- **Avanza al siguiente píxel**:
  ```systemverilog
  if (j_dst == DST_W-1):
    j_dst = 0
    i_dst = i_dst + 1
  else:
    j_dst = j_dst + 1
  ```

- **Condición de término**:
  ```systemverilog
  if (i_dst == DST_H-1 && j_dst == DST_W-1):
    done = 1
    Estado → S_DONE
  else:
    Estado → S_SETUP  // Procesar siguiente píxel
  ```

**ESTADO: S_DONE**
- Mantiene `done = 1`
- Espera `start = 0`
- Transición: Cuando `start = 0` → `S_IDLE`

### ModoSecuencial (Interpolador Bilineal)

#### Pipeline de 5 Etapas

**ETAPA 1: Extensión a Q8.8**
```systemverilog
I00_q = {I00, 8'h00}  // 8 bits → 16 bits Q8.8
I10_q = {I10, 8'h00}
I01_q = {I01, 8'h00}
I11_q = {I11, 8'h00}
alpha_q = {8'h00, alpha}  // Q0.8 → Q8.8
beta_q  = {8'h00, beta}
```

**ETAPA 2: Interpolación Horizontal**
```systemverilog
// Calcular a = I00 + alpha * (I10 - I00)
diff_x0 = I10_q - I00_q  // Puede ser negativo
if (diff_x0 < 0):
  a_q = I00_q - ((-diff_x0) * alpha_q)[23:8]
else:
  a_q = I00_q + (diff_x0 * alpha_q)[23:8]

// Calcular b = I01 + alpha * (I11 - I01)
diff_x1 = I11_q - I01_q
if (diff_x1 < 0):
  b_q = I01_q - ((-diff_x1) * alpha_q)[23:8]
else:
  b_q = I01_q + (diff_x1 * alpha_q)[23:8]
```

**ETAPA 3: Interpolación Vertical**
```systemverilog
// Calcular v = a + beta * (b - a)
diff_y = b_q - a_q
if (diff_y < 0):
  v_q = a_q - ((-diff_y) * beta_q)[23:8]
else:
  v_q = a_q + (diff_y * beta_q)[23:8]
```

**ETAPA 4: Redondeo y Saturación**
```systemverilog
v_rounded = v_q + 0x0080  // Sumar 0.5 en Q8.8
pixel_int = v_rounded[16:8]  // Extraer parte entera

if (pixel_int > 255):
  pixel_clamped = 255
else:
  pixel_clamped = pixel_int[7:0]
```

**ETAPA 5: Registro de Salida**
```systemverilog
valid_out <= valid_in  // Retardo de 1 ciclo
pixel_out <= pixel_clamped
```

**Latencia Total**: 1 ciclo (todo es lógica combinacional excepto el registro de salida)

---

## 3. FLUJO MODO SIMD

### Top_Downscale_SIMD

#### Estados de la FSM
```
S_IDLE → S_LOAD_IMAGE → S_WAIT_LOAD (bucle) → S_START_DOWNSCALE →
S_WAIT_DOWNSCALE → S_WRITE_RESULTS → S_DONE → S_IDLE
```

#### Flujo Detallado

**ESTADO: S_IDLE**
- Espera `start_req = 1`
- Inicializa todos los contadores
- Limpia `mem_rd_req[N]`
- Transición: Si `start_req` → `S_LOAD_IMAGE`

**ESTADO: S_LOAD_IMAGE**
- **Objetivo**: Solicitar lectura de N píxeles en paralelo
- **Lógica**:
  ```systemverilog
  for (k = 0; k < N; k++):
    if (load_addr + k < SRC_DEPTH):
      mem_rd_req[k]  = 1
      mem_rd_addr[k] = load_addr + k
    else:
      mem_rd_req[k] = 0
  ```
- Transición inmediata: `S_WAIT_LOAD`

**ESTADO: S_WAIT_LOAD**
- Baja todos los `mem_rd_req[k] = 0`
- **Verifica si todos los datos válidos llegaron**:
  ```systemverilog
  all_ready = 1
  for (k = 0; k < N; k++):
    if ((load_addr + k < SRC_DEPTH) && !mem_rd_valid[k]):
      all_ready = 0
  ```

- **Cuando `all_ready = 1`**:
  ```systemverilog
  for (k = 0; k < N; k++):
    if (load_addr + k < SRC_DEPTH):
      row = (load_addr + k) / SRC_W
      col = (load_addr + k) % SRC_W
      image_in[row][col] = mem_rd_data[k]

  load_addr = load_addr + N

  if (load_addr >= SRC_DEPTH):
    Estado → S_START_DOWNSCALE
  else:
    Estado → S_LOAD_IMAGE  // Cargar siguiente bloque
  ```

**ESTADO: S_START_DOWNSCALE**
- Activa `downscale_start = 1`
- Transición: `S_WAIT_DOWNSCALE`

**ESTADO: S_WAIT_DOWNSCALE**
- Baja `downscale_start = 0`
- Espera `downscale_done = 1`
- Cuando `downscale_done = 1` → `S_WRITE_RESULTS`

**ESTADO: S_WRITE_RESULTS**
- Nota: En versión actual NO escribe resultados a BRAM
- Simplemente activa `done = 1`
- Transición: `S_DONE`

**ESTADO: S_DONE**
- Mantiene `done = 1`
- Espera `start_req = 0`
- Transición: Cuando `start_req = 0` → `S_IDLE`

### ImageMemory_SIMDPort (Memoria con Cache)

#### Arquitectura
- **1 BRAM compartida** (1 puerto de lectura)
- **N cachés independientes** (1 por lane SIMD)
- **Árbitro Round-Robin** para acceso a BRAM

#### Estructura de Cache
```systemverilog
cache_line_t {
  valid: 1 bit
  tag: TAG_BITS bits
  data[LINE_SIZE]: 8 bits × LINE_SIZE
}
```

Donde:
- `LINE_SIZE = 8` píxeles por línea
- `TAG_BITS = ADDR_BITS - log2(LINE_SIZE)`
- `OFFSET_BITS = log2(LINE_SIZE)`

#### Estados por Lane
```
IDLE → (HIT? output inmediato : WAIT_ARB) → FETCH → OUTPUT → IDLE
```

**ESTADO: IDLE**
- Espera `rd_req[i] = 1`
- Decodifica dirección:
  ```systemverilog
  tag    = rd_addr[ADDR_BITS-1:OFFSET_BITS]
  offset = rd_addr[OFFSET_BITS-1:0]
  ```
- **Cache HIT**:
  ```systemverilog
  if (cache[i].valid && cache[i].tag == tag):
    rd_data[i] = cache[i].data[offset]
    rd_valid[i] = 1
    Estado permanece en IDLE
  ```
- **Cache MISS**:
  ```systemverilog
  line_addr_base[i] = {tag, {OFFSET_BITS{1'b0}}}
  fetch_idx[i] = 0
  Estado → WAIT_ARB
  ```

**ESTADO: WAIT_ARB**
- Espera turno en árbitro Round-Robin
- Cuando este lane gana:
  ```systemverilog
  active_lane = i
  mem_busy = 1
  Estado → FETCH
  ```

**ESTADO: FETCH**
- **Carga línea completa** (LINE_SIZE píxeles):
  ```
  Ciclo 0: mem_addr = line_addr_base
  Ciclo 1: cache.data[0] = mem_rdata
           mem_addr = line_addr_base + 1
  Ciclo 2: cache.data[1] = mem_rdata
           mem_addr = line_addr_base + 2
  ...
  Ciclo LINE_SIZE: cache.data[LINE_SIZE-1] = mem_rdata
                   cache.valid = 1
                   cache.tag = req_tag
                   mem_busy = 0
                   arb_ptr = i  (avanzar RR)
                   Estado → OUTPUT
  ```
- **Total**: LINE_SIZE + 1 ciclos

**ESTADO: OUTPUT**
- Entrega dato solicitado:
  ```systemverilog
  rd_data[i] = cache[i].data[req_offset]
  rd_valid[i] = 1
  Estado → IDLE
  ```

#### Árbitro Round-Robin
```systemverilog
// Identifica lanes esperando
lane_needs_mem[i] = (state[i] == WAIT_ARB)

// Selecciona siguiente lane
for offset = 1 to N:
  idx = (arb_ptr + offset) % N
  if lane_needs_mem[idx]:
    next_lane = idx
    break
```

### Downscale_SIMD

#### Estados de la FSM
```
S_IDLE → S_PREP_BATCH → S_START_TOP → S_WAIT_TOP → S_WRITE_BATCH (bucle) → S_DONE → S_IDLE
```

#### Flujo por Batch

**ESTADO: S_IDLE**
- Espera `start = 1`
- Inicializa `base_idx = 0`
- Transición: `S_PREP_BATCH`

**ESTADO: S_PREP_BATCH**
- **Calcula índices de píxeles** (lógica combinacional):
  ```systemverilog
  for (k = 0; k < N; k++):
    idx[k] = base_idx + k
    valid_lane[k] = (idx[k] < TOT_PIX)

    if valid_lane[k]:
      i_dst[k] = idx[k] / DST_W
      j_dst[k] = idx[k] % DST_W
  ```

- **Calcula coordenadas fuente** (Q8.8):
  ```systemverilog
  for (k = 0; k < N; k++):
    if valid_lane[k]:
      x_src_fp[k] = j_dst[k] * X_RATIO_FP
      y_src_fp[k] = i_dst[k] * Y_RATIO_FP

      x_l[k] = x_src_fp[k][15:8]
      y_l[k] = y_src_fp[k][15:8]
      x_h[k] = (x_l[k] < SRC_W-1) ? x_l[k]+1 : x_l[k]
      y_h[k] = (y_l[k] < SRC_H-1) ? y_l[k]+1 : y_l[k]
  ```

- **Obtiene píxeles vecinos**:
  ```systemverilog
  for (k = 0; k < N; k++):
    if valid_lane[k]:
      I00_vec[k] = image_in[y_l[k]][x_l[k]]
      I10_vec[k] = image_in[y_l[k]][x_h[k]]
      I01_vec[k] = image_in[y_h[k]][x_l[k]]
      I11_vec[k] = image_in[y_h[k]][x_h[k]]
      alpha_vec[k] = x_src_fp[k][7:0]
      beta_vec[k]  = y_src_fp[k][7:0]
    else:
      // Lane inactivo: poner ceros
      I00_vec[k] = 0, I10_vec[k] = 0, ...
  ```

- Transición: `S_START_TOP`

**ESTADO: S_START_TOP**
- Activa `top_start = 1`
- Transición: `S_WAIT_TOP`

**ESTADO: S_WAIT_TOP**
- Baja `top_start = 0`
- Espera `top_done = 1`
- Cuando `top_done = 1` → `S_WRITE_BATCH`

**ESTADO: S_WRITE_BATCH**
- **Almacena resultados**:
  ```systemverilog
  for (k = 0; k < N; k++):
    if valid_lane[k]:
      image_out[i_dst[k]][j_dst[k]] = pixel_out_vec[k]
  ```

- **Avanza al siguiente batch**:
  ```systemverilog
  if (base_idx + N >= TOT_PIX):
    done = 1
    Estado → S_DONE
  else:
    base_idx = base_idx + N
    Estado → S_PREP_BATCH
  ```

**ESTADO: S_DONE**
- Mantiene `done = 1`
- Espera `start = 0`
- Transición: `S_IDLE`

### Top_SIMD (Control de Batch SIMD)

#### Estados de la FSM
```
S_IDLE → S_LOAD → S_RUN → S_WAIT → S_WRITE → S_IDLE
```

**ESTADO: S_IDLE**
- Espera `start = 1`
- Transición: `S_LOAD`

**ESTADO: S_LOAD**
- Activa `load_regs = 1` (1 ciclo)
- Los registros SIMD capturan:
  - `I00_vec[N]`, `I10_vec[N]`, `I01_vec[N]`, `I11_vec[N]`
  - `alpha_vec[N]`, `beta_vec[N]`
- Transición: `S_RUN`

**ESTADO: S_RUN**
- Activa `run_simd = 1` (1 ciclo)
- Dispara los N interpoladores en paralelo
- Transición: `S_WAIT`

**ESTADO: S_WAIT**
- Espera `simd_valid = 1` (de ModoSIMD)
- Cuando `simd_valid = 1` → `S_WRITE`

**ESTADO: S_WRITE**
- Activa `write_back = 1` (1 ciclo)
- Activa `done = 1` (pulso de 1 ciclo)
- Los `pixel_out_vec[N]` están listos
- Transición: `S_IDLE`

**Latencia Total por Batch**: ~4-5 ciclos

### ModoSIMD

- **Simplemente instancia N copias de `ModoSecuencial`**
- Cada core procesa 1 píxel independientemente
- `valid_out = valid_int[0]` (se asume que todos terminan juntos)

---

## 4. COMPARACIÓN DE RENDIMIENTO

### Modo Secuencial
Para imagen 32×32 → 16×16 (256 píxeles de salida):

```
Cargar imagen:     1024 + 2 = 1026 ciclos
Procesar píxeles:  256 × 2 = 512 ciclos  (2 ciclos por píxel: SETUP + WAIT)
TOTAL:             ~1538 ciclos
```

### Modo SIMD (N=4)
Para imagen 32×32 → 16×16 (256 píxeles de salida):

```
Cargar imagen:     ~1024/4 + overhead de cache ≈ 300-400 ciclos
Procesar píxeles:  256/4 × 5 = 320 ciclos  (5 ciclos por batch de 4)
TOTAL:             ~620-720 ciclos
```

**Speedup teórico**: ~2-2.5× para N=4

---

## 5. FORMATO DE PUNTO FIJO Q8.8

### Representación
```
[15:8] = Parte entera (8 bits)
[7:0]  = Parte fraccional (8 bits)
```

### Ejemplos
```
0x0000 = 0.00
0x0080 = 0.50  (128/256)
0x0100 = 1.00
0x0180 = 1.50
0xFFFF = 255.996
```

### Operaciones
```systemverilog
// Multiplicación: Q8.8 × Q8.8 = Q16.16
mult_result = a_q8_8 * b_q8_8  // 32 bits
result_q8_8 = mult_result[23:8]  // Extraer Q8.8

// División: Entero / Entero → Q8.8
ratio_q8_8 = (numerador << 8) / denominador
```

---

## 6. EJEMPLO COMPLETO: Uso desde PC/FPGA

### Configuración Inicial
```c
// 1. Seleccionar modo
write_reg(0x00, 0x04);  // mode = 1 (SIMD)

// 2. Cargar imagen 32×32
for (int i = 0; i < 32; i++) {
  for (int j = 0; j < 32; j++) {
    write_reg(0x03, i*32 + j);           // Dirección
    write_reg(0x04, imagen[i][j]);       // Dato
  }
}

// 3. Iniciar procesamiento
write_reg(0x00, 0x05);  // start=1, mode=1

// 4. Esperar hasta que termine
while (!(read_reg(0x06) & 0x01)) {
  // Esperar done_flag
}

// 5. Leer contador de performance
uint32_t ciclos = read_reg(0x07);
printf("Procesamiento completado en %d ciclos\n", ciclos);

// 6. Leer dato de debug
uint8_t dbg = read_reg(0x05) & 0xFF;
printf("Debug: %d\n", dbg);
```

---

## 7. NOTAS IMPORTANTES

### Limitaciones
1. **Factor de escala fijo**: IMG_W/2 × IMG_H/2
   - Si necesitas factores variables, usar `param_x_ratio` y `param_y_ratio`
2. **Tamaño máximo de imagen**: 256×256 (65536 píxeles)
   - Por ancho de bus `cfg_addr[15:0]`
   - Para imágenes más grandes, ampliar a 32 bits
3. **Resultados en memoria interna**: No se escriben de vuelta a BRAM automáticamente

### Extensiones Posibles
1. **Escritura de resultados**: Implementar lógica en `S_WRITE_RESULTS` de ambos tops
2. **Factor de escala variable**: Usar `param_x_ratio` y `param_y_ratio` en lugar de calcularlos fijos
3. **Múltiples modos de interpolación**: Añadir nearest-neighbor, bicubic, etc.
4. **DMA para carga/descarga**: Evitar escrituras píxel por píxel desde JTAG

---

## 8. DIAGRAMA DE TIEMPO

### Secuencial (1 píxel)
```
     ┌─────┬─────┬─────┬─────┐
clk  ┘     └─────┘     └─────┘
     ──────┐           ┌───────
start       └───────────┘
     ──────────────┐   ┌───────
valid_in            └───┘
     ────────────────┐ ┌───────
valid_out            └─┘
     ────────────────┐ ┌───────
pixel_out     [DATO] └─┘
```

### SIMD (Batch de N=4)
```
     ┌─────┬─────┬─────┬─────┬─────┬─────┐
clk  ┘     └─────┘     └─────┘     └─────┘
     ──┐               ┌───────────────────
start   └───────────────┘
S_IDLE │S_LOAD│S_RUN│S_WAIT│S_WRITE│S_IDLE
     ──────────────────────┐       ┌───────
done                        └───────┘
     ──────────────────────┐       ┌───────
pixel_out_vec[0:3]  [DATOS]└───────┘
```

---

**Versión**: 1.0
**Fecha**: 2025-01
**Autor**: Sistema de Downscaling con Interpolación Bilineal
