# NeuroProc_prototype

Prototype of Tensor neural processor for CNN processing acceleration

## Repo structure

`/doc` - documentation files for used libraries and useful information files

`/src` - source files of neural processor modules

`/tb` - testbench files for testing neural processor modules in a simulation environment

`/xc7a100tcsg324_project` - Xilinx Vivado project for xc7a100tcsg324 FPGA

`/xc7a100tcsg324_project/waveform_cfg` - Xilinx Vivado waveform configuration files for all testbenches

## Simulation instruction

Xilinx Vivado CAD verison required: v2019.1 (64-bit)

1. Download and install Xilinx Vivado CAD
2. Open Vivado project `/xc7a100tcsg324_project/xc7a100tcsg324_project.xpr`
3. Select necessary testbench file and "Set as top"
4. Start "Behavioral Simulation"
5. The test results are displayed in the TCL console
