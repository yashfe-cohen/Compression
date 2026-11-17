module rmii_rx (
    input            clk,
    input            rst_n,
    input            crs_dv,
    input      [1:0] rxd,      
    output reg [1:0] dout,     // data out
    output reg       valid     // 1 while a packet is passing
);

    reg crs_dv_d; // crs_dv from previous clock

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout     <= 2'd0;
            valid    <= 1'b0;
            crs_dv_d <= 1'b0;
        end else begin
            crs_dv_d <= crs_dv;

            if (valid == 1'b0) begin
            
                if (crs_dv == 1'b1) begin
                    valid <= 1'b1;
                    dout  <= rxd;
                end
            end
            else if ((crs_dv == 1'b0) && (crs_dv_d == 1'b0)) begin

                valid <= 1'b0;
                dout  <= 2'b00;
            end
            else begin
                dout  <= rxd;
            end
        end
    end
endmodule
