`include "sysconfig.v"

module ysyx_041514_pc_reg (
    input clk,
    input rst,
    input [5:0] stall_valid_i,
    input [5:0] flush_valid_i,

    input [`ysyx_041514_XLEN_BUS] redirect_pc_i,  // branch pc,来自 exc 模块
    input redirect_pc_valid_i,  // 分支预测错误时，需要重定向 pc
    input [`ysyx_041514_XLEN_BUS] clint_pc_i,  // trap pc,来自mem
    input clint_pc_valid_i,  // trap pc valide,来自mem
    input clint_pc_plus4_valid_o,  // fencei 的 pc +4
    // input [`ysyx_041514_XLEN_BUS] bpu_pc_i,  // bpu pc ,来自 if bpu 分支预测
    input [`ysyx_041514_XLEN_BUS] bpu_pc_op1_i,
    input [`ysyx_041514_XLEN_BUS] bpu_pc_op2_i,
    input bpu_pc_valid_i,

    output                             read_req_o,
    output [`ysyx_041514_NPC_ADDR_BUS] pc_next_o,   //输出 next_pc, icache 取指
    output [    `ysyx_041514_XLEN_BUS] pc_o         //输出pc
);

  wire [`ysyx_041514_XLEN_BUS] _pc_current;
  wire [`ysyx_041514_XLEN_BUS] pc_temp = clint_pc_plus4_valid_o ? clint_pc_i : _pc_current;
  wire [`ysyx_041514_XLEN_BUS] pc_temp_plus4 = pc_temp + 'd4;

  reg [`ysyx_041514_XLEN_BUS] _pc_next;
  always @(*) begin
    if (clint_pc_valid_i & clint_pc_plus4_valid_o) begin : int_pc
      _pc_next = pc_temp_plus4;
    end else if (clint_pc_valid_i & ~clint_pc_plus4_valid_o) begin : trap_pc
      _pc_next = clint_pc_i;
    end else if (redirect_pc_valid_i) begin : redirect_pc
      _pc_next = redirect_pc_i;
    end else if (bpu_pc_valid_i) begin : bpu_pc
      _pc_next = bpu_pc_op1_i + bpu_pc_op2_i;
    end else begin
      _pc_next = pc_temp_plus4;
    end
  end


  wire _read_req = (~rst);  // pre if 阶段访问 icache, if 阶段返回数据

  wire _pc_reg_wen = (~stall_valid_i[`ysyx_041514_CTRLBUS_PC]) & (~rst);  // stall
  wire _flush_valid = flush_valid_i[`ysyx_041514_CTRLBUS_PC];  // flush

  wire [`ysyx_041514_XLEN_BUS] _pc_next_d = (_flush_valid) ? `ysyx_041514_PC_RESET_ADDR : _pc_next;
  ysyx_041514_regTemplate #(
      .WIDTH    (`ysyx_041514_XLEN),
      .RESET_VAL(`ysyx_041514_PC_RESET_ADDR)
  ) u_pc_reg (
      .clk (clk),
      .rst (rst),
      .din (_pc_next_d),
      .dout(_pc_current),
      .wen (_pc_reg_wen)
  );

  // next pc,为 icache 的访存地址, stall 时,保持上一个 pc 的值
  assign pc_next_o = stall_valid_i[`ysyx_041514_CTRLBUS_PC] ? _pc_current[31:0] : _pc_next_d[31:0];

  assign pc_o = _pc_current;
  assign read_req_o = _read_req;

endmodule
