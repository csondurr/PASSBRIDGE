# PASSBRIDGE — NIHAI DIJITAL SİMÜLASYON RAPORU
Durum: **END_TO_END_SIMULATED_WITH_NUMERICAL_CAVEATS**
Tarih: 2026-10-26T19:50:35

CST FEM-birleşik RF koşulları: **150/150** kutuplanma dosyası
MATLAB OFDM koşulları: **13**
Mesh yakınsama kontrolü: **Henüz tamam değil**
Minimum eleman kalitesi uyarısı: **Var**

## Mesh analizi
| W (m/s) | Mesh | Maks. depl. (mm) | Maks. Mises (MPa) | Min. kalite | Δdepl. % | Δgerilme % |
|---:|---:|---:|---:|---:|---:|---:|
| 15 | 7 | 0.03803 | 5.2475 | 0.000011 | nan | nan |
| 15 | 6 | 0.05042 | 7.1203 | 0.003286 | 24.57 | 26.30 |
| 15 | 5 | 0.05393 | 6.9352 | 0.000414 | 6.51 | 2.67 |
| 15 | 4 | 0.15304 | 9.7202 | 0.004494 | 64.76 | 28.65 |
| 25 | 7 | 0.10565 | 14.5763 | 0.000011 | nan | nan |
| 25 | 6 | 0.14005 | 19.7785 | 0.003286 | 24.57 | 26.30 |
| 25 | 5 | 0.14980 | 19.2643 | 0.000414 | 6.51 | 2.67 |
| 25 | 4 | 0.42512 | 27.0007 | 0.004494 | 64.76 | 28.65 |
| 35 | 7 | 0.20707 | 28.5696 | 0.000011 | nan | nan |
| 35 | 6 | 0.27450 | 38.7659 | 0.003286 | 24.57 | 26.30 |
| 35 | 5 | 0.29361 | 37.7580 | 0.000414 | 6.51 | 2.67 |
| 35 | 4 | 0.83323 | 52.9213 | 0.004494 | 64.76 | 28.65 |

## Gerçek FEM deformasyonuyla CST SBR / bağlantı
| W | Pol | N | Nominal dBm | En kötü dBm | AX | AY | En kötü SNR |
|---:|:---:|---:|---:|---:|---:|---:|---:|
| 15 | TE | 25 | -74.8904183 | -75.8834231 | -0.2 | 0.2 | 18.106277 |
| 15 | TM | 25 | -74.9058516 | -75.897457 | -0.2 | -0.2 | 18.0922431 |
| 25 | TE | 25 | -74.8923712 | -75.8838523 | -0.2 | 0.2 | 18.1058478 |
| 25 | TM | 25 | -74.9055319 | -75.898279 | -0.2 | -0.2 | 18.0914211 |
| 35 | TE | 25 | -74.8946478 | -75.8858271 | -0.2 | 0.2 | 18.103873 |
| 35 | TM | 25 | -74.9470267 | -75.9011103 | -0.2 | -0.2 | 18.0885897 |

## MATLAB 20 MHz OFDM
| W | Pol | Durum | SNR dB | BER | PER | Veri hızı Mbit/s |
|---:|:---:|:---|---:|---:|---:|---:|
| 15 | TE | ALIGNED | 19.0992818 | 0 | 0 | 26 |
| 15 | TE | WORST_TILT | 18.106277 | 0 | 0 | 26 |
| 15 | TM | ALIGNED | 19.0838485 | 0 | 0 | 26 |
| 15 | TM | WORST_TILT | 18.0922431 | 0 | 0 | 26 |
| 25 | TE | ALIGNED | 19.0973289 | 0 | 0 | 26 |
| 25 | TE | WORST_TILT | 18.1058478 | 0 | 0 | 26 |
| 25 | TM | ALIGNED | 19.0841682 | 0 | 0 | 26 |
| 25 | TM | WORST_TILT | 18.0914211 | 0 | 0 | 26 |
| 35 | TE | ALIGNED | 19.0950523 | 0 | 0 | 26 |
| 35 | TE | WORST_TILT | 18.103873 | 0 | 0 | 26 |
| 35 | TM | ALIGNED | 19.0426733 | 0 | 0 | 26 |
| 35 | TM | WORST_TILT | 18.0885897 | 0 | 0 | 26 |
| 0 | NA | NO_REFLECTOR_BLOCKED_LOS | NaN | 0.498554258241758 | 1 | 0 |

## Sınırlar
- PASSBRIDGE G1 / numerical digital-twin evidence only
- CST model uses two finite-conductivity DX51D+Z275 sheets; COMSOL structural steel law is provisional.
- FEM front-surface u,v,w sampled and IDW-interpolated into closed finite-thickness RF solids.
- Wind is uniform pressure from a simplified force coefficient, not a code-prescribed site load.
- Finite-height / 2D beam support and true welded/bolted joint stiffness are not independently certified.
- Only 5.5 GHz field data drive the flat AWGN channel; not 802.11 MAC or measured throughput.
- No-reflector is modeled with blocked direct path; alternate multipath not simulated.
- Fullwave IE, actual site measurements, material test reports, and production certification are OUTSIDE this digital acceptance stage.

## Mesh kontrolü
- W15: displacement 64.76%, stress 28.65%, not converged
- W25: displacement 64.76%, stress 28.65%, not converged
- W35: displacement 64.76%, stress 28.65%, not converged