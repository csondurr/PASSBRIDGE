% PASSBRIDGE: real CST FEM-coupled RCS -> 20 MHz uncoded OFDM link model.
% No Communications Toolbox required. This is NOT IEEE 802.11 throughput or field BER.
% Direct LOS is blocked as an explicit scenario assumption; no-reflector has no RF path.
clear; clc; rng(20261026,'twister');
here=fileparts(mfilename('fullpath'));
root=fileparts(here);
linkFile=fullfile(root,'04_LINK','LINK_CASES.csv');
if ~isfile(linkFile), error('PASSBRIDGE:NoRealRFData','No CST native RF link CSV; refusing synthesized RCS'); end
T=readtable(linkFile);
need={'Wind_m_s','AX_deg','AY_deg','Pol','Pr_dBm','SNR_dB'};
if ~all(ismember(need,T.Properties.VariableNames)), error('PASSBRIDGE:BadFields','Link CSV missing required columns'); end
out=fullfile(root,'05_MATLAB_OFDM');if ~isfolder(out),mkdir(out);end
rows=struct([]);
for w=[15,25,35]
 for pp={'TE','TM'}
  p=string(pp{1});sel=T(T.Wind_m_s==w & string(T.Pol)==p,:);
  if height(sel)==0,error('PASSBRIDGE:MissingCase','No CST case for W%d %s',w,p);end
  aligned=sel(sel.AX_deg==0 & sel.AY_deg==0,:);
  if height(aligned)~=1,error('PASSBRIDGE:MissingAligned','No unique aligned CST case for W%d %s',w,p);end
  [~,j]=min(sel.Pr_dBm); worst=sel(j,:);
  cases={aligned, worst}; labels={'ALIGNED','WORST_TILT'};
  for k=1:2
   one=cases{k};snr=one.SNR_dB;
   [ber,per,rate]=simulate_ofdm_awgn(snr,200);
   rows=[rows;struct('Wind_m_s',w,'Pol',char(p),'Scenario',labels{k},'AX_deg',one.AX_deg,'AY_deg',one.AY_deg,...
      'Pr_dBm',one.Pr_dBm,'SNR_dB',snr,'BER',ber,'PER',per,'Net_Mbps',rate,'Packets',200,'Source','CST_FEM_RCS_PLUS_SIMULATED_FLAT_AWGN')]; %#ok<AGROW>
  end
 end
end
% Explicit absent-panel null-path baseline: direct LOS is blocked by assumption.
[ber0,per0,rate0]=simulate_ofdm_no_link(200);
rows=[rows;struct('Wind_m_s',0,'Pol','NA','Scenario','NO_REFLECTOR_BLOCKED_LOS','AX_deg',0,'AY_deg',0,'Pr_dBm',NaN,'SNR_dB',NaN,'BER',ber0,'PER',per0,'Net_Mbps',rate0,'Packets',200,'Source','ASSUMED_BLOCKED_PATH_NO_SCATTERER')];
R=struct2table(rows);
writetable(R,fullfile(out,'MATLAB_OFDM_RESULTS.csv'));
try
 f=figure('Visible','off','Color','w');
 for k=1:2
  subplot(1,2,k);pol=string({'TE','TM'});sub=R(string(R.Pol)==pol(k),:);
  bar(categorical(strcat(string(sub.Wind_m_s),'m/s-',string(sub.Scenario))),sub.Net_Mbps);
  title(sprintf('%s OFDM simulated throughput',pol(k)));ylabel('Mbit/s');ylim([0 30]);xtickangle(45);grid on;
 end
 set(f,'Position',[100 100 1350 530]);exportgraphics(f,fullfile(out,'OFDM_THROUGHPUT.png'),'Resolution',150);close(f);
 f=figure('Visible','off','Color','w');s=R(string(R.Pol)=='TE',:);
 plot(s.Wind_m_s(strcmp(string(s.Scenario),"ALIGNED")),s.SNR_dB(strcmp(string(s.Scenario),"ALIGNED")),'-o');hold on;
 plot(s.Wind_m_s(strcmp(string(s.Scenario),"WORST_TILT")),s.SNR_dB(strcmp(string(s.Scenario),"WORST_TILT")),'-x');
 xlabel('Wind speed [m/s]');ylabel('Scenario SNR [dB]');legend('Aligned','Worst tilt','Location','best');grid on;
 title('CST FEM-coupled SNR: TE');exportgraphics(f,fullfile(out,'OFDM_SNR.png'),'Resolution',150);close(f);
catch e
 fid=fopen(fullfile(out,'PLOT_WARNING.txt'),'w');fprintf(fid,'%s\n',getReport(e));fclose(fid);
end
fid=fopen(fullfile(out,'SIMULATION_ASSUMPTIONS.txt'),'w');
fprintf(fid,['20 MHz baseband, uncoded QPSK, 64-point OFDM, 52 data bins, CP16, 14 symbols per frame, 200 Monte Carlo packets per condition.\n' ...
 'Effective channel: frequency-flat AWGN with signal/noise power determined by genuine CST FEM-RCS plus assumed EIRP, antenna gains, noise figure and external losses.\n' ...
 'This simulation does not implement actual Wi-Fi MAC, channel coding, practical fading, interference, receive sensitivity, fading or packet retransmissions.\n' ...
 'NO_REFLECTOR condition assumes no alternate RF propagation path; it is not a terrain ray-tracing measurement.\n' ...
 'Strongest claim supported: conditional digital link feasibility under stipulated RF scenario; not field throughput.\n']);fclose(fid);
fprintf('PASSBRIDGE | MATLAB_OFDM_COMPLETE | %d conditions | %s\n',height(R),out);

function [ber,per,throughput]=simulate_ofdm_awgn(snrDb,nPackets)
 N=64;cp=16;nb=52;ns=14;fs=20e6;
 k=[-26:-1 1:26];idx=mod(k,N)+1;
 nbits=nb*ns*2; biterr=0; packeterr=0;
 for pkt=1:nPackets
  b=randi([0 1],nb*ns*2,1);
  s=((1-2*double(b(1:2:end)))+1i*(1-2*double(b(2:2:end))))/sqrt(2);
  X=zeros(N,ns);X(idx,:)=reshape(s,nb,ns);
  tx=ifft(X,N,1)*sqrt(N);
  txcp=[tx(end-cp+1:end,:);tx]; sigPow=mean(abs(txcp(:)).^2);
  sigNoise=10^(-snrDb/10)*sigPow;
  awgn=(randn(size(txcp))+1i*randn(size(txcp)))*sqrt(sigNoise/2);
  rx=txcp+awgn;
  Y=fft(rx(cp+1:cp+N,:),N,1)/sqrt(N);
  z=Y(idx,:); z=z(:);
  bhat=zeros(nbits,1);bhat(1:2:end)=real(z)<0;bhat(2:2:end)=imag(z)<0;
  e=sum(b~=bhat);biterr=biterr+e;packeterr=packeterr+(e>0);
 end
 ber=biterr/(nb*ns*2*nPackets);per=packeterr/nPackets;
 throughput=(nb*ns*2 * fs/((N+cp)*ns))*max(0,1-per)/1e6;
end
function [ber,per,throughput]=simulate_ofdm_no_link(nPackets)
 % No reflection + blocked LOS -> no transmitted component at receiver.
 bits=randi([0 1],52*14*2*nPackets,1);
 guesses=randi([0 1],size(bits));ber=mean(bits~=guesses);
 per=1;throughput=0; % no RF route available by explicit topology assumption
end
