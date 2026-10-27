# Modeling scope and limitations

- **Electromagnetic:** 5.5 GHz, bistatic SBR scattering by two galvanized-steel panels; finite-conductivity metal approximations, not PEC. This is not a fully independent integral-equation/full-wave validation.
- **Structural:** 2 m class panel supported by steel profiles, three uniform design wind pressures corresponding to 15, 25 and 35 m/s. Mesh-independent peak displacements and stresses **were not demonstrated**; a mesh-level disparity remains.
- **FEM-to-RF:** Real FEM `u,v,w` is interpolated to an RF surface mesh; the deformation geometry is computationally projected rather than metrologically verified.
- **Link:** Two 500 m paths, 29 dBm EIRP, 23 dBi Rx gain, 6 dB additional loss, 7 dB NF, 20 MHz bandwidth, assumed blocked direct LOS. Figures are conditional calculations, not measured RSRP or guaranteed service.
- **Signal processing:** Uncoded QPSK/64-point OFDM with a frequency-flat AWGN channel; no MAC, channel coding, terrain fading, interference or retransmission model.
- **Physical verification:** Not performed. No certification for installation or wind loading is claimed.
