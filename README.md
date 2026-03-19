# SIR: Sparse-Interaction Keystream Generator

## Overview

This repository provides the reference implementation of the **SIR (Sparse Interaction Register)** keystream generator, a lightweight stream generation architecture designed for hardware-efficient cryptographic applications.

The SIR design explores an alternative paradigm to traditional shift-register-based stream ciphers by employing **sparse nonlinear interaction among state variables**, enabling:

- rapid internal diffusion  
- compact hardware footprint  
- reduced sequential storage requirements  

This repository accompanies the research article:

> **"SIR: A Sparse-Interaction Keystream Generator with a Hardware-Oriented Architecture"**  
> Submitted to *AEU – International Journal of Electronics and Communications*

---

## Repository Structure


### sir-keystream-generator

**Python**
- sir_reference_model.py
- sir_generate_test_vectors.py

**Verilog rtl**
- sir_core.v
- sir_xor_wrapper.v

**Verilog tb**
- tb_sir_core.v
- tb_sir_xor_wrapper.v

**test vectors**
- sir_test_vectors.csv
- sir_test_vectors.txt

README.md



---

## Design Summary

The SIR keystream generator consists of:

- a **nonlinear primary state** updated via sparse local interaction  
- an **auxiliary linear register** providing perturbation  
- a **uniform Boolean update rule** enabling parallel combinational mixing  

Unlike traditional LFSR/NFSR-based designs, SIR shifts the design focus from sequential propagation to **parallel interaction-driven diffusion**.

---

## Python Reference Model

The Python model provides:

- a golden reference implementation  
- deterministic keystream generation  
- test vector generation  

### Run:



```cd python```
```python sir_generate_test_vectors.py```



### Outputs:

- `sir_test_vectors.csv`  
- `sir_test_vectors.txt`  

---

## Verilog Implementation

The RTL implementation is written in **Verilog-2005** and targets lightweight FPGA/ASIC realization.

### Key modules:

- `sir_core.v`  
  Core keystream generator  

- `sir_xor_wrapper.v`  
  Stream encryption/decryption interface  

---

## Verification

Testbenches validate the RTL implementation against Python-generated reference vectors.

### Typical flow:

1. Generate vectors using Python  
2. Run Verilog simulation  
3. Compare outputs  

---

## Hardware Characteristics

The architecture is designed for:

- low LUT utilization  
- reduced flip-flop count  
- efficient FPGA mapping  
- balanced combinational vs sequential logic  

---

## Disclaimer

This implementation is intended for:

- research  
- evaluation  
- academic study  

It is **not a standardized or production-ready cipher** and should not be used for real-world security-critical applications without further analysis.

---

## Author

Dr. W. A. S. Wijesinghe  
Department of Electronics  
Wayamba University of Sri Lanka  

---




