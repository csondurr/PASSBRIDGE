#!/usr/bin/env python3
"""Self-contained HTML/Markdown report from validated actual outputs only."""
import argparse,csv,json,html,math,pathlib,re,datetime

def rows(path):
    if not path.exists():return []
    with path.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def get_quality(path):
    if not path.exists():return {}
    txt=path.read_text(encoding='utf-8-sig',errors='replace')
    pat=r'Minimum element quality:\s*([0-9.+Ee-]+).*?PASSBRIDGE \| MESH_BUILT size=(\d+)'
    return {int(m.group(2)):float(m.group(1)) for m in re.finditer(pat,txt,re.S)}
def n(v,d=5):
    try:return f'{float(v):.{d}f}'
    except:return '—'
def tofloat(v):
    try:return float(v)
    except:return math.nan

def make(root,fem):
    rdir=root/'06_RAPOR';rdir.mkdir(parents=True,exist_ok=True)
    baseline=rows(fem/'FEM_RESULTS.csv');refined=rows(root/'02_FEM_REFINEMENT'/'REFINED_FEM_RESULTS.csv');allrows=baseline+refined
    fm={(int(z['mesh_size']),int(z['windspeed_m_s'])):z for z in allrows}
    q=get_quality(fem/'COMSOL_RUN_LOG.txt');q.update(get_quality(root/'02_FEM_REFINEMENT'/'COMSOL_REFINEMENT_LOG.txt'))
    cmp=[]
    for wind in (15,25,35):
        for mesh in (7,6,5,4):
            x=fm.get((mesh,wind))
            if not x:continue
            prev=fm.get((mesh+1,wind))
            dd=(abs(tofloat(x['max_displacement_mm'])-tofloat(prev['max_displacement_mm']))/abs(tofloat(x['max_displacement_mm']))*100) if prev and tofloat(x['max_displacement_mm']) else math.nan
            sd=(abs(tofloat(x['max_mises_MPa'])-tofloat(prev['max_mises_MPa']))/abs(tofloat(x['max_mises_MPa']))*100) if prev and tofloat(x['max_mises_MPa']) else math.nan
            cmp.append({'Wind_m_s':wind,'Mesh':mesh,'MaxDisp_mm':x['max_displacement_mm'],'MaxMises_MPa':x['max_mises_MPa'],'MeshMinQuality':q.get(mesh,''),'PreviousToCurrent_DispChangePct':dd,'PreviousToCurrent_StressChangePct':sd})
    if cmp:
        with (rdir/'MESH_QA.csv').open('w',encoding='utf-8-sig',newline='') as f:
            w=csv.DictWriter(f,fieldnames=list(cmp[0]));w.writeheader();w.writerows(cmp)
    link=rows(root/'04_LINK'/'WORST_CASES.csv')
    modem=rows(root/'05_MATLAB_OFDM'/'MATLAB_OFDM_RESULTS.csv')
    rfinfo={}
    f=root/'04_LINK'/'RF_VALIDATION.json'
    if f.exists():rfinfo=json.loads(f.read_text(encoding='utf-8'))
    geom=[]
    for f in sorted((root/'03_FEM_STL').glob('W*/FEM_GEOMETRY_MANIFEST.json')):
        geom.append(json.loads(f.read_text(encoding='utf-8')))
    emcomplete=rfinfo.get('complete',False) and len(modem)>=13
    # Mesh QA cannot be declared converged from mere solver convergence.
    mesh_valid=True; mesh_checks=[]
    for wind in (15,25,35):
        a=fm.get((4,wind));b=fm.get((5,wind))
        if not a or not b: mesh_valid=False;mesh_checks.append(f'W{wind}: mesh4 unavailable');continue
        d=abs(tofloat(a['max_displacement_mm'])-tofloat(b['max_displacement_mm']))/max(1e-20,abs(tofloat(a['max_displacement_mm'])))
        s=abs(tofloat(a['max_mises_MPa'])-tofloat(b['max_mises_MPa']))/max(1e-20,abs(tofloat(a['max_mises_MPa'])))
        ok=d<=0.03 and s<=0.05
        mesh_checks.append(f'W{wind}: displacement {d*100:.2f}%, stress {s*100:.2f}%, {"screen passed" if ok else "not converged"}')
        if not ok:mesh_valid=False
    # Very low mesh minimum quality triggers explicit caveat even if integral metrics converge.
    geom_warning=min(q.values())<0.01 if q else True
    state='END_TO_END_SIMULATED_WITH_NUMERICAL_CAVEATS' if emcomplete else 'PARTIAL_END_TO_END_RESULTS'
    notes=[
      'PASSBRIDGE G1 / numerical digital-twin evidence only',
      'CST model uses two finite-conductivity DX51D+Z275 sheets; COMSOL structural steel law is provisional.',
      'FEM front-surface u,v,w sampled and IDW-interpolated into closed finite-thickness RF solids.',
      'Wind is uniform pressure from a simplified force coefficient, not a code-prescribed site load.',
      'Finite-height / 2D beam support and true welded/bolted joint stiffness are not independently certified.',
      'Only 5.5 GHz field data drive the flat AWGN channel; not 802.11 MAC or measured throughput.',
      'No-reflector is modeled with blocked direct path; alternate multipath not simulated.',
      'Fullwave IE, actual site measurements, material test reports, and production certification are OUTSIDE this digital acceptance stage.'
    ]
    lines=['# PASSBRIDGE — NIHAI DIJITAL SİMÜLASYON RAPORU',f'Durum: **{state}**',f'Tarih: {datetime.datetime.now().isoformat(timespec="seconds")}', '',
           f'CST FEM-birleşik RF koşulları: **{rfinfo.get("success_native_pol_cases",0)}/{rfinfo.get("expected_native_pol_cases",150)}** kutuplanma dosyası',
           f'MATLAB OFDM koşulları: **{len(modem)}**', f'Mesh yakınsama kontrolü: **{"Geçti" if mesh_valid else "Henüz tamam değil"}**',
           f'Minimum eleman kalitesi uyarısı: **{"Var" if geom_warning else "Kayıt yok veya eşik üstü"}**', '', '## Mesh analizi']
    lines += ['| W (m/s) | Mesh | Maks. depl. (mm) | Maks. Mises (MPa) | Min. kalite | Δdepl. % | Δgerilme % |','|---:|---:|---:|---:|---:|---:|---:|']
    for t in cmp:lines.append('| '+ ' | '.join([str(t['Wind_m_s']),str(t['Mesh']),n(t['MaxDisp_mm'],5),n(t['MaxMises_MPa'],4),n(t['MeshMinQuality'],6),n(t['PreviousToCurrent_DispChangePct'],2),n(t['PreviousToCurrent_StressChangePct'],2)])+' |')
    lines += ['', '## Gerçek FEM deformasyonuyla CST SBR / bağlantı', '| W | Pol | N | Nominal dBm | En kötü dBm | AX | AY | En kötü SNR |','|---:|:---:|---:|---:|---:|---:|---:|---:|']
    for t in link:lines.append('| '+' | '.join([str(t[k]) for k in ('Wind_m_s','Pol','N_cases','Nominal_Pr_dBm','Worst_Pr_dBm','Worst_AX_deg','Worst_AY_deg','Worst_SNR_dB')])+' |')
    lines+=['','## MATLAB 20 MHz OFDM','| W | Pol | Durum | SNR dB | BER | PER | Veri hızı Mbit/s |','|---:|:---:|:---|---:|---:|---:|---:|']
    for t in modem:
        lines.append('| '+' | '.join([str(t.get(k,'')) for k in ('Wind_m_s','Pol','Scenario','SNR_dB','BER','PER','Net_Mbps')])+' |')
    lines+=['','## Sınırlar']+['- '+x for x in notes]+['','## Mesh kontrolü']+['- '+x for x in mesh_checks]
    report='\n'.join(lines)
    (rdir/'PASSBRIDGE_DIGITAL_FINAL.md').write_text(report,encoding='utf-8')
    # Simple HTML without additional Python packages
    import html
    def tgen(data,keys):
        if not data:return '<p>Veri yok</p>'
        return '<table><thead><tr>'+''.join('<th>'+html.escape(k)+'</th>' for k in keys)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(n(row.get(k,''),5) if isinstance(row.get(k),float) else str(row.get(k,'')))+'</td>' for k in keys)+'</tr>' for row in data)+'</tbody></table>'
    style='body{font:15px Segoe UI,Arial,sans-serif;color:#1b2838;max-width:1180px;margin:32px auto;padding:0 22px;line-height:1.6}h1,h2{color:#163653}table{border-collapse:collapse;width:100%;font-size:13px;margin:14px 0 27px}td,th{border:1px solid #cfdae7;padding:8px 9px;text-align:right}th{background:#eaf1f9}td:first-child,th:first-child{text-align:left}.summary{font-size:16px;background:#f1f5fa;padding:18px;border-radius:8px}.warning{color:#a3422a}li{margin:4px 0}img{max-width:90%;border:1px solid #ddd}'
    h='<html lang="tr"><head><meta charset="utf-8"><title>PASSBRIDGE digital final</title><style>'+style+'</style></head><body>'
    h+='<h1>PASSBRIDGE — Dijital Simülasyon Sonuçları</h1><div class="summary"><b>Durum:</b> '+html.escape(state)+'<p>Gerçek CST native FEM-RF: '+str(rfinfo.get('success_native_pol_cases',0))+'/150; MATLAB OFDM: '+str(len(modem))+' koşul</p></div>'
    h+='<h2>Yapısal FEM mesh kontrolü</h2>'+tgen(cmp,['Wind_m_s','Mesh','MaxDisp_mm','MaxMises_MPa','MeshMinQuality','PreviousToCurrent_DispChangePct','PreviousToCurrent_StressChangePct'])
    h+='<h2>FEM→CST RCS ve bağlantı</h2>'+tgen(link,['Wind_m_s','Pol','N_cases','Nominal_Pr_dBm','Worst_Pr_dBm','Worst_AX_deg','Worst_AY_deg','Worst_SNR_dB'])
    h+='<h2>MATLAB OFDM</h2>'+tgen(modem,['Wind_m_s','Pol','Scenario','SNR_dB','BER','PER','Net_Mbps'])
    for im in ('OFDM_THROUGHPUT.png','OFDM_SNR.png'):
        src=root/'05_MATLAB_OFDM'/im
        if src.exists():h+='<p><img src="../05_MATLAB_OFDM/'+im+'" alt="'+im+'"></p>'
    h+='<h2>Belirlenmiş model sınırları</h2><ul>'+''.join('<li>'+html.escape(x)+'</li>' for x in notes)+'</ul>'
    h+='<h2>Mesh yakınsama kriteri</h2><ul>'+''.join('<li>'+html.escape(x)+'</li>' for x in mesh_checks)+'</ul></body></html>'
    (rdir/'PASSBRIDGE_DIGITAL_FINAL.html').write_text(h,encoding='utf-8')
    final={'digital_pipeline_complete':emcomplete,'mesh_screen_passed':mesh_valid,'low_quality_mesh_warning':geom_warning,'reported_status':state,'notes':notes}
    (rdir/'FINAL_STATUS.json').write_text(json.dumps(final,indent=2,ensure_ascii=False),encoding='utf-8')
    print(json.dumps(final,ensure_ascii=False))

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--root',type=pathlib.Path,required=True);ap.add_argument('--fem-root',type=pathlib.Path,required=True)
    a=ap.parse_args();make(a.root,a.fem_root)
