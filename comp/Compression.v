module Compression (
    input             clk,
    input             rst_n,

    // RX
    input             valid_in,
    input      [1:0]  din,

    // TX just pass RX 
    output reg [1:0]  dout,
    output reg        valid_out,

    // byte out
    output reg [7:0]  byte_out,
    output reg        byte_valid,
    output reg [10:0] byte_pos,
    output reg        is_file,      // 1 if byte is file data

    // FTP status
    output reg        got_150,
    output reg [31:0] file_size,    // from "(N bytes)"
    output reg        xfer_active,  // 1 between 150 and 226
    output reg [31:0] file_bytes,
    output reg        got_226
);

    localparam S_IDLE  = 4'd0;
    localparam S_SFD   = 4'd1;
    localparam S_ETH   = 4'd2;
    localparam S_IP    = 4'd3;
    localparam S_TCP   = 4'd4;
    localparam S_REPLY = 4'd5;
    localparam S_SIZE  = 4'd6;
    localparam S_DATA  = 4'd7;
    localparam S_DONE  = 4'd8;

    // dibits on the wire (LSB first)
    localparam DIBIT_PREAMBLE = 2'b01;   // 0x55 = 01 01 01 01
    localparam DIBIT_SFD      = 2'b11;   // 0xD5 = 01 01 01 11

    // dibit count in a byte
    localparam DIBIT_FIRST  = 2'd0;
    localparam DIBIT_SECOND = 2'd1;
    localparam DIBIT_THIRD  = 2'd2;
    localparam DIBIT_LAST   = 2'd3;      // 4 dibits = 1 byte

    // byte index in frame 
    localparam POS_ETHTYPE    = 11'd13;
    localparam POS_IP         = 11'd14;
    localparam POS_IP_LEN     = 11'd17;
    localparam POS_IP_PROTO   = 11'd23;   // change 6 to 108
    localparam POS_IP_CSUM    = 11'd25;   // fix checksum 
    localparam POS_IP_END     = 11'd33;
    localparam POS_TCP        = 11'd34;
    localparam POS_SRC_PORT   = 11'd35;
    localparam POS_TCP_OFFSET = 11'd46;
    
    //start val for pram 
    localparam PREAMBLE_BYTE = 8'h55;
    localparam SFD_BYTE      = 8'hD5;     // 8'hD5 in LSB first 
    localparam ETHTYPE_IPV4  = 16'h0800;
    localparam IP_VER_IHL5   = 8'h45;
    localparam PROTO_TCP     = 8'd6;
    localparam PROTO_IPCOMP  = 8'd108;
    localparam PORT_CTRL     = 16'd21;
    localparam PORT_DATA     = 16'd20;
    localparam REPLY_150 = 24'h313530;
    localparam REPLY_226 = 24'h323236;
    localparam TCP_HEADER_MIN = 6'd20;
    localparam REPLY_CODE_LEN = 11'd3;     // "150" / "226"

    // ascii codes in "(1234 bytes)"
    localparam ASCII_OPEN_PAREN = 8'h28;   // '('
    localparam ASCII_0          = 8'h30;   // '0'
    localparam ASCII_9          = 8'h39;   // '9'
    localparam ASCII_CR         = 8'h0D;   // end of line

    reg [3:0]  state;
    reg [1:0]  dibit_cnt;
    reg [5:0]  shift;
    reg [10:0] byte_cnt;
    reg [15:0] prev_bytes;
    reg [10:0] ip_len;
    reg [5:0]  tcp_len;
    reg [15:0] src_port;
    reg        in_paren;     // inside "(N bytes)"

    wire [7:0]  new_byte       = {din, shift};   // shift has 3 old dibits, din is the 4th
    wire [15:0] last_2_bytes   = {prev_bytes[7:0], new_byte};
    wire [23:0] last_3_bytes   = {prev_bytes, new_byte};
    wire [10:0] header_end     = POS_TCP + {5'd0, tcp_len} - 11'd1;   // last byte of tcp header
    wire [10:0] data_end       = POS_IP + ip_len - 11'd1;             // ip_len counts from the ip header
    wire [10:0] third_char_pos = header_end + REPLY_CODE_LEN;         // 150 / 226 are the first 3 chars

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout        <= 2'd0;
            valid_out   <= 1'b0;
            byte_out    <= 8'd0;
            byte_valid  <= 1'b0;
            byte_pos    <= 11'd0;
            is_file     <= 1'b0;
            got_150     <= 1'b0;
            file_size   <= 32'd0;
            xfer_active <= 1'b0;
            file_bytes  <= 32'd0;
            got_226     <= 1'b0;
            state       <= S_IDLE;
            dibit_cnt   <= 2'd0;
            shift       <= 6'd0;
            byte_cnt    <= 11'd0;
            prev_bytes  <= 16'd0;
            ip_len      <= 11'd0;
            tcp_len     <= TCP_HEADER_MIN;
            src_port    <= 16'd0;
            in_paren    <= 1'b0;
        end
        else begin
            dout      <= din;
            valid_out <= valid_in;

            byte_valid <= 1'b0;
            is_file    <= 1'b0;

            if (!valid_in) begin
                state     <= S_IDLE;
                dibit_cnt <= DIBIT_FIRST;
                byte_cnt  <= 11'd0;
            end
            else begin
                case (state)

                    // wait for first 0x55 of preamble
                    S_IDLE: begin
                        byte_cnt <= 11'd0;
                        case (dibit_cnt)
                            DIBIT_FIRST: begin
                                if (din == DIBIT_PREAMBLE) begin  
                                    shift     <= {din, shift[5:2]};   // LSB first, new dibit goes in from the top
                                    dibit_cnt <= dibit_cnt + 2'd1;
                                end
                            end
                            DIBIT_SECOND, DIBIT_THIRD: begin
                                shift     <= {din, shift[5:2]};
                                dibit_cnt <= dibit_cnt + 2'd1;
                            end
                            DIBIT_LAST: begin
                                shift     <= {din, shift[5:2]};
                                dibit_cnt <= dibit_cnt + 2'd1;
                                if (new_byte == PREAMBLE_BYTE) begin   // got 0x55
                                    byte_out   <= new_byte;
                                    byte_valid <= 1'b1;
                                    byte_pos   <= 11'd0;
                                    state      <= S_SFD;
                                end
                            end
                        endcase
                    end

                    // inside preamble, wait for SFD
                    S_SFD: begin
                        byte_cnt  <= 11'd0;
                        tcp_len   <= TCP_HEADER_MIN;  // new frame
                        in_paren  <= 1'b0;
                        shift     <= {din, shift[5:2]};
                        dibit_cnt <= dibit_cnt + 2'd1;

                        case (din)
                            DIBIT_PREAMBLE: begin
                                if (dibit_cnt == DIBIT_LAST) begin
                                    byte_out   <= new_byte;
                                    byte_valid <= 1'b1;
                                    byte_pos   <= 11'd0;
                                end
                            end
                            DIBIT_SFD: begin
                                byte_out   <= new_byte;
                                byte_valid <= 1'b1;
                                byte_pos   <= 11'd0;
                                dibit_cnt  <= DIBIT_FIRST;    // next dibit is the first one of dest MAC
                                state      <= S_ETH;
                            end
                            default: state <= S_IDLE;   // not preamble  drop it
                        endcase
                    end

                    // frame bytes
                    S_ETH, S_IP, S_TCP, S_REPLY, S_SIZE, S_DATA, S_DONE: begin
                        shift     <= {din, shift[5:2]};
                        dibit_cnt <= dibit_cnt + 2'd1;

                        if (dibit_cnt == DIBIT_LAST) begin
                            byte_out   <= new_byte;
                            byte_valid <= 1'b1;
                            byte_pos   <= byte_cnt;
                            byte_cnt   <= byte_cnt + 11'd1;
                            prev_bytes <= last_2_bytes;   // keep 2 old bytes for 16 bit fields and "150"

                            case (state)

                                S_ETH: begin  // Ethernet header
                                    case (byte_cnt)
                                        POS_ETHTYPE: begin
                                            if (last_2_bytes == ETHTYPE_IPV4)
                                                state <= S_IP;
                                            else
                                                state <= S_DONE;
                                        end
                                        default: ;
                                    endcase
                                end

                                S_IP: begin  // IPv4 header
                                    case (byte_cnt)
                                        POS_IP: begin
                                            if (new_byte != IP_VER_IHL5)
                                                state <= S_DONE;
                                        end
                                        POS_IP_LEN:
                                            ip_len <= last_2_bytes[10:0];
                                        POS_IP_PROTO: begin
                                            if (new_byte != PROTO_TCP)
                                                state <= S_DONE;
                                        end
                                        POS_IP_END:
                                            state <= S_TCP;
                                        default: ;
                                    endcase
                                end

                                S_TCP: begin  // TCP header
                                    case (byte_cnt)
                                        POS_SRC_PORT:
                                            src_port <= last_2_bytes;
                                        POS_TCP_OFFSET:
                                            tcp_len <= {new_byte[7:4], 2'b00};  // offset is in words, * 4 = bytes
                                        default: ;
                                    endcase

                                    if (byte_cnt == header_end) begin
                                        if (header_end == data_end)
                                            state <= S_DONE;     // empty packet
                                        else begin
                                            case (src_port)
                                                PORT_CTRL:        // FTP reply
                                                    state <= S_REPLY;
                                                PORT_DATA: begin  // file data
                                                    if (xfer_active == 1'b1)
                                                        state <= S_DATA;
                                                    else
                                                        state <= S_DONE;
                                                end
                                                default:
                                                    state <= S_DONE;
                                            endcase
                                        end
                                    end
                                end

                                S_REPLY: begin
                                    if (byte_cnt > data_end)
                                        state <= S_DONE;
                                    else if (byte_cnt == third_char_pos) begin
                                        case (last_3_bytes)
                                            REPLY_150: begin    // start transfer
                                                got_150     <= 1'b1;
                                                file_size   <= 32'd0;
                                                xfer_active <= 1'b1;
                                                file_bytes  <= 32'd0;
                                                got_226     <= 1'b0;
                                                state       <= S_SIZE;
                                            end
                                            REPLY_226: begin    // end transfer
                                                got_226     <= 1'b1;
                                                xfer_active <= 1'b0;
                                                state       <= S_DONE;
                                            end
                                            default:
                                                state <= S_DONE;
                                        endcase
                                    end
                                end

                                S_SIZE: begin  // size from "(1234 bytes)"
                                    case (new_byte)
                                        ASCII_OPEN_PAREN: begin
                                            file_size <= 32'd0;
                                            in_paren  <= 1'b1;
                                        end
                                        ASCII_CR: begin
                                            in_paren <= 1'b0;
                                            state    <= S_DONE;
                                        end
                                        default: begin
                                            if ((new_byte >= ASCII_0) && (new_byte <= ASCII_9)) begin   // its a digit
                                                if (in_paren == 1'b1)
                                                    file_size <= (file_size * 32'd10) + {28'd0, new_byte[3:0]};  // ascii '0'-'9' low 4 bits = the digit
                                            end
                                            else
                                                in_paren <= 1'b0;   // ' ' or ')' ends the number
                                        end
                                    endcase

                                    if (byte_cnt == data_end)
                                        state <= S_DONE;
                                end

                                S_DATA: begin
                                    is_file    <= 1'b1;
                                    file_bytes <= file_bytes + 32'd1;
                                    if (byte_cnt == data_end)
                                        state <= S_DONE;
                                end

                                S_DONE: ;  // wait for end of frame

                                default: state <= S_DONE;

                            endcase
                        end
                    end

                    default: state <= S_IDLE;

                endcase
            end
        end
    end

endmodule