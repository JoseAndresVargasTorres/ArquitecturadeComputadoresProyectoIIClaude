module ModoSIMD #(
    parameter int N = 4   // cantidad de píxeles por ciclo
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,

    // vectores de entrada (cada uno N elementos)
    input  logic [7:0] I00_vec  [N],
    input  logic [7:0] I10_vec  [N],
    input  logic [7:0] I01_vec  [N],
    input  logic [7:0] I11_vec  [N],
    input  logic [7:0] alpha_vec[N],
    input  logic [7:0] beta_vec [N],

    output logic valid_out,
    output logic [7:0] pixel_out_vec[N]
);

    logic valid_int [N];

    genvar i;
    generate
        for (i = 0; i < N; i++) begin : SIMD_CORES
            ModoSecuencial core (
                .clk(clk),
                .rst(rst),
                .valid_in(valid_in),
                .I00(I00_vec[i]),
                .I10(I10_vec[i]),
                .I01(I01_vec[i]),
                .I11(I11_vec[i]),
                .alpha(alpha_vec[i]),
                .beta(beta_vec[i]),
                .valid_out(valid_int[i]),
                .pixel_out(pixel_out_vec[i])
            );
        end
    endgenerate

    // valid_out será válido cuando el primer núcleo lo esté
    assign valid_out = valid_int[0];

endmodule
