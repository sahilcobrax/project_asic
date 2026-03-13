# Design of High-Performance and Area-Efficient Decoder for 5G LDPC Codes

**Course:** VLS822 - Physical Design of ASICs  
**Instructor:** Dr. Anuj Verma  
**Team Members:** Sahil Singh, Shrujan Teja, Rajdeep Saha, Suhas Nagabandi, Nachiappan N  
**Optimization Target:** Area Efficiency  

---

## Project Overview
This repository contains the RTL design, verification, and physical synthesis flow for a 5G Low-Density Parity-Check (LDPC) decoder. The project is based on the IEEE paper *"Design of High-Performance and Area-Efficient Decoder for 5G LDPC Codes"* by Hangxuan Cui et al. 

The ultimate goal of this project is to transition from algorithmic specification to a physical GDSII layout, implementing specific architectural optimizations to significantly reduce the silicon area consumption required for 5G New Radio (NR) baseband processing.

---

## Midterm Evaluation: Baseline Implementation
For the midterm phase, we have successfully developed, simulated, and synthesized the **unoptimized baseline architecture** of the LDPC decoder to establish a verified functional datapath.

### Key Midterm Features:
* **Algorithmic Foundation:** Implementation of the **Improved Adapted Min-Sum (IAMS)** algorithm within the Check Node Units (CNUs) to enhance the reliability of Check-to-Variable (CTV) messages, protecting fragile degree-1 variable nodes.
* **Hardware Architecture:** A standard layered decoding pipeline consisting of an APP Memory, Variable Node Units (VNUs), CNUs, and a CTV Memory.
* **Functional Verification:** Complete behavioral simulation of the decoding process, successfully correcting noisy LLR inputs (Verified via Icarus Verilog & GTKWave).
* **Logic Synthesis:** The baseline RTL has been successfully synthesized and mapped to the **SkyWater 130nm** open-source standard cell library (`sky130_fd_sc_hd__tt_025C_1v80.lib`), generating a complete gate-level netlist.

### Repository Structure
* `/sky130RTLDesignAndSynthesisWorkshop/verilog_files/`
  * `LDPC_modified_fixed.v`: Top-level baseline decoder RTL and sub-modules.
  * `LDPC_test.vh`: Testbench for module-wise and top-level verification.
  * `run_synth.ys`: Yosys batch script for reproducible synthesis.
  * `/Midterm_Screenshots/`: GTKWave simulation waveforms and terminal execution logs.
  * `/Synthesis_Outputs/`: Gate-level netlist (`ldpc_baseline_netlist.v`) and schematic diagrams.
  * `/Hardware_Architecture/`: Block diagrams of the implemented RTL datapath.

### Toolchain
* **Simulation & Linting:** Icarus Verilog (`iverilog`)
* **Waveform Visualization:** GTKWave
* **Logic Synthesis:** Yosys

---

## Endterm Roadmap: Area Optimization & Physical Design
With the baseline functional and synthesized, the second half of the project will focus on modifying the RTL to implement the paper's proposed area optimizations, followed by routing the design to a final GDSII layout.

1. **Layer Merging Integration:** * Modifying the Check Node Units and Controller to process two orthogonal layers (e.g., rows 21–42 of BG2) simultaneously.
   * *Target:* ~26% reduction in decoding latency and associated control logic area.
2. **Split Storage Method for CTV Memory:**
   * Redesigning the standard CTV memory into a dual-structure (CTV Memory 1 & 2) customized to the irregular degree distribution of the 5G base graph.
   * *Target:* ~29.8% reduction in memory area consumption.
3. **Selective-Shift Structure:**
   * Replacing massive, area-heavy read/write crossbar networks with optimized cyclic shift registers for routing APP messages.
4. **Physical Design (RTL-to-GDSII):**
   * Pushing the final, optimized netlist through the open-source **OpenROAD / OpenLane** flow.
   * Steps will include Floorplanning, Placement, Clock Tree Synthesis (CTS), Routing, and passing Design Rule Checks (DRC) and Layout Versus Schematic (LVS) verification.
