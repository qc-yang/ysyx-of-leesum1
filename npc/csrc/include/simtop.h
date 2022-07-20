#ifndef  __SIMTOP_H__
#define __SIMTOP_H__

#include <iostream>
#include <verilated_vcd_c.h>
#include <verilated.h>
#include <Vtop.h>
#include <iomanip>
#include "verilated_dpi.h"
#include "simMem.h"
#include "watchpoint.h"
#include "expr.h"
#include "difftest.h"

extern uint64_t* cpu_gpr;
extern uint64_t cpu_pc;

class Simtop {
private:
    Vtop* top;

    VerilatedContext* contextp;
    VerilatedVcdC* tfp;
    uint64_t* registerfile;
    uint64_t pc;

private:
    void stepCycle(bool val);
    const char* getRegName(int idx);
    void changeCLK();
    void dampWave();
public:
    uint32_t top_status;
    enum {
        TOP_STOP,
        TOP_RUNNING
    };
    SimMem* mem;
    Watchpoint u_wp;
    expr_namespace::Expr u_expr;
    Difftest u_difftest;
    Simtop();
    ~Simtop();
    Vtop* getTop();
    void reset();
    int npcTrap();
    uint64_t getRegVal(int idx);
    uint64_t getRegVal(const char* str);
    void printRegisterFile();
    void scanMem(paddr_t addr, uint32_t len);
    void excute(int32_t t);
    void excute();
};

#endif