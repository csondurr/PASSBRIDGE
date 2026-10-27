# Reproducibility and source provenance

The published `src/` code comes from the documented COMSOL -> FEM displacement -> CST SBR -> MATLAB workflow. The CST runner is the corrected edition where PowerShell uses `-lt` instead of `<`.

### Prerequisites

- COMSOL Multiphysics 6.4 with the relevant structural modules and compatible license
- CST Studio Suite 2025 and its SBR solver
- MATLAB R2025b
- Python >= 3.10
- The original CST master geometry and sufficient COMSOL model/displacement data

### Typical steps (not a turnkey invocation)

1. Build/inspect the structural model using `src/pipeline/PASSBRIDGE_G1_FEM.java` and inspect `results/fem/`.
2. Export genuine `u,v,w` displacement tables; do not create synthetic displacement fields.
3. Generate finite-thickness STL layers using `src/pipeline/FEMDEN_STL.py` and examine the geometry manifest.
4. Run CST SBR using `src/pipeline/CST_FEM_RF.ps1` with a properly configured local installation and master `.cst` file.
5. Verify native TE and TM fields with `src/pipeline/DOGRULA_RCS.py`, then evaluate communication using `src/pipeline/MATLAB_OFDM.m`.

The original automation was tied to specific Windows file paths and installed CAD/solver automation APIs, so reproducing on another machine may require integration edits. Large binaries may be omitted by design. See `PUBLICATION_AUDIT.txt` and `SHA256_MANIFEST.csv`.

The supplied digital results demonstrate feasibility **only under declared assumptions**. The structural mesh does not pass convergence and should not be represented as a certified load-bearing design.
