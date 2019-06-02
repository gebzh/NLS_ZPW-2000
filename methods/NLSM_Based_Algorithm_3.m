function [ f0_hat, f1_hat, alpha_hat, cos_correlation, n_all_ZPW, p_all, q_all, ...
    Amplis_all,cos_correlation_all] = NLSM_Based_Algorithm_3( x_bold, fs )
% NLS method based ZPW-2000 signal demodulation method
% using scheme 3
%   inputs:
%   x_bold: the received signal; fs: the sampling frequency
%   outputs:
%   f0: the estimated carrier frequency; f1: the estimated low frequency
%   alpha_hat: the estimated linear coefficients
%   cos_correlation: the cosine correlation between the estimated amplitudes &
% the standard amplitudes
%   n_all_ZPW: the amount of the ZPW-2000 signals including the interference 
% from the neighboring track
%   p_all: the numbers corresponding to all of existing f0s
%   q_all: the numbers corresponding to all of existing f1s
%   Amplis_all: the estimated amplitudes of all of existing ZPW-2000 signals
%   cos_correlation_all:  the cosine correlation of all of existing ZPW-2000 
% signals

N = length(x_bold);
n0 = -(N-1)/2;
omegarp = 2*pi*0.0001/fs;
Apslowerbound = 0.15; 
% the lower bound of the amplitude of the carrier freq and the first-side
% freqs components

%========================* loading data *==========================
global Z_AI;
global ZTZ_AI;
global ZTZ_AII;
global ks_AII;
global gridparas_AII;
global lengthOfSignal;
global n0iszero;
global Amplis_std;
global f0_std;
global f1_std;

if (isempty(Z_AI) || isempty(ZTZ_AI) || isempty(ZTZ_AII) || ...
        isempty(gridparas_AII) || isempty(ks_AII) || isempty(Amplis_std) ||...
        lengthOfSignal ~= N || n0iszero ~= 0)
    Load_Data(N,fs);
end

% definition of the standard carrier freqs, the standard low freqs and the
% modulation indexes 
if isempty(f0_std) || isempty(f1_std) 
    f0_std = [1701.4; 1698.7; 2001.4; 1998.7; 2301.4; 2298.7; 2601.4; 2598.7];
    f1_std = (10.3:1.1:29)';
end

% parameters for fast-solving method
LlpLlT = zeros(5,5,5);
for i = 1:5
    for j = 2:i
        LlpLlT(j-1,j,i) = 1;
    end
    for j = 1:i-1
        LlpLlT(j+1,j,i) = 1;
    end
end

% starting the timer
global Timer;
Timer = 0;
tic;
%========================* coarse estimation *==========================
n_all_ZPW = 0;
p_all = zeros(10,1);
q_all = zeros(10,1);
Amplis_all = zeros(5,10);
cos_correlation_all = zeros(10,1);

Jmax = 0; f0c = -1; f1c = -1;
for p = 1:8
    for q = 1:18
        [J, alph_hat, cc] = CostCalcForCoarseEst(p,q);
        if (J > Jmax)
            Jmax = J;
            f0c = f0_std(p); f1c = f1_std(q);
            pc = p; qc = q;
        end
        if (J > 0)
            n_all_ZPW = n_all_ZPW + 1;
            p_all(n_all_ZPW) = p;
            q_all(n_all_ZPW) = q;
            Amplis_all(:,n_all_ZPW) = sqrt_BinarySearchpro(alph_hat(1:5).^2 ...
                + alph_hat(6:10).^2);
            cos_correlation_all(n_all_ZPW) = cc;
        end
    end
end
if f0c == -1 || f1c == -1
    f0_hat = -1; f1_hat = -1;
    alpha_hat = zeros(10,1);  cos_correlation = 0;
end

%========================* grid search *==========================
if f0c ~= -1 && f1c ~= -1
    k0 = ks_AII(1,pc,qc); k1 = ks_AII(2,pc,qc); k2 = ks_AII(3,pc,qc);
    M = gridparas_AII(1); L_h = gridparas_AII(2);
    Deltaomega = 2*pi/M;

    XM = fft(x_bold,M); 
    
    Jmax = 0;
    for i = -L_h : L_h
        for j = -L_h : L_h
            J = CostCalcForGridSearch(pc,qc,i,j);
            if J>Jmax
                Jmax = J;
                omega0g = (k0+i)*Deltaomega;
                omega1g = (k1+j)*Deltaomega;
                Deltaomegag = Deltaomega;
            end
        end
    end
end

%========================* fine search *==========================
if f0c~=-1 && f1c ~=-1
    omega0l = omega0g - Deltaomegag; omega0r = omega0g + Deltaomegag;
    Deltaomega0 = Deltaomegag;
    
    [J0l] = DichotomousSearchForLowFreq(omega0l);
    [J0r] = DichotomousSearchForLowFreq(omega0r);
    omega0m = (omega0l+omega0r)/2;

    while (2*Deltaomega0 > omegarp)
        [J0m,omega0m_1,alpha0m] = DichotomousSearchForLowFreq(omega0m);
        Deltaomega0 = Deltaomega0 / 2; 
        omega0m_last = omega0m;
        if J0l<J0r
            J0l = J0m; omega0m = omega0m + Deltaomega0;
        else
            J0r = J0m; omega0m = omega0m - Deltaomega0;
        end
    end
    f0_hat = fs*omega0m_last/(2*pi);
    f1_hat = fs*omega0m_1/(2*pi);
    alpha_hat = alpha0m;
    
    Amplis_hat = sqrt_BinarySearchpro(alpha_hat(1:5).^2 + alpha_hat(6:10).^2);
    cos_correlation = CalcCosCorrelation(Amplis_hat,Amplis_std(:,qc));
end

% record the time cost
Timer = Timer + toc;
fprintf('running time of alg3 %fs\n',Timer);

%% ========================* functions *==========================
    function [J1m, omega1m_last, alpha1m] = DichotomousSearchForLowFreq(omega0p)
        omega1l = omega1g - Deltaomegag; omega1r = omega1g + Deltaomegag;
        Deltaomega1 = Deltaomegag;
        
        omega1m = (omega1l+omega1r)/2;
        [J1l] = CostCalcAccordingToFreqs(omega0p,omega1l);
        [J1r] = CostCalcAccordingToFreqs(omega0p,omega1r);
        while (2*Deltaomega1 > omegarp)
            [J1m,alpha1m] = CostCalcAccordingToFreqs(omega0p,omega1m);
            Deltaomega1 = Deltaomega1 / 2;
            omega1m_last = omega1m;
            
            if J1l < J1r
                J1l = J1m; omega1m = omega1m + Deltaomega1;
            else
                J1r = J1m; omega1m = omega1m - Deltaomega1;
            end
        end
    end
    function [J, lph_hat, c_c] = CostCalcForCoarseEst(pp,qq)
        % If the Amplitudes of the three main freq components are larger than
        % Aslowerbound, the corresponding carrier freq and the low freq will 
        % be choosed as candidates, and the corresponding alpha_hat and
        % the r square will be recorded as references for fault diagnosis
        eta = Z_AI(:,:,pp,qq)'*x_bold;
        lph_hat = FastSolvingForTPHSystem(ZTZ_AI(:,:,pp,qq),eta);
        J = eta'*lph_hat;
        Apls_hat = sqrt_BinarySearchpro(lph_hat(1:5).^2 + lph_hat(6:10).^2);
        c_c = CalcCosCorrelation(Apls_hat,Amplis_std(:,qq));
        if ( Apls_hat(2)<Apslowerbound || Apls_hat(3)<Apslowerbound...
                || Apls_hat(4)<Apslowerbound || (qq <= 9 ...
                && Apls_hat(1)>Apls_hat(2) && Apls_hat(5)>Apls_hat(4)) )
            J = -1;
            c_c = 0;
        end
    end
    function [J,alpha] = CostCalcAccordingToFreqs(omega0,omega1)
        Z = CreateZ(omega0,omega1);
        eta = Z'*x_bold;
        alpha = FastSolvingForTPHSystem(Z'*Z,eta);
        J = eta'*alpha;
    end     
    function c_c = CalcCosCorrelation(y,x)
        c_c = x'*y/sqrt_BinarySearchpro(sum(x.^2))...
            /sqrt_BinarySearchpro(sum(y.^2));
        c_c = 1-2*arccos_CORDICpro(c_c)/pi;
    end
    function J = CostCalcForGridSearch(pp,qq,ii,jj)
        eta = zeros(10,1); 
        k = k0-k2+(ii-2*jj); temp = exp(-1j*k*Deltaomega*n0)*XM(k+1);
        eta(1) = real(temp); eta(6) = -imag(temp);
        k = k0-k1+(ii-jj); temp = exp(-1j*k*Deltaomega*n0)*XM(k+1);
        eta(2) = real(temp); eta(7) = -imag(temp);
        k = k0+ii; temp = exp(-1j*k*Deltaomega*n0)*XM(k+1);
        eta(3) = real(temp); eta(8) = -imag(temp);
        k = k0+k1+(ii+jj); temp = exp(-1j*k*Deltaomega*n0)*XM(k+1);
        eta(4) = real(temp); eta(9) = -imag(temp);
        k = k0+k2+(ii+2*jj); temp = exp(-1j*k*Deltaomega*n0)*XM(k+1);
        eta(5) = real(temp); eta(10) = -imag(temp);
        alpha = FastSolvingForTPHSystem(ZTZ_AII(:,:,ii+L_h+1,jj+L_h+1,pp,qq),eta);
        J = eta'*alpha;
    end
    function alpha = FastSolvingForTPHSystem(ZTZ,eta)
        [t,h,qL] = LoadDataForFastAlg(ZTZ);
        a_l = FastSolving(t,h,qL,5,eta(1:5));

        qL = [-t(2);-t(3)+h(2);-t(4)+h(3); -t(5)+h(4) ];
        b_l = FastSolving(-t,h,qL,5,eta(6:10));

        alpha = [a_l;-b_l];
    end
    function [t,h,qL] = LoadDataForFastAlg(ZZ)
        t = ((ZZ(1,1:5)+ZZ(6,6:10))/2)';
        h = zeros(10,1);
        h(2:6) =  ((ZZ(1,1:5) - ZZ(6,6:10))/2)';
        h(7:10) = ((ZZ(2:5,5) - ZZ(7:10,10))/2)';
        qL = [t(2); t(3)+h(2); t(4)+h(3); t(5)+h(4)];
    end
    function a = FastSolving(t,h,qL,L,omega_L)
        % Solving the linear system Ax = b with time complexity O(L^2) 
        % according to properties of the Toeplitz-plus-Hankel system 
        gamma = zeros(L,1);  phi = zeros(L,1);  psi = zeros(L,1); 
        r_bold = zeros(L,1);  rho = zeros(L,1);  beta = zeros(L,1); 
        lambda = zeros(L,1);  a = zeros(L,1); 
        t = [t;0]; h = [h;0]; %for situation that L==1
        
        r_little = t(0+1) + h(2);
        gamma(1) = 1/r_little;
        phi(1) = qL(1)/r_little;
        psi(1) = 1/r_little;
        r_bold(1) = t(1+1) + h(3);
        rho(1) = -r_bold(1)/r_little;
        beta(1) = rho(1) * gamma(1);
        lambda(1) = omega_L(1);
        a(1) = lambda(1)*gamma(1);

        for ll = 1:L-1 
            r_little = t(0+1) + h(2*ll+2);
            gamma_ll = gamma(1:ll);
            gamma(ll+1) = 1/(r_little+r_bold(1:ll)'*beta(1:ll)/gamma_ll(ll));% spends too much time
            gamma(1:ll) = gamma(ll+1) * beta(1:ll) /gamma_ll(ll);
            a(1:ll+1) = [a(1:ll);0] + gamma(1:ll+1)*(omega_L(ll+1)-r_bold(1:ll)'*a(1:ll));% spends too much time
            if ll == L-1
                break;
            end
            phi(1:ll+1) = [phi(1:ll);0] + (qL(ll+1) - r_bold(1:ll)'*phi(1:ll))*gamma(1:ll+1);
            psi(1:ll+1) = [psi(1:ll);0] - r_bold(1:ll)'*psi(1:ll)*gamma(1:ll+1);
            r_bold(1:ll+1) = t(ll+2:-1:2) + h(ll+3:2*ll+3);
            rho(ll+1) = -r_bold(1:ll+1)'*gamma(1:ll+1);
            beta(1:ll+1) = ((rho(ll+1)-rho(ll))*eye(ll+1)+LlpLlT(1:ll+1,1:ll+1,ll+1))*...
                gamma(1:ll+1) - [gamma_ll;0] + psi(ll+1)*phi(1:ll+1) - phi(ll+1)*...
                psi(1:ll+1);
        end
    end
    function Z = CreateZ(omg0,omg1) 
        Z = zeros(N,10);
        omgs = omg0 + omg1*(-2:1:2)';
        for ii = 1:5
            omg = omgs(ii);
            cosomg = cossin_CORDICpro(omg,1);
            sinomg = cossin_CORDICpro(omg,2);
            Z(1,ii) = cossin_CORDICpro(omg*n0,1);
            Z(1,ii+5) = cossin_CORDICpro(omg*n0,2);
            for jj = 2:N
                Z(jj,ii) = Z(jj-1,ii)*cosomg - Z(jj-1,ii+5)*sinomg;
                Z(jj,ii+5) = Z(jj-1,ii+5)*cosomg + Z(jj-1,ii)*sinomg;
            end
        end
    end
end