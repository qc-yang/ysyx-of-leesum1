`include "sysconfig.v"
module ysyx_041514_execute_top (
    input                                       clk,
    input                                       rst,
    /******************************* from id/ex *************************/
    // pc
    input  [             `ysyx_041514_XLEN_BUS] pc_i,
    input  [         `ysyx_041514_INST_LEN-1:0] inst_data_i,
    input                                       bpu_taken_i,
    // gpr 译码结果
    input  [    `ysyx_041514_REG_ADDRWIDTH-1:0] rd_idx_i,
    input  [             `ysyx_041514_XLEN_BUS] rs1_data_i,
    input  [             `ysyx_041514_XLEN_BUS] rs2_data_i,
    input  [          `ysyx_041514_IMM_LEN-1:0] imm_data_i,
    // CSR 译码结果 
    input  [`ysyx_041514_CSR_REG_ADDRWIDTH-1:0] csr_readaddr_i,
    input  [             `ysyx_041514_XLEN_BUS] csr_data_i,
    input  [          `ysyx_041514_IMM_LEN-1:0] csr_imm_i,
    input                                       csr_imm_valid_i,
    // 指令微码
    input  [        `ysyx_041514_ALUOP_LEN-1:0] alu_op_i,         // alu 操作码
    input  [        `ysyx_041514_MEMOP_LEN-1:0] mem_op_i,         // 访存操作码
    input  [        `ysyx_041514_EXCOP_LEN-1:0] exc_op_i,         // exc 操作码
    input  [        `ysyx_041514_CSROP_LEN-1:0] csr_op_i,         // exc_csr 操作码
    /* TARP 总线 */
    input  [             `ysyx_041514_TRAP_BUS] trap_bus_i,
    /********************** to ex/mem **************************/
    // pc 同时给 EX/MEM 和 MEM（用于中断返回地址）
    output [             `ysyx_041514_XLEN_BUS] pc_o,
    output [         `ysyx_041514_INST_LEN-1:0] inst_data_o,
    // gpr 译码结果
    output [    `ysyx_041514_REG_ADDRWIDTH-1:0] rd_idx_o,
    output [             `ysyx_041514_XLEN_BUS] rs2_data_o,
    // CSR 译码结果 
    output [`ysyx_041514_CSR_REG_ADDRWIDTH-1:0] exc_csr_addr_o,
    output [        `ysyx_041514_MEMOP_LEN-1:0] mem_op_o,         // 访存操作码

    output [`ysyx_041514_XLEN_BUS] exc_alu_data_o,  // ALU 计算得到的数据，同时送给 ID（bypass） 和 EX/MEM
    output [`ysyx_041514_XLEN_BUS] exc_csr_data_o,  // csr 计算得到的数据
    output exc_csr_valid_o,
    /************************to pc_reg ******************************************/
    output [`ysyx_041514_XLEN_BUS] redirect_pc_o,
    output redirect_pc_valid_o,

    /********************* from data_buff *******************/

    input alu_data_buff_valid_i,  // ALU结果缓存
    input [`ysyx_041514_XLEN_BUS] alu_data_buff_i,
    output alu_data_ready_o,
    /* trap bus */
    output jump_hazard_valid_o,  // 请求暂停流水线
    output alu_mul_div_valid_o,

    output [`ysyx_041514_TRAP_BUS] trap_bus_o
);
  assign pc_o = pc_i;
  assign inst_data_o = inst_data_i;
  assign mem_op_o = mem_op_i;
  assign rs2_data_o = rs2_data_i;
  assign rd_idx_o = rd_idx_i;
  assign exc_csr_addr_o = csr_readaddr_i;


  wire [`ysyx_041514_XLEN_BUS] _alu_out;
  wire _compare_out;
  wire alu_stall_req;


  wire _excop_none = exc_op_i[`ysyx_041514_EXCOP_NONE];
  wire _excop_auipc = exc_op_i[`ysyx_041514_EXCOP_AUIPC];
  wire _excop_lui = exc_op_i[`ysyx_041514_EXCOP_LUI];
  wire _excop_jal = exc_op_i[`ysyx_041514_EXCOP_JAL];
  wire _excop_jalr = exc_op_i[`ysyx_041514_EXCOP_JALR];
  wire _excop_load = exc_op_i[`ysyx_041514_EXCOP_LOAD];
  wire _excop_store = exc_op_i[`ysyx_041514_EXCOP_STORE];
  wire _excop_branch = exc_op_i[`ysyx_041514_EXCOP_BRANCH];
  wire _excop_opimm = exc_op_i[`ysyx_041514_EXCOP_OPIMM];
  wire _excop_opimm32 = exc_op_i[`ysyx_041514_EXCOP_OPIMM32];
  wire _excop_op = exc_op_i[`ysyx_041514_EXCOP_OP];
  wire _excop_op32 = exc_op_i[`ysyx_041514_EXCOP_OP32];
  wire _excop_csr = exc_op_i[`ysyx_041514_EXCOP_CSR];

  /***************************** branch ********************************/

  // 当不考虑分支预测时，以下两种情况 跳转指令 ，应该执行跳转
  // 1. branch 指令，且条件成立
  // 2. jal、jalr 指令
  wire jump_taken = (_compare_out & _excop_branch) | _excop_jalr | _excop_jal;

  // bpu_taken_i 分支预测的跳转情况
  // jump_taken  正确的跳转情况
  // 两者不同，分支预测错误，需要冲刷流水线，修改 pc
  wire bpu_pc_wrong = jump_taken ^ bpu_taken_i;



  // 1. _excop_branch，_excop_jal （pc+imm）
  // 2. _excop_jalr (rs1+imm)
  // 3. bpu err （pc+4）or (pc+imm)、(rs1+imm)，depending on bpu_taken_i
  reg [`ysyx_041514_XLEN_BUS] redirect_pc_op1;
  reg [`ysyx_041514_XLEN_BUS] redirect_pc_op2;
  always @(*) begin
    if (bpu_taken_i) begin
      redirect_pc_op1 = pc_i;
      redirect_pc_op2 = 'd4;
    end else begin
      redirect_pc_op1 = _excop_jalr ? rs1_data_i : pc_i;
      redirect_pc_op2 = imm_data_i;
    end
  end

  // TODO 节省加法器, 可能引入关键路径
  wire [`ysyx_041514_XLEN_BUS] redirect_pc = redirect_pc_op1 + redirect_pc_op2;

  assign redirect_pc_o = redirect_pc;
  assign redirect_pc_valid_o = bpu_pc_wrong;
  // 若跳转指令有效，通知控制模块，中断流水线
  assign jump_hazard_valid_o = bpu_pc_wrong;


  /****************************** ALU 操作******************************************/

  /* ALU 两端操作数选择 */
  wire _rs1_rs2 = _excop_op32 | _excop_op | _excop_branch;
  wire _rs1_imm = _excop_opimm | _excop_opimm32 | _excop_load | _excop_store;
  wire _pc_4 = _excop_jal | _excop_jalr;
  wire _pc_imm12 = _excop_auipc;
  wire _none_imm12 = _excop_lui;
  wire _none_csr = _excop_csr;  //保存原来的 csr csr->rd

  /* jal jalr lui auipc ecall ebreak 需要单独处理 */
  /* 拼接代替左移 */
  // wire [`ysyx_041514_IMM_LEN-1:0] _imm_aui_auipc = imm_data << 12;
  wire [`ysyx_041514_IMM_LEN-1:0] _imm_aui_auipc = {imm_data_i[`ysyx_041514_IMM_LEN-1:12], 12'b0};

  // ALU 第一个操作数
  wire [`ysyx_041514_XLEN_BUS] _alu_in1 = ({`ysyx_041514_XLEN{_rs1_rs2 | _rs1_imm}}&rs1_data_i) |
                                       ({`ysyx_041514_XLEN{_pc_4 | _pc_imm12}}&pc_i) |
                                       ({`ysyx_041514_XLEN{_none_imm12|_none_csr}}&`ysyx_041514_XLEN'b0);
  // ALU 第二个操作数
  wire [`ysyx_041514_XLEN_BUS] _alu_in2 = ({`ysyx_041514_XLEN{_rs1_rs2}}&rs2_data_i) |
                                       ({`ysyx_041514_XLEN{_rs1_imm}}&imm_data_i) |
                                       ({`ysyx_041514_XLEN{_none_csr}}&csr_data_i) |
                                       ({`ysyx_041514_XLEN{_pc_4}}&`ysyx_041514_XLEN'd4)   |
                                       ({`ysyx_041514_XLEN{_pc_imm12|_none_imm12}}&_imm_aui_auipc);


  ysyx_041514_alu_top u_alu (
      .clk(clk),
      .rst(rst),
      /* ALU 端口 */
      .alu_a_i(_alu_in1),
      .alu_b_i(_alu_in2),
      .alu_out_o(_alu_out),
      .alu_op_i(alu_op_i),
      .compare_out_o(_compare_out),
      /* 乘法、除法结果缓存 */
      .alu_data_buff_valid_i(alu_data_buff_valid_i),
      .alu_data_buff_i(alu_data_buff_i),
      .alu_data_ready_o(alu_data_ready_o),
      .alu_stall_req_o(alu_stall_req)
  );
  /* alu计算结果需要符号扩展 */
  wire _alu_sext = _excop_opimm32 | _excop_op32;
  wire [`ysyx_041514_XLEN_BUS] _alu_sext_out = {{32{_alu_out[31]}}, _alu_out[31:0]};
  assign exc_alu_data_o = (_alu_sext) ? _alu_sext_out : _alu_out;
  // 乘除法需要暂停处理器
  assign alu_mul_div_valid_o = alu_stall_req;

  /***************************** CSR 执行操作 **************************/

  wire [`ysyx_041514_XLEN_BUS] _csr_exe_data;
  wire _csr_exe_data_valid;
  ysyx_041514_execute_csr u_execute_csr (
      .csr_imm_i           (csr_imm_i),
      .csr_imm_valid_i     (csr_imm_valid_i),     // 是否是立即数指令
      .rs1_data_i          (rs1_data_i),          // rs1 data
      .csr_data_i          (csr_data_i),          // 读取的 CSR 数据
      .csr_op_i            (csr_op_i),            // csr 操作码
      .csr_exe_data_o      (_csr_exe_data),
      .csr_exe_data_valid_o(_csr_exe_data_valid)
  );

  assign exc_csr_data_o  = _csr_exe_data;
  assign exc_csr_valid_o = _csr_exe_data_valid;




  /* trap_bus TODO:add more*/
  reg [`ysyx_041514_TRAP_BUS] _exc_trap_bus;
  integer i;
  always @(*) begin
    for (i = 0; i < `ysyx_041514_TRAP_LEN; i = i + 1) begin
      _exc_trap_bus[i] = trap_bus_i[i];
    end
  end
  assign trap_bus_o = _exc_trap_bus;


endmodule
