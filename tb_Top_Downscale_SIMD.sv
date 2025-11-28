`timescale 1ns/1ps

module tb_Top_Downscale_SIMD;

    localparam int SRC_H = 32;
    localparam int SRC_W = 32;
    localparam int DST_H = 16;
    localparam int DST_W = 16;
    localparam int N     = 4;       // lanes SIMD

    localparam int SRC_DEPTH = SRC_W * SRC_H;
    localparam int DST_DEPTH = DST_W * DST_H;

    // Señales DUT
    logic        clk;
    logic        rst;
    logic        cfg_we;
    logic [15:0] cfg_addr;
    logic [7:0]  cfg_data;
    logic        start_req;
    logic        done;
    logic [7:0]  dbg_data;

    // Para generar imagen de entrada y comparación
    logic [7:0] image_in_ref  [0:SRC_H-1][0:SRC_W-1];
    int         expected      [0:DST_H-1][0:DST_W-1];

    int pass_count = 0;
    int fail_count = 0;
    int cycle_count = 0;

    // Instancia del DUT
    Top_Downscale_SIMD #(
        .SRC_W(SRC_W),
        .SRC_H(SRC_H),
        .DST_W(DST_W),
        .DST_H(DST_H),
        .N    (N)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .cfg_we   (cfg_we),
        .cfg_addr (cfg_addr),
        .cfg_data (cfg_data),
        .start_req(start_req),
        .done     (done),
        .dbg_data (dbg_data)
    );

    // Generación del reloj
    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // periodo = 10ns
    end

    // Función de referencia para interpolación bilineal
    function automatic int bilinear_ref_pixel(
        input int a, b, c, d,
        input real xw, yw
    );
        real w00 = (1.0 - xw) * (1.0 - yw);
        real w10 = xw         * (1.0 - yw);
        real w01 = (1.0 - xw) * yw;
        real w11 = xw         * yw;

        real r   = a*w00 + b*w10 + c*w01 + d*w11;
        int  pix = $rtoi(r + 0.5);

        if (pix < 0)   pix = 0;
        if (pix > 255) pix = 255;
        return pix;
    endfunction

    // Proceso principal de prueba
    initial begin
        int i, j;
        int addr;
        real xr, yr;
        real xs, ys;
        int x_l, x_h, y_l, y_h;
        real x_w, y_w;
        int a, b, c, d;
        int diff;

        // ============================================
        // 1. Generar imagen de entrada
        // ============================================
        $display("=== Generando imagen de entrada %0dx%0d ===", SRC_H, SRC_W);
        for (i = 0; i < SRC_H; i++) begin
            for (j = 0; j < SRC_W; j++) begin
                image_in_ref[i][j] = (i*4 + j*2) & 8'hFF;
            end
        end

        // ============================================
        // 2. Calcular valores esperados (modelo de referencia)
        // ============================================
        $display("=== Calculando valores esperados ===");
        xr = real'(SRC_W-1) / real'(DST_W-1);
        yr = real'(SRC_H-1) / real'(DST_H-1);
        $display("Ratios: x_ratio=%0.4f, y_ratio=%0.4f", xr, yr);

        for (i = 0; i < DST_H; i++) begin
            for (j = 0; j < DST_W; j++) begin
                xs = xr * j;
                ys = yr * i;

                x_l = int'($floor(xs));
                y_l = int'($floor(ys));
                x_h = int'($ceil(xs));
                y_h = int'($ceil(ys));

                if (x_h > SRC_W-1) x_h = SRC_W-1;
                if (y_h > SRC_H-1) y_h = SRC_H-1;

                x_w = xs - x_l;
                y_w = ys - y_l;

                a = image_in_ref[y_l][x_l];
                b = image_in_ref[y_l][x_h];
                c = image_in_ref[y_h][x_l];
                d = image_in_ref[y_h][x_h];

                expected[i][j] = bilinear_ref_pixel(a,b,c,d,x_w,y_w);
            end
        end

        // ============================================
        // 3. Reset del sistema
        // ============================================
        $display("=== Reset del sistema ===");
        rst      = 1;
        cfg_we   = 0;
        cfg_addr = 0;
        cfg_data = 0;
        start_req = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // ============================================
        // 4. Cargar imagen a memoria via interfaz JTAG
        // ============================================
        $display("=== Cargando imagen a memoria via JTAG ===");
        cfg_we = 1;
        for (i = 0; i < SRC_H; i++) begin
            for (j = 0; j < SRC_W; j++) begin
                addr = i * SRC_W + j;
                cfg_addr = addr[15:0];
                cfg_data = image_in_ref[i][j];
                @(posedge clk);
            end
        end
        cfg_we = 0;
        @(posedge clk);
        $display("Imagen cargada: %0d pixeles escritos", SRC_DEPTH);

        // ============================================
        // 5. Iniciar procesamiento
        // ============================================
        $display("=== Iniciando procesamiento SIMD ===");
        cycle_count = 0;

        @(posedge clk);
        start_req = 1;
        @(posedge clk);
        // start_req = 0;  // Mantener start_req alto hasta que done se active

        // Esperar a que termine el procesamiento
        while (!done) begin
            @(posedge clk);
            cycle_count++;
            // Timeout de seguridad
            if (cycle_count > 100000) begin
                $display("ERROR: Timeout esperando done");
                $finish;
            end
        end

        start_req = 0;
        @(posedge clk);

        $display("\n[TOP_SIMD] N=%0d", N);
        $display("[TOP_SIMD] Ciclos totales = %0d", cycle_count);
        $display("[TOP_SIMD] Tiempo = %0d ns (periodo=10ns)", cycle_count*10);

        // ============================================
        // 6. Verificar resultados
        // ============================================
        // NOTA: Accedemos directamente a la señal interna image_out del módulo
        // ya que el Top actual no escribe los resultados de vuelta a memoria
        $display("\n=== Verificando resultados ===");
        $display("Comparando HW (Top_Downscale_SIMD.image_out) vs REF");

        for (i = 0; i < DST_H; i++) begin
            for (j = 0; j < DST_W; j++) begin
                diff = dut.image_out[i][j] - expected[i][j];
                if (diff < 0) diff = -diff;

                if (diff <= 1) begin
                    pass_count++;
                end else begin
                    fail_count++;
                    $display("Pixel (%0d,%0d): HW=%0d REF=%0d diff=%0d  --> FAIL",
                             i, j, dut.image_out[i][j], expected[i][j], diff);
                end
            end
        end

        // ============================================
        // 7. Resumen final
        // ============================================
        $display("\n========================================");
        $display("RESUMEN Top_Downscale_SIMD:");
        $display("  PASS = %0d", pass_count);
        $display("  FAIL = %0d", fail_count);
        $display("  Total pixeles = %0d", DST_DEPTH);
        $display("========================================");

        if (fail_count == 0) begin
            $display("TEST PASSED: Todos los pixeles pasaron (tolerancia ±1 LSB)");
        end else begin
            $display("TEST FAILED: Hay errores en la interpolacion");
        end

        // Pequeña espera antes de finalizar
        repeat(10) @(posedge clk);
        $finish;
    end

    // Monitor opcional para debug
    // initial begin
    //     $monitor("t=%0t rst=%b start_req=%b done=%b dbg_data=%h",
    //              $time, rst, start_req, done, dbg_data);
    // end

endmodule
