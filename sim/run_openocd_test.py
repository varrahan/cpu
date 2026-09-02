#!/usr/bin/env python3
"""Run OpenOCD against the Verilated remote-bitbang server."""

import socket
import subprocess
import sys


def main():
    server_path, openocd_path, scripts = sys.argv[1:]
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    server = subprocess.Popen(
        [server_path, str(port)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        ready = server.stdout.readline().strip()
        assert ready == f"READY {port}", ready
        commands = [
            "adapter driver remote_bitbang",
            "remote_bitbang host 127.0.0.1",
            f"remote_bitbang port {port}",
            "adapter speed 1000",
            "transport select jtag",
            "jtag newtap cpu tap -irlen 5 -expected-id 0x00000001",
            "target create cpu riscv -chain-position cpu.tap",
            "init",
            "halt",
            "reg a0 0x55aa1234",
            "reg a0",
            "resume",
            "shutdown",
        ]
        command = [openocd_path, "-s", scripts]
        for item in commands:
            command += ["-c", item]
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=60)
        print(result.stdout, end="")
        assert result.returncode == 0, "OpenOCD failed"
        assert "55AA1234" in result.stdout.upper(), "GPR readback missing"
        server_output = server.communicate(timeout=10)[0]
        print(server_output, end="")
        assert server.returncode == 0, "remote-bitbang server failed"
    finally:
        if server.poll() is None:
            server.kill()
            server.wait()


if __name__ == "__main__":
    main()
