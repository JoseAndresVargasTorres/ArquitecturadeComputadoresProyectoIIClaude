`timescale 1ns/1ps

module tb_downscale_ModoSIMD;

    localparam int SRC_H = 4;
    localparam int SRC_W = 4;
    localparam int DST_H = 3;
    localparam int DST_W = 3;
    localparam int N = 4;

    logic [7:0] image [0:SRC_H-1][0:SRC_W-1];

    logic clk, rst, valid_in, valid_out;

    logic [7:0] I00_vec  [N];
    logic [7:0] I10_vec  [N];
    logic [7:0] I01_vec  [N];
    logic [7:0] I11_vec  [N];
    logic [7:0] alpha_vec[N];
    logic [7:0] beta_vec [N];

    logic [7:0] pixel_out_vec[N];

    int pass_count = 0;
    int fail_count = 0;

    ModoSIMD #(N) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .I00_vec(I00_vec),
        .I10_vec(I10_vec),
        .I01_vec(I01_vec),
        .I11_vec(I11_vec),
        .alpha_vec(alpha_vec),
        .beta_vec(beta_vec),
        .valid_out(valid_out),
        .pixel_out_vec(pixel_out_vec)
    );

    // Clock 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    function automatic int bilinear_ref_pixel(
        input int a, b, c, d,
        input real xw, yw
    );
        real w00 = (1-xw)*(1-yw);
        real w10 = (xw)*(1-yw);
        real w01 = (1-xw)*(yw);
        real w11 = (xw)*(yw);
        real pix_r = a*w00 + b*w10 + c*w01 + d*w11;
        int pix_i = $rtoi(pix_r + 0.5);
        if (pix_i < 0) pix_i = 0;
        else if (pix_i > 255) pix_i = 255;
        return pix_i;
    endfunction


    // --------------------------------------------------------------------
    // ███   FULL DEBUG SIMD (igual que el testbench secuencial)
    // --------------------------------------------------------------------
    task automatic run_batch(
        input int batch_id,
        input real x_ratio,
        input real y_ratio
    );
        int k;
        int idx;
        int i_dst, j_dst;

        real x_src, y_src;
        int x_l, x_h, y_l, y_h;
        real x_w, y_w;
        int a,b,c,d;
        int expected[N];
        int diff;

        $display("\n======================================");
        $display("===  BATCH SIMD %0d (4 pixeles)   ===", batch_id);
        $display("======================================");

        for (k = 0; k < N; k++) begin
            idx = batch_id*N + k;

            if (idx >= DST_H*DST_W) begin
                I00_vec[k] = 0;
                I10_vec[k] = 0;
                I01_vec[k] = 0;
                I11_vec[k] = 0;
                alpha_vec[k] = 0;
                beta_vec[k] = 0;
                expected[k] = -1;
                continue;
            end

            i_dst = idx / DST_W;
            j_dst = idx % DST_W;

            x_src = x_ratio * j_dst;
            y_src = y_ratio * i_dst;

            x_l = int'($floor(x_src));
            x_h = int'($ceil (x_src));
            y_l = int'($floor(y_src));
            y_h = int'($ceil (y_src));

            if (x_l < 0) x_l = 0;
            if (y_l < 0) y_l = 0;
            if (x_h > SRC_W-1) x_h = SRC_W-1;
            if (y_h > SRC_H-1) y_h = SRC_H-1;

            x_w = x_src - x_l;
            y_w = y_src - y_l;

            a = image[y_l][x_l];
            b = image[y_l][x_h];
            c = image[y_h][x_l];
            d = image[y_h][x_h];

            expected[k] = bilinear_ref_pixel(a,b,c,d,x_w,y_w);

            alpha_vec[k] = int'(x_w*256.0 + 0.5);
            beta_vec[k]  = int'(y_w*256.0 + 0.5);

            I00_vec[k] = a;
            I10_vec[k] = b;
            I01_vec[k] = c;
            I11_vec[k] = d;

            // -----------------------------
            // Debug individual del lane SIMD
            // -----------------------------
            $display("\n--- PIXEL SIMD %0d (idx=%0d) ---", k, idx);
            $display("  (i_dst,j_dst) = (%0d,%0d)", i_dst, j_dst);
            $display("  x_src=%.4f  y_src=%.4f", x_src, y_src);
            $display("  x_l=%0d x_h=%0d  y_l=%0d y_h=%0d", x_l, x_h, y_l, y_h);
            $display("  a=%0d b=%0d c=%0d d=%0d", a,b,c,d);
            $display("  x_w=%.4f  y_w=%.4f", x_w, y_w);
            $display("  alpha=%0d (%.4f)  beta=%0d (%.4f)",
                     alpha_vec[k], alpha_vec[k]/256.0,
                     beta_vec[k],  beta_vec[k]/256.0);
            $display("  expected=%0d", expected[k]);
        end

        @(posedge clk);
        valid_in <= 1;

        @(posedge clk);
        valid_in <= 0;

        wait(valid_out == 1);

        for (k = 0; k < N; k++) begin
            if (expected[k] < 0) continue;

            diff = pixel_out_vec[k] - expected[k];
            if (diff < 0) diff = -diff;

            $display("  HW[%0d] = %0d   REF=%0d   diff=%0d",
                      k, pixel_out_vec[k], expected[k], diff);

            if (diff <= 1) begin
                pass_count++;
                $display("   ✓ PASS");
            end else begin
                fail_count++;
                $display("   ✗ FAIL");
            end
        end

        $display("=== FIN BATCH %0d ===", batch_id);
    endtask


    initial begin
        int total_pixels = DST_H*DST_W;
        int total_batches = (total_pixels + N - 1) / N;
        int b;

        real x_ratio = real'(SRC_W - 1) / real'(DST_W - 1);
        real y_ratio = real'(SRC_H - 1) / real'(DST_H - 1);

        image[0] = '{10,30,50,70};
        image[1] = '{90,110,130,150};
        image[2] = '{170,190,210,230};
        image[3] = '{240,245,250,255};

        rst = 1;
        valid_in = 0;
        repeat(4) @(posedge clk);
        rst = 0;

        for (b = 0; b < total_batches; b++) begin
            run_batch(b, x_ratio, y_ratio);
        end

        $display("\n===============================");
        $display("      FIN SIMD");
        $display("      PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===============================");

        if (fail_count == 0)
            $display("    ✓ SIMD CORRECTO");
        else
            $display("    ✗ ERROR EN SIMD");

        $finish;
    end


    initial begin
        $dumpfile("tb_downscale_ModoSIMD.vcd");
        $dumpvars(0, tb_downscale_ModoSIMD);
    end

endmodule
