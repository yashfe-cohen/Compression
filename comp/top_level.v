module top_level (
    input            clk,              
    input            rst_n,            
    output           clk_PHy,      
    output           rst_n_PHY,        

    // port A
    input            phya_rx_crs_dv,   
    input      [1:0] phya_rxd,         
    output           phya_tx_en,       
    output     [1:0] phya_txd,         

    // port B
    input            phyb_rx_crs_dv,   
    input      [1:0] phyb_rxd,         
    output           phyb_tx_en,       
    output     [1:0] phyb_txd          
);

    assign clk_PHy   = clk; // pin for phy 
    assign rst_n_PHY = rst_n;

    //  path A to B
    
    wire [1:0]  rx_a_data;             
    wire        rx_a_valid;
    wire [1:0]  to_b_data;             
    wire        to_b_valid;

    wire [7:0]  a_byte;
    wire        a_byte_valid;
    wire [10:0] a_byte_pos;
    wire        a_is_file;
    wire        a_got_150;
    wire        a_got_226;
    wire        a_xfer_active;
    wire [31:0] a_file_size;
    wire [31:0] a_file_bytes;

    rmii_rx rx_from_a (
        .clk    (clk),
        .rst_n  (rst_n),
        .crs_dv (phya_rx_crs_dv),
        .rxd    (phya_rxd),
        .dout   (rx_a_data),
        .valid  (rx_a_valid)
    );

    Compression comp_a_to_b (
        .clk         (clk),
        .rst_n       (rst_n),
        .valid_in    (rx_a_valid),
        .din         (rx_a_data),
        .dout        (to_b_data),
        .valid_out   (to_b_valid),
        .byte_out    (a_byte),
        .byte_valid  (a_byte_valid),
        .byte_pos    (a_byte_pos),
        .is_file     (a_is_file),
        .got_150     (a_got_150),
        .got_226     (a_got_226),
        .xfer_active (a_xfer_active),
        .file_size   (a_file_size),
        .file_bytes  (a_file_bytes)
    );

    rmii_tx tx_to_b (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid_in (to_b_valid),
        .din      (to_b_data),
        .tx_en    (phyb_tx_en),
        .txd      (phyb_txd)
    );

    // path B to A 
    
    wire [1:0]  rx_b_data;             
    wire        rx_b_valid;
    wire [1:0]  to_a_data;             
    wire        to_a_valid;

    wire [7:0]  b_byte;
    wire        b_byte_valid;
    wire [10:0] b_byte_pos;
    wire        b_is_file;
    wire        b_got_150;
    wire        b_got_226;
    wire        b_xfer_active;
    wire [31:0] b_file_size;
    wire [31:0] b_file_bytes;

    rmii_rx rx_from_b (
        .clk    (clk),
        .rst_n  (rst_n),
        .crs_dv (phyb_rx_crs_dv),
        .rxd    (phyb_rxd),
        .dout   (rx_b_data),
        .valid  (rx_b_valid)
    );

    Compression comp_b_to_a (
        .clk         (clk),
        .rst_n       (rst_n),
        .valid_in    (rx_b_valid),
        .din         (rx_b_data),
        .dout        (to_a_data),
        .valid_out   (to_a_valid),
        .byte_out    (b_byte),
        .byte_valid  (b_byte_valid),
        .byte_pos    (b_byte_pos),
        .is_file     (b_is_file),
        .got_150     (b_got_150),
        .got_226     (b_got_226),
        .xfer_active (b_xfer_active),
        .file_size   (b_file_size),
        .file_bytes  (b_file_bytes)
    );

    rmii_tx tx_to_a (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid_in (to_a_valid),
        .din      (to_a_data),
        .tx_en    (phya_tx_en),
        .txd      (phya_txd)
    );

endmodule