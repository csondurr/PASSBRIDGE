# PASSBRIDGE

**Passive microwave reflector for a conditional 5.5 GHz non-line-of-sight radio link — engineering simulation study.**

PASSBRIDGE investigates a **2 × 2 m** passive galvanized-steel panel for redirecting a 5.5 GHz microwave link. The modeled geometry consists of two approximately 999 × 2000 mm sheets and a 2 mm center seam. The reference link contains two 500 m segments and a nominal 90° propagation deflection. Electromagnetic analysis is performed in **CST Studio Suite** using an SBR solver, structural wind loading is modeled in **COMSOL**, and a **MATLAB** QPSK-OFDM simulation evaluates a simplified baseband link.

## Reported simulation results

| Metric | Reported result | Interpretation |
|---|---:|---|
| CST geometry/horizontal/vertical tilt combinations | 75 completed | Simulated conditions only |
| Polarization records | 150 TE/TM | Native CST fields were used to compute link results |
| Worst calculated received power | approximately -75.90 dBm | Depends on assumed EIRP, RX gain, path lengths and losses |
| Reference received-power threshold | -77 dBm | Scenario-defined screening target, **not** a certified sensitivity limit |
| Modeled QPSK-OFDM rate | 26 Mbit/s | PHY calculation, **not measured Wi-Fi throughput** |
| Reported MATLAB communication conditions | 13 | The test observed no errors in the stated finite trials |

The reported RF assumptions are **29 dBm EIRP, 23 dBi receive gain, 6 dB additional loss, 7 dB receiver noise figure, and 20 MHz channel bandwidth**. See [`docs/SIMULATION_ASSUMPTIONS.txt`](docs/SIMULATION_ASSUMPTIONS.txt), [`results/rf/RF_VALIDATION.json`](results/rf/RF_VALIDATION.json) and [`results/reports/PASSBRIDGE_DIGITAL_FINAL.md`](results/reports/PASSBRIDGE_DIGITAL_FINAL.md).

## Critical limitations

**This is a numerical feasibility study, not a field-proven product.** No physical prototype, measured link budget, real antenna pattern, real terrain model, multipath characterization, construction approval or structural safety certification is claimed. The FEM **mesh-convergence screen failed**: a finer discretization produced a substantial change in maximum displacement; very poor minimum element quality was reported. Steel properties, Zn layer properties, mounting stiffness and uniform wind loads are provisional modeling assumptions. Consequently, RF sensitivity to *exact* structural deflection has unresolved numerical uncertainty. The 20 MHz MATLAB link uses a frequency-flat AWGN assumption; it is not a full 802.11 stack or real WLAN throughput prediction.

## Repository contents

- [`src/`](src/): COMSOL Java, CST PowerShell, MATLAB and Python modeling/analysis sources; the PowerShell CST script contains the corrected comparison operator used for the successful simulation campaign.
- [`results/fem/`](results/fem/): structural summary results and mesh-quality screen.
- [`results/rf/`](results/rf/): case-by-case received-power results, CST run index and optional native TE/TM outputs.
- [`results/communication/`](results/communication/): OFDM results and plots.
- [`results/reports/`](results/reports/): original machine-generated technical findings and status.
- [`models/`](models/), [`data/`](data/): only **size-qualified** native design files and FEM displacement exports, if found on the originating machine.
- [`docs/PUBLICATION_AUDIT.txt`](docs/PUBLICATION_AUDIT.txt): list of missing or intentionally excluded assets; check this **before** claiming complete reproducibility.

## Reproducing the numerical study

The analysis sources require **COMSOL Multiphysics 6.4, CST Studio Suite 2025, MATLAB R2025b and Python 3.10+**. Paths and licensing differ by computer; scripts may need paths adjusted. See [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md). Do **not** treat these files as a validated one-click unattended build. Raw CST model binaries and COMSOL model binaries may be withheld from Git if they exceed regular Git size limits; that constraint is explicitly documented in the audit.

## Data integrity and publication

Files in `results/` are the actual submitted results of the completed simulation campaign, not fabricated or recomputed during repository packaging. The Windows curation script prioritizes available native local files where relevant and keeps a SHA-256 inventory. GitHub publishing is a separate, manual step: inspect names, contents and the audit before pushing.

**License:** No reuse license has been assigned by the project owner. You can add one if you wish to authorize public reuse.
