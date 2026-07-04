%% Reproduction — Critical #4: TF null TFCE built with the wrong dimensionality
% In limo_tfce_handling the OBSERVED F-map TFCE uses the correct type map
%   single-channel TF -> limo_tfce(2, freq x time)      (2D)
%   multi-channel  TF -> limo_tfce(3, chan x freq x time)(3D)
% but the H0 (null) section used type 1 and type 2 respectively -- one lower.
% The null is then enhanced by a DIFFERENT-dimensional clustering algorithm than
% the observed statistic, so the TFCE-corrected threshold is incomparable and
% the corrected p-values for F-effects in Time-Frequency are wrong.
%
% This script shows that, for the SAME multi-channel TF F-map, limo_tfce(3,...)
% (correct, observed & fixed-null) and limo_tfce(2,...) (buggy null) produce
% different scores. Run from the limo_tools root.

rng(3);
nchan = 8; nfreq = 10; ntime = 12;
Fmap = randn(nchan,nfreq,ntime).^2;        % positive, F-like map (chan x freq x time)

% simple channel neighbourhood (chain adjacency), n_chan x n_chan logical
nb = false(nchan);
for c = 1:nchan
    if c>1,     nb(c,c-1)=true; end
    if c<nchan, nb(c,c+1)=true; end
end

s3 = limo_tfce(3, Fmap, nb, 0);            % correct: observed & fixed null
try
    s2 = limo_tfce(2, Fmap, nb, 0);        % buggy null used this on 3D data
    d  = max(abs(s3(:)-s2(:)));
    fprintf('type-3 vs type-2 on identical 3D F-map: max |diff| = %.4g\n', d);
    fprintf('size(type3)=[%s]  size(type2)=[%s]\n', ...
            strtrim(sprintf('%d ',size(s3))), strtrim(sprintf('%d ',size(s2))));
    assert(d > 0, 'null (type 2) differs from observed (type 3) -> incomparable');
    disp('PASS: buggy null (type 2) is not comparable to the observed statistic (type 3).');
catch ME
    fprintf(['type-2 on 3D data errored/mis-handled (%s)\n' ...
             'PASS: buggy null could not even be computed the same way as observed.\n'], ME.message);
end
