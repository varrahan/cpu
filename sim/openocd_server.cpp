#include "Vtop_jtag.h"
#include "verilated.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstdlib>
#include <iostream>

static void core_cycle(Vtop_jtag &top) {
    top.clk = 0;
    top.eval();
    top.clk = 1;
    top.eval();
    top.clk = 0;
    top.eval();
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const int port = argc > 1 ? std::atoi(argv[1]) : 9824;
    Vtop_jtag top;
    top.rst_n = 0;
    top.trst_n = 0;
    top.tck = 0;
    top.tms = 1;
    top.tdi = 0;
    top.irq_m_software = 0;
    top.irq_m_timer = 0;
    top.irq_m_external = 0;
    top.irq_s_software = 0;
    top.irq_s_timer = 0;
    top.irq_s_external = 0;
    top.nmi = 0;
    top.imem_req_ready = 1;
    top.imem_rsp_valid = 1;
    top.imem_rsp_rdata = 0x00000013;
    top.imem_rsp_error = 0;
    top.dmem_req_ready = 1;
    top.dmem_rsp_valid = 1;
    top.dmem_rsp_rdata = 0;
    top.dmem_rsp_error = 0;
    top.reservation_invalidate = 0;
    for (int i = 0; i < 8; ++i)
        core_cycle(top);
    top.rst_n = 1;
    top.trst_n = 1;

    const int listener = socket(AF_INET, SOCK_STREAM, 0);
    int reuse = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(port);
    if (bind(listener, reinterpret_cast<sockaddr *>(&address), sizeof(address)) ||
        listen(listener, 1)) {
        std::perror("remote-bitbang listen");
        return 1;
    }
    std::cout << "READY " << port << std::endl;
    const int client = accept(listener, nullptr, nullptr);
    if (client < 0) {
        std::perror("remote-bitbang accept");
        return 1;
    }

    bool saw_halt = false;
    bool saw_resume = false;
    bool quit = false;
    char buffer[512];
    while (!quit) {
        const ssize_t count = read(client, buffer, sizeof(buffer));
        if (count <= 0)
            break;
        for (ssize_t i = 0; i < count; ++i) {
            const char command = buffer[i];
            if (command >= '0' && command <= '7') {
                const int pins = command - '0';
                top.tck = (pins >> 2) & 1;
                top.tms = (pins >> 1) & 1;
                top.tdi = pins & 1;
                top.eval();
            } else if (command == 'R') {
                const char response = top.tdo ? '1' : '0';
                if (write(client, &response, 1) != 1)
                    return 1;
            } else if (command >= 'r' && command <= 'u') {
                const int resets = command - 'r';
                top.rst_n = !(resets & 1);
                top.trst_n = !(resets & 2);
                top.eval();
            } else if (command == 'Q') {
                quit = true;
            }
            core_cycle(top);
            core_cycle(top);
            saw_halt |= top.debug_halted;
            saw_resume |= saw_halt && !top.debug_halted;
        }
    }
    close(client);
    close(listener);
    top.final();
    if (!saw_halt || !saw_resume) {
        std::cerr << "Debugger did not complete halt/resume" << std::endl;
        return 1;
    }
    std::cout << "PASS: external OpenOCD halt/register/resume" << std::endl;
    return 0;
}
