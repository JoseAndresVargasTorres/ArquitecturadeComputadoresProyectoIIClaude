`timescale 1ns/1ps

module tb_ImageMemory_SIMDPort;

    // --------------------------------------------------
    // Parámetros
    // --------------------------------------------------
    localparam int IMG_W = 16;
    localparam int IMG_H = 16;
    localparam int N     = 4;

    // --------------------------------------------------
    // Señales
    // --------------------------------------------------
    logic clk, rst;

    logic        rd_req   [N];
    logic [7:0]  rd_data  [N];
    logic        rd_valid [N];
    logic [$clog2(IMG_W*IMG_H)-1:0] rd_addr [N];

    logic we;
    logic [$clog2(IMG_W*IMG_H)-1:0] wr_addr;
    logic [7:0] wr_data;

    // --------------------------------------------------
    // DUT
    // --------------------------------------------------
    ImageMemory_SIMDPort #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .N(N),
        .LINE_SIZE(8)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rd_req(rd_req),
        .rd_addr(rd_addr),
        .rd_valid(rd_valid),
        .rd_data(rd_data),
        .we(we),
        .wr_addr(wr_addr),
        .wr_data(wr_data)
    );

    // --------------------------------------------------
    // Clock
    // --------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // 100 MHz
    end

    // --------------------------------------------------
    // TEST
    // --------------------------------------------------
    initial begin
        int i;

        $display("\n===================================");
        $display("     TEST: ImageMemory_SIMDPort");
        $display("===================================\n");

        // --------------------------------------------
        // 1) Reset
        // --------------------------------------------
        rst = 1;
        we  = 0;
        for (i = 0; i < N; i++) begin
            rd_req[i] = 0;
            rd_addr[i] = 0;
        end

        repeat(4) @(posedge clk);
        rst = 0;

        // --------------------------------------------
        // 2) Escribir patrón conocido en memoria
        // --------------------------------------------
        $display("[1] Cargando memoria con patrón...");
        for (i = 0; i < 40; i++) begin
            @(posedge clk);
            we = 1;
            wr_addr = i;
            wr_data = i + 10;   // Patrón simple
        end
        @(posedge clk);
        we = 0;

        $display("[OK] Memoria cargada.\n");

        // --------------------------------------------
        // 3) LECTURA SIMD simultánea
        // --------------------------------------------
        $display("[2] Lectura paralela desde 4 lanes...");

        @(posedge clk);
        for (i = 0; i < N; i++) begin
            rd_req[i]  = 1;
            rd_addr[i] = i * 4;  // 0, 4, 8, 12
        end

        @(posedge clk);
        for (i = 0; i < N; i++)
            rd_req[i] = 0;

        // Esperar respuestas
        repeat (30) begin
            @(posedge clk);
            for (int k = 0; k < N; k++) begin
                if (rd_valid[k]) begin
                    $display("  [Lane %0d] Addr=%0d  Data=%0d  (esperado=%0d)",
                        k, rd_addr[k], rd_data[k], rd_addr[k] + 10);
                end
            end
        end

        // --------------------------------------------
        // 4) Segunda lectura = CACHE HIT inmediato
        // --------------------------------------------
        $display("\n[3] Segunda lectura (cache hit)...");

        @(posedge clk);
        for (i = 0; i < N; i++) begin
            rd_req[i]  = 1;
            rd_addr[i] = i * 4;  
        end
        @(posedge clk);
        rd_req = '{default:0};

        repeat (8) @(posedge clk);

        for (int k = 0; k < N; k++) begin
            if (rd_valid[k])
                $display("  HIT Lane %0d → Data=%0d", k, rd_data[k]);
        end

        // --------------------------------------------
        // END
        // --------------------------------------------
        $display("\n=== TEST COMPLETADO ===");
        $finish;
    end

endmodule
