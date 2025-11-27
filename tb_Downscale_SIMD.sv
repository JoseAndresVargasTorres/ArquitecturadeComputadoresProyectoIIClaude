`timescale 1ns/1ps

module tb_Downscale_SIMD;

    localparam int SRC_H = 32;
    localparam int SRC_W = 32;
    localparam int DST_H = 16;
    localparam int DST_W = 16;
    localparam int N     = 4;   // lanes SIMD

    // Señales DUT
    logic clk, rst, start;
    logic done;

    logic [7:0] image_in  [0:SRC_H-1][0:SRC_W-1];
    logic [7:0] image_out [0:DST_H-1][0:DST_W-1];

    // Para referencia
    int expected[0:DST_H-1][0:DST_W-1];

    int pass_count = 0;
    int fail_count = 0;
    int cycle_count = 0;

    Downscale_SIMD #(
        .SRC_H(SRC_H),
        .SRC_W(SRC_W),
        .DST_H(DST_H),
        .DST_W(DST_W),
        .N    (N)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .image_in (image_in),
        .done     (done),
        .image_out(image_out)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;   // 10ns periodo
    end


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


    initial begin
        int i, j;
        real xr, yr;
        real xs, ys;
        int x_l, x_h, y_l, y_h;
        real x_w, y_w;
        int a, b, c, d;
        int diff;

  
        for (i = 0; i < SRC_H; i++) begin
            for (j = 0; j < SRC_W; j++) begin
                image_in[i][j] = (i*4 + j*2) & 8'hFF;
            end
        end

        $display("Imagen fuente %0dx%0d inicializada.", SRC_H, SRC_W);

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

                a = image_in[y_l][x_l];
                b = image_in[y_l][x_h];
                c = image_in[y_h][x_l];
                d = image_in[y_h][x_h];

                expected[i][j] = bilinear_ref_pixel(a,b,c,d,x_w,y_w);
            end
        end


        rst   = 1;
        start = 0;
        repeat(4) @(posedge clk);
        rst   = 0;

        cycle_count = 0;

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        while (!done) begin
            @(posedge clk);
            cycle_count++;
        end

        $display("\n[SIMD] N=%0d", N);
        $display("[SIMD] Ciclos totales = %0d", cycle_count);
        $display("[SIMD] Tiempo = %0d ns (periodo=10ns)", cycle_count*10);

 
        $display("\n=== COMPARACIÓN HW (Downscale_SIMD) vs REF ===");
        for (i = 0; i < DST_H; i++) begin
            for (j = 0; j < DST_W; j++) begin
                diff = image_out[i][j] - expected[i][j];
                if (diff < 0) diff = -diff;

                if (diff <= 1) begin
                    pass_count++;
                end else begin
                    fail_count++;
                    $display("Pixel (%0d,%0d): HW=%0d REF=%0d diff=%0d  --> FAIL",
                             i, j, image_out[i][j], expected[i][j], diff);
                end
            end
        end

        $display("\nResumen SIMD: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("TODOS los píxeles pasaron (±1 LSB).");
        else
            $display("Hay errores en la interpolación SIMD.");

        $finish;
    end

endmodule
