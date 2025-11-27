`timescale 1ns/1ps

// =====================================================
// tb_Downscale_Secuencial_con_Memoria.sv
// Testbench que integra ImageMemory_SequentialPort
// con Downscale_Secuencial
// =====================================================

module tb_Downscale_Secuencial_con_Memoria;

    // Parámetros de la imagen
    localparam int SRC_H = 32;
    localparam int SRC_W = 32;
    localparam int DST_H = 16;
    localparam int DST_W = 16;

    localparam int SRC_SIZE = SRC_H * SRC_W;
    localparam int DST_SIZE = DST_H * DST_W;
    localparam int ADDR_BITS = $clog2(SRC_SIZE);

    // Señales del sistema
    logic clk, rst;

    // ====================================================
    // Señales de la memoria de entrada
    // ====================================================
    logic                  mem_rd_req;
    logic [ADDR_BITS-1:0]  mem_rd_addr;
    logic                  mem_rd_valid;
    logic [7:0]            mem_rd_data;

    logic                  mem_we;
    logic [ADDR_BITS-1:0]  mem_wr_addr;
    logic [7:0]            mem_wr_data;

    // ====================================================
    // Señales del Downscale
    // ====================================================
    logic                  downscale_start;
    logic                  downscale_done;
    logic [7:0]            image_in  [0:SRC_H-1][0:SRC_W-1];
    logic [7:0]            image_out [0:DST_H-1][0:DST_W-1];

    // ====================================================
    // Instancia de la Memoria Secuencial
    // ====================================================
    ImageMemory_SequentialPort #(
        .IMG_W(SRC_W),
        .IMG_H(SRC_H)
    ) u_input_memory (
        .clk      (clk),
        .rd_req   (mem_rd_req),
        .rd_addr  (mem_rd_addr),
        .rd_valid (mem_rd_valid),
        .rd_data  (mem_rd_data),
        .we       (mem_we),
        .wr_addr  (mem_wr_addr),
        .wr_data  (mem_wr_data)
    );

    // ====================================================
    // Instancia del Downscale Secuencial
    // ====================================================
    Downscale_Secuencial #(
        .SRC_H(SRC_H),
        .SRC_W(SRC_W),
        .DST_H(DST_H),
        .DST_W(DST_W)
    ) u_downscale (
        .clk      (clk),
        .rst      (rst),
        .start    (downscale_start),
        .image_in (image_in),
        .done     (downscale_done),
        .image_out(image_out)
    );

    // ====================================================
    // Generación de reloj (10ns de periodo)
    // ====================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ====================================================
    // Función de referencia para interpolación bilineal
    // ====================================================
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

    // ====================================================
    // Proceso de prueba
    // ====================================================
    initial begin
        int i, j, addr;
        int expected[0:DST_H-1][0:DST_W-1];
        real xr, yr, xs, ys;
        int x_l, x_h, y_l, y_h;
        real x_w, y_w;
        int a, b, c, d;
        int diff;
        int pass_count = 0;
        int fail_count = 0;
        int cycle_count = 0;

        $display("========================================");
        $display(" TB: Downscale Secuencial + Memoria");
        $display("========================================");
        $display("Imagen fuente: %0dx%0d", SRC_H, SRC_W);
        $display("Imagen destino: %0dx%0d", DST_H, DST_W);

        // ================================================
        // 1. Inicialización
        // ================================================
        rst = 1;
        downscale_start = 0;
        mem_we = 0;
        mem_wr_addr = 0;
        mem_wr_data = 0;
        mem_rd_req = 0;
        mem_rd_addr = 0;

        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("\n[1] Cargando imagen de prueba en la memoria...");

        // ================================================
        // 2. Cargar imagen de prueba en la memoria
        // ================================================
        mem_we = 1;
        for (i = 0; i < SRC_H; i++) begin
            for (j = 0; j < SRC_W; j++) begin
                addr = i * SRC_W + j;
                mem_wr_addr = addr;
                mem_wr_data = (i*4 + j*2) & 8'hFF;
                @(posedge clk);
            end
        end
        mem_we = 0;
        @(posedge clk);

        $display("    Imagen cargada en memoria (%0d bytes)", SRC_SIZE);

        // ================================================
        // 3. Leer imagen desde la memoria a arreglo 2D
        // ================================================
        $display("\n[2] Leyendo imagen desde memoria...");

        for (i = 0; i < SRC_H; i++) begin
            for (j = 0; j < SRC_W; j++) begin
                addr = i * SRC_W + j;
                mem_rd_req = 1;
                mem_rd_addr = addr;
                @(posedge clk);

                // Esperar rd_valid
                while (!mem_rd_valid) begin
                    mem_rd_req = 0;
                    @(posedge clk);
                end

                image_in[i][j] = mem_rd_data;
                mem_rd_req = 0;
            end
        end

        @(posedge clk);
        $display("    Imagen leída desde memoria al arreglo 2D");

        // ================================================
        // 4. Calcular imagen de referencia
        // ================================================
        $display("\n[3] Calculando imagen de referencia...");

        xr = real'(SRC_W-1) / real'(DST_W-1);
        yr = real'(SRC_H-1) / real'(DST_H-1);

        $display("    Ratios: x_ratio=%.4f, y_ratio=%.4f", xr, yr);

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

                a = image_in[y_l][x_l];
                b = image_in[y_l][x_h];
                c = image_in[y_h][x_l];
                d = image_in[y_h][x_h];

                expected[i][j] = bilinear_ref_pixel(a,b,c,d,x_w,y_w);
            end
        end

        $display("    Imagen de referencia calculada");

        // ================================================
        // 5. Ejecutar Downscale
        // ================================================
        $display("\n[4] Ejecutando Downscale Secuencial...");

        cycle_count = 0;

        @(posedge clk);
        downscale_start = 1;
        @(posedge clk);
        downscale_start = 0;

        while (!downscale_done) begin
            @(posedge clk);
            cycle_count++;
        end

        $display("    Downscale completado");
        $display("    Ciclos totales: %0d", cycle_count);
        $display("    Tiempo: %0d ns", cycle_count*10);

        // ================================================
        // 6. Verificar resultados
        // ================================================
        $display("\n[5] Verificando resultados...\n");

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

                a = image_in[y_l][x_l];
                b = image_in[y_l][x_h];
                c = image_in[y_h][x_l];
                d = image_in[y_h][x_h];

                diff = image_out[i][j] - expected[i][j];
                if (diff < 0) diff = -diff;

                $display("Pixel (%0d,%0d): x_src=%.2f, y_src=%.2f | vecinos=[%0d,%0d,%0d,%0d] | REF=%0d, HW=%0d, diff=%0d",
                         i, j, xs, ys, a, b, c, d, expected[i][j], image_out[i][j], diff);

                if (diff <= 1) begin
                    pass_count++;
                end else begin
                    fail_count++;
                    $display("    *** FAIL: diferencia mayor a 1 LSB");
                end
            end
        end

        // ================================================
        // 7. Resumen
        // ================================================
        $display("\n========================================");
        $display(" RESUMEN");
        $display("========================================");
        $display("PASS: %0d / %0d", pass_count, DST_H*DST_W);
        $display("FAIL: %0d / %0d", fail_count, DST_H*DST_W);

        if (fail_count == 0) begin
            $display("✓ TODOS los píxeles pasaron (±1 LSB)");
        end else begin
            $display("✗ Hay errores en la interpolación");
        end

        $display("\nCiclos: %0d", cycle_count);
        $display("Tiempo: %0d ns", cycle_count*10);
        $display("========================================\n");

        $finish;
    end

endmodule
