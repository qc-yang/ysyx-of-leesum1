#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <verilated.h>
#include <Vtop.h>
#include "verilated_vcd_c.h"
#include "simtop.h"
#include "cppreadline/Console.hpp"
#include "mysdb.h"
#include "simMem.h"

namespace cr = CppReadline;
using ret = cr::Console::ReturnCode;



const char* nemu_so_path = "/lib/libnemu.so";

Simtop* mysim_p;
int main() {
  /* 不知道为什么将 Simtop mysim 声明为全局变量会崩溃*/
  mysim_p = new Simtop;


  static Vtop* top = mysim_p->getTop();
  uint32_t imgsize = mysim_p->mem->getImgSize(mysim_p->mem->imgpath);
  cout << "testsizd:" << imgsize << endl;
  mysim_p->reset();
  mysim_p->u_difftest.init(nemu_so_path, imgsize, 0);
  /* 注册命令 */
  cr::Console c(">:");
  c.registerCommand("info", cmd_info);
  c.registerCommand("x", cmd_x);
  c.registerCommand("si", cmd_si);
  c.registerCommand("c", cmd_c);
  c.registerCommand("p", cmd_p);
  c.registerCommand("help", cmd_help);
  c.registerCommand("w", cmd_w);
  int retCode;
  do {
    retCode = c.readLine();
    // We can also change the prompt based on last return value:
    if (retCode == ret::Ok)
      c.setGreeting(">");
    else
      c.setGreeting("!>");

    if (retCode == 1) {
      std::cout << "Received error code 1\n";
    }
    else if (retCode == 2) {
      std::cout << "Received error code 2\n";
    }
  } while (retCode != ret::Quit);
  mysim_p->npcTrap();
  return 0;
}

// //声明
// static Vtop* top;
// int main(int argc, char** argv, char** env) {

//   Simtop mysim;
//   top = mysim.getTop();
//   int i = 50;
//   mysim.reset();
//   while (!top->contextp()->gotFinish()) {
//     mysim.stepCycle();
//   }
//   mysim.npcTrap();
// }



