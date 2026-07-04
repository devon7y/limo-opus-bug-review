%% Reproduction — Critical #1: limo_mglm captures eigenVECTORS, not eigenvalues
% limo_decomp is declared  [eigen_vectors, eigen_values] = limo_decomp(E,H)  --
% the FIRST output is the p x p eigenvector matrix, the SECOND is the eigenvalue
% vector. Eleven single-output calls in limo_mglm.m (e.g. line 182) captured the
% first output into a variable named Eigen_values_* and fed it into the Roy /
% Pillai F formulas, so every multivariate statistic was computed from the
% eigenvectors instead of the eigenvalues of inv(E)*H.
%
% This shows (i) the single-output form returns the eigenvector matrix, and
% (ii) Roy's statistic is a well-formed SCALAR when built from the eigenvalues
% (the fix) but a meaningless 1 x p ROW VECTOR when built from what the buggy
% code captured. Run from the limo_tools root.

rng(42);
p = 5;
E = cov(randn(30,p));   % error SSCP-like (p x p, pos-def)
H = cov(randn(30,p));   % hypothesis SSCP-like (p x p)

[eigen_vectors, eigen_values] = limo_decomp(E,H);   % correct 2-output form (the fix)
captured = limo_decomp(E,H);                         % what limo_mglm captured (1-output)

fprintf('single-output size = [%d %d] (eigenVECTOR matrix); true eigenvalues = [%d %d]\n', ...
        size(captured), size(eigen_values));
assert(isequal(captured, eigen_vectors), 'the single-output form returns the eigenvector matrix');

% Roy largest-root statistic: theta = max(ev)/(1+max(ev)); F uses max(ev)
theta_fixed = max(eigen_values) / (1+max(eigen_values));   % from eigenvalues  -> scalar
theta_buggy = max(captured)    ./ (1+max(captured));        % from eigenvectors -> 1 x p vector

fprintf('Roy theta  fixed (eigenvalues) = %.6f   (scalar)\n', theta_fixed);
fprintf('Roy theta  buggy (eigenvectors)= [%s] (1 x %d row vector)\n', ...
        strtrim(sprintf('%.4f ', theta_buggy)), numel(theta_buggy));

assert(isscalar(theta_fixed), 'fixed Roy statistic is a scalar');
assert(~isscalar(theta_buggy) && numel(theta_buggy)==p, 'buggy Roy statistic is a p-vector');
assert(abs(theta_fixed - theta_buggy(1)) > 1e-6, 'fixed and buggy differ');
disp('PASS: the fix makes Roy/Pillai use the eigenvalues (scalar) instead of eigenvectors.');
