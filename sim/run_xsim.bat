@echo off
rem Compile and run the testbench with the Vivado simulator (xsim).
rem Run from this folder. Adjust VIVADO if your install path differs.
set VIVADO=C:\Xilinx\2025.1\Vivado\bin

call %VIVADO%\xvlog.bat ..\rtl\sync_2ff.v ..\rtl\fifo_mem.v ..\rtl\wptr_full.v ..\rtl\rptr_empty.v ..\rtl\async_fifo.v ..\tb\tb_async_fifo.v || exit /b 1
call %VIVADO%\xelab.bat tb_async_fifo -s fifo_sim -debug typical || exit /b 1
call %VIVADO%\xsim.bat fifo_sim -R
