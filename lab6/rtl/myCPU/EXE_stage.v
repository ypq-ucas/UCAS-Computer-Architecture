`include "mycpu.h"

module exe_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ms_allowin    ,
    output                         es_allowin    ,
    //from ds
    input                          ds_to_es_valid,
    input  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    //to ms
    output                         es_to_ms_valid,
    output [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    // data sram interface
    output        data_sram_en   ,
    output [ 3:0] data_sram_wen  ,
    output [31:0] data_sram_addr ,
    output [31:0] data_sram_wdata,

    //pipeline block   
    output [4:0] reg_dest_es,
    output [31:0] es_value,
    output es_lw_valid
);


reg         es_valid      ;
wire        es_ready_go   ;

reg  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus_r;
wire [11:0] es_alu_op     ;
wire        es_load_op    ;
wire        es_src1_is_sa ;  
wire        es_src1_is_pc ;
wire        es_src2_is_imm;
wire        es_src2_is_8  ;
wire        es_gr_we      ;
wire        es_mem_we     ;
wire [ 4:0] es_dest       ;
wire [15:0] es_imm        ;
wire [31:0] es_rs_value   ;
wire [31:0] es_rt_value   ;
wire [31:0] es_pc         ;

// lab6 append
wire        es_src2_is_0imm; 

wire es_inst_mult;
wire es_inst_multu;
wire es_inst_div;
wire es_inst_divu;
wire es_inst_mfhi;
wire es_inst_mflo;
wire es_inst_mthi;
wire es_inst_mtlo;

assign {
        es_inst_mult,     //144:144
        es_inst_multu,    //143:143
        es_inst_div,      //142:142
        es_inst_divu,     //141:141
        es_inst_mfhi,     //140:140
        es_inst_mflo,     //139:139
        es_inst_mthi,     //138:138
        es_inst_mtlo,     //137:137
        es_src2_is_0imm,  //136:136
        es_alu_op      ,  //135:124
        es_load_op     ,  //123:123
        es_src1_is_sa  ,  //122:122
        es_src1_is_pc  ,  //121:121
        es_src2_is_imm ,  //120:120
        es_src2_is_8   ,  //119:119
        es_gr_we       ,  //118:118
        es_mem_we      ,  //117:117
        es_dest        ,  //116:112
        es_imm         ,  //111:96
        es_rs_value    ,  //95 :64
        es_rt_value    ,  //63 :32
        es_pc             //31 :0
       } = ds_to_es_bus_r;

wire [31:0] es_alu_src1   ;
wire [31:0] es_alu_src2   ;
wire [31:0] es_alu_result ;

wire        es_res_from_mem;

assign es_res_from_mem = es_load_op;
assign es_to_ms_bus = {

                       es_res_from_mem,  //70:70
                       es_gr_we       ,  //69:69
                       es_dest        ,  //68:64
                       es_value  ,       //63:32
                       es_pc             //31:0
                      };
                      
                                
assign reg_dest_es = es_valid ? ((es_gr_we) ? (es_dest):(5'b0)):(5'b0);
//assign es_value = es_alu_result;

assign es_lw_valid = es_valid && es_load_op;                               

//assign es_ready_go    = 1'b1;

assign es_allowin     = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid =  es_valid && es_ready_go;
always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end

    if (ds_to_es_valid && es_allowin) begin
        ds_to_es_bus_r <= ds_to_es_bus;
    end
end

assign es_alu_src1 = es_src1_is_sa  ? {27'b0, es_imm[10:6]} : 
                     es_src1_is_pc  ? es_pc[31:0] :
                                      es_rs_value;
/*                                      
assign es_alu_src2 = es_src2_is_imm ? {{16{es_imm[15]}}, es_imm[15:0]} : 
                     es_src2_is_8   ? 32'd8 :
                                      es_rt_value;
*/                                      
assign es_alu_src2 = es_src2_is_imm ? {{16{es_imm[15]}},es_imm[15:0]} :
                     es_src2_is_0imm ? {16'b0,es_imm[15:0]} :
                     es_src2_is_8   ? 32'd8 :
                                      es_rt_value;

alu u_alu(
    .alu_op     (es_alu_op    ),
    .alu_src1   (es_alu_src1  ),
    .alu_src2   (es_alu_src2  ),
    .alu_result (es_alu_result)
    );

assign data_sram_en    = 1'b1;
assign data_sram_wen   = es_mem_we&&es_valid ? 4'hf : 4'h0;
assign data_sram_addr  = es_alu_result;
assign data_sram_wdata = es_rt_value;

// lab6 append mult & div
wire [31:0] mudi_src1;
wire [31:0] mudi_src2;
wire [63:0] signed_prod;
wire [63:0] unsigned_prod;
wire [63:0] div_result;
wire [63:0] divu_result;

reg div_valid;

wire div_ready;
wire div_divisor_ready;
wire div_dividend_ready;
wire div_done;

reg divu_valid;

wire divu_ready;
wire divu_divisor_ready;
wire divu_dividend_ready;
wire divu_done;

reg [31:0] cp0_hi;
reg [31:0] cp0_lo;

// es_ready_go
assign es_ready_go = es_inst_div ? div_done :
                     es_inst_divu ? divu_done :
                                   1'b1;
                                 
assign es_value = es_inst_mfhi ? cp0_hi :
                  es_inst_mflo ? cp0_lo :
                                 es_alu_result;

assign mudi_src1 = es_rs_value;
assign mudi_src2 = es_rt_value;
assign unsigned_prod = mudi_src1 * mudi_src2;
assign signed_prod = $signed(mudi_src1) * $signed(mudi_src2);

assign div_ready = div_divisor_ready & div_dividend_ready;
//assign div_valid = es_inst_div & div_ready & es_valid;

assign divu_ready = divu_divisor_ready & divu_dividend_ready;
//assign divu_valid = es_inst_divu & divu_ready & es_valid;

always @(posedge clk)
begin
    if(reset) begin
        div_valid <= 1'b0;
    end
    else if(div_valid & div_ready) begin
        div_valid <= 1'b0;
    end
//    else if(es_valid & es_inst_div) begin
//        div_valid <= 1'b1;
//    end
    else if(ds_to_es_valid && es_allowin) begin
        div_valid <= ds_to_es_bus[142:142];
    end
end

always @(posedge clk)
begin
    if(reset) begin
        divu_valid <= 1'b0;
    end
    else if(divu_valid & divu_ready) begin
        divu_valid <= 1'b0;
    end
    else if(ds_to_es_valid && es_allowin) begin
        divu_valid <= ds_to_es_bus[141:141];
    end
end

always @(posedge clk)
begin
    if(reset) begin
        cp0_hi <= 32'b0;
        cp0_lo <= 32'b0;
    end
    else if(es_inst_mult) begin
        cp0_hi <= signed_prod[63:32];
        cp0_lo <= signed_prod[31:0];
    end
    else if(es_inst_multu) begin
        cp0_hi <= unsigned_prod[63:32];
        cp0_lo <= unsigned_prod[31:0];
    end
    else if(es_inst_div & div_done) begin
        cp0_lo <= div_result[63:32];
        cp0_hi <= div_result[31:0];
    end
    else if(es_inst_divu & divu_done) begin
        cp0_lo <= divu_result[63:32];
        cp0_hi <= divu_result[31:0];
    end
    else if(es_inst_mthi) begin
        cp0_hi <= es_rs_value;
    end
    else if(es_inst_mtlo) begin
        cp0_lo <= es_rs_value;
    end
end

my_div u_my_div(
      .aclk (clk),
      .s_axis_divisor_tvalid (div_valid),
      .s_axis_divisor_tready  (div_divisor_ready),
      .s_axis_divisor_tdata  (mudi_src2),
      .s_axis_dividend_tvalid (div_valid),
      .s_axis_dividend_tready (div_dividend_ready),
      .s_axis_dividend_tdata (mudi_src1),
      .m_axis_dout_tvalid (div_done),
      .m_axis_dout_tdata (div_result)    
    );
    
my_divu u_my_divu(
      .aclk (clk),
      .s_axis_divisor_tvalid (divu_valid),
      .s_axis_divisor_tready  (divu_divisor_ready),
      .s_axis_divisor_tdata  (mudi_src2),
      .s_axis_dividend_tvalid (divu_valid),
      .s_axis_dividend_tready (divu_dividend_ready),
      .s_axis_dividend_tdata (mudi_src1),
      .m_axis_dout_tvalid (divu_done),
      .m_axis_dout_tdata (divu_result)    
    );
    
endmodule