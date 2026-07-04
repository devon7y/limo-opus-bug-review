%% Reproduction — Critical #4: TF null TFCE built with the wrong dimensionality
% In limo_tfce, type 2 reads [x,y,b]=size(data) -- so a 3D chan x freq x time
% array is misread with TIME as the bootstrap dimension b, and TFCE is applied to
% each time slice independently. type 3 reads [x,y,z,b] and clusters in true 3D.
%
% For multi-channel Time-Frequency F-maps limo_tfce_handling computes the OBSERVED
% statistic with type 3 but (pre-fix) built the H0 null with type 2 -- a different
% algorithm -- so the corrected threshold is incomparable. This script shows the
% two give materially different scores on a map with a cluster that spans time.
%
% Run from the limo_tools root.

rng(3);
nchan = 8; nfreq = 10; ntime = 12;

% a coherent positive blob spanning channels x freq x time (a real TF cluster)
[cc,ff,tt] = ndgrid(1:nchan,1:nfreq,1:ntime);
Fmap = 6*exp(-(((cc-4).^2)/5 + ((ff-5).^2)/6 + ((tt-6).^2)/9)) + 0.15*abs(randn(nchan,nfreq,ntime));

% channel neighbourhood, n_chan x n_chan logical. limo_tfce calls
% limo_findcluster with minnbchan=2, so a point needs >=2 active channel
% neighbours to survive -- use a dense montage (all channels neighbours) so the
% clustering is well-posed for this small synthetic example.
nb = true(nchan) & ~eye(nchan);

s3 = limo_tfce(3, Fmap, nb, 0);   % correct: matches the observed statistic (and the fixed null)
s2 = limo_tfce(2, Fmap, nb, 0);   % the buggy null: treats time as bootstraps -> per-slice 2D TFCE

d   = max(abs(s3(:)-s2(:)));
rel = d / max(abs(s3(:)));
fprintf('max TFCE score:  type3 (correct) = %.3f   type2 (buggy null) = %.3f\n', max(s3(:)), max(s2(:)));
fprintf('max |type3 - type2| = %.4g   (%.1f%% of the peak)\n', d, 100*rel);
assert(d > 1e-6, 'the buggy null (type 2) differs from the observed statistic (type 3)');
disp('PASS: type-2 null is not comparable to the type-3 observed statistic -> fix required.');
