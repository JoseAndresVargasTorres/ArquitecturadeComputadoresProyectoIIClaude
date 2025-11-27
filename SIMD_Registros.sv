module SIMD_Registros #(
    parameter int N = 4
)(
    input  logic clk,
    input  logic rst,
    input  logic load,

    input  logic [7:0] I00_in  [N],
    input  logic [7:0] I10_in  [N],
    input  logic [7:0] I01_in  [N],
    input  logic [7:0] I11_in  [N],
    input  logic [7:0] alpha_in[N],
    input  logic [7:0] beta_in [N],

    output logic [7:0] I00_out [N],
    output logic [7:0] I10_out [N],
    output logic [7:0] I01_out [N],
    output logic [7:0] I11_out [N],
    output logic [7:0] alpha_out[N],
    output logic [7:0] beta_out [N]
);

    logic [7:0] I00_r [N], I10_r[N], I01_r[N], I11_r[N];
    logic [7:0] alpha_r[N], beta_r[N];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            I00_r   <= '{default:0};
            I10_r   <= '{default:0};
            I01_r   <= '{default:0};
            I11_r   <= '{default:0};
            alpha_r <= '{default:0};
            beta_r  <= '{default:0};
        end else if (load) begin
            I00_r   <= I00_in;
            I10_r   <= I10_in;
            I01_r   <= I01_in;
            I11_r   <= I11_in;
            alpha_r <= alpha_in;
            beta_r  <= beta_in;
        end
    end

    assign I00_out   = I00_r;
    assign I10_out   = I10_r;
    assign I01_out   = I01_r;
    assign I11_out   = I11_r;
    assign alpha_out = alpha_r;
    assign beta_out  = beta_r;

endmodule
