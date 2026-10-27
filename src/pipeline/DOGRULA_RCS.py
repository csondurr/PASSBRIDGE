#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Compute bistatic RCS from real CST complex farfield (9-column native format).
Reject a case unless both TE/TM fixed-RX native samples are present.
"""
import argparse,csv,math,pathlib,json
C=299792458.

def parse_native(path):
    best=None; pts=[]
    for line in path.read_text(encoding='utf-8-sig',errors='replace').splitlines():
        a=line.split()
        if len(a)!=9:continue
        try:v=[float(z) for z in a]
        except ValueError:continue
        if not all(math.isfinite(z) for z in v):continue
        f,phi_inc,theta_inc,phi,theta,*fld=v
        if abs(f-5.5)>.001 or abs(phi)>1e-4:continue
        # native already normalized by 1 V/m incident field; 4pi*E^2
        rcs=4*math.pi*sum(z*z for z in fld)
        if rcs<=0:continue
        dbsm=10*math.log10(rcs)
        pts.append((theta,dbsm))
        if best is None or abs(theta-45.)<abs(best[0]-45.):best=(theta,dbsm,f)
    if not best or abs(best[0]-45.)>.03:raise RuntimeError(f'No 5.5GHz theta=45 phi=0 native point in {path}')
    peak=max(pts,key=lambda p:p[1])
    return {'fixed_rx_rcs_dbsm':best[1],'theta_deg':best[0],'theta_cut_peak_deg':peak[0],'theta_cut_peak_dbsm':peak[1],'frequency_ghz':best[2]}

def main():
    p=argparse.ArgumentParser();p.add_argument('--root',required=True,type=pathlib.Path);p.add_argument('--complete',action='store_true');a=p.parse_args()
    rf=a.root/'03_FEM_TO_CST_RF'; rows=[]
    for case in sorted(rf.glob('FEM_W*_X*_Y*')):
        if not case.is_dir():continue
        s=case.name;import re
        match=re.match(r'FEM_W(15|25|35)_X(m?\d+(?:p\d+)?)_Y(m?\d+(?:p\d+)?)$',s)
        if not match:continue
        wind=int(match[1]);xx=float(match[2].replace('m','-').replace('p','.'));yy=float(match[3].replace('m','-').replace('p','.'))
        for pol in ('TE','TM'):
            f=case/'NATIVE'/f'{pol}.txt'
            if not f.exists():continue
            r=parse_native(f);rcs=r['fixed_rx_rcs_dbsm'];lam=C/(5.5e9)
            pr=29+23+20*math.log10(lam)+rcs-30*math.log10(4*math.pi)-40*math.log10(500.)-6
            noise=-174+10*math.log10(20e6)+7
            rows.append({'Case':s,'Wind_m_s':wind,'AX_deg':xx,'AY_deg':yy,'Pol':pol,'RCS_dBsm':round(rcs,7),'Pr_dBm':round(pr,7),'Noise_dBm':round(noise,6),'SNR_dB':round(pr-noise,7),'ThetaCutPeak_deg':r['theta_cut_peak_deg'],'ThetaCutPeak_dBsm':round(r['theta_cut_peak_dbsm'],7),'DataClass':'NATIVE_CST_SBR_FEM_DEFORMATION','SourcePath':str(f)})
    if not rows:raise RuntimeError('No valid native CST FEM-coupled cases')
    out=a.root/'04_LINK';out.mkdir(parents=True,exist_ok=True)
    with (out/'LINK_CASES.csv').open('w',newline='',encoding='utf-8-sig') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    expected=3*25*2;unique={(r['Wind_m_s'],r['AX_deg'],r['AY_deg'],r['Pol']) for r in rows}
    summaries=[]
    for wind in (15,25,35):
        for pol in ('TE','TM'):
            sub=[r for r in rows if r['Wind_m_s']==wind and r['Pol']==pol]
            if not sub:continue
            worst=min(sub,key=lambda v:v['Pr_dBm'])
            nominal=[r for r in sub if r['AX_deg']==0. and r['AY_deg']==0.]
            summaries.append({'Wind_m_s':wind,'Pol':pol,'N_cases':len(sub),'Nominal_Pr_dBm':nominal[0]['Pr_dBm'] if nominal else '','Worst_Pr_dBm':worst['Pr_dBm'],'Worst_AX_deg':worst['AX_deg'],'Worst_AY_deg':worst['AY_deg'],'Worst_SNR_dB':worst['SNR_dB'],'Worst_ThetaCutPeak_deg':worst['ThetaCutPeak_deg'],'ScenarioMargin_vs_minus80_dB':round(worst['Pr_dBm']+80,5)})
    with (out/'WORST_CASES.csv').open('w',newline='',encoding='utf-8-sig') as f:
        w=csv.DictWriter(f,fieldnames=list(summaries[0]));w.writeheader();w.writerows(summaries)
    info={'success_native_pol_cases':len(unique),'expected_native_pol_cases':expected,'complete':len(unique)==expected,'source':'CST native complex scattered field, not COMSOL fullwave or field measurement','link_assumptions':{'EIRP_dBm':29,'Gr_dBi':23,'R1_m':500,'R2_m':500,'external_loss_dB':6,'NF_dB':7,'bandwidth_Hz':20e6}}
    (out/'RF_VALIDATION.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
    print(json.dumps(info))
    if a.complete and len(unique)!=expected:raise RuntimeError(f'Only {len(unique)}/{expected} TE/TM link cases completed. Resume CST before MATLAB.')
if __name__=='__main__':main()
