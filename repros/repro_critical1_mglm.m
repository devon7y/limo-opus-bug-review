%% Reproduction — Critical #1: limo_mglm captures eigenVECTORS, not eigenvalues
% limo_decomp is declared:  [eigen_vectors, eigen_values] = limo_decomp(E,H)
% Every single-output call in limo_mglm.m (e.g. line 182) writes the FIRST
% output (the p x p eigenvector matrix) into a variable named Eigen_values_*
% and then feeds it into the Roy / Pillai F formulas. This script shows that
% the captured quantity is the eigenvector matrix and that the resulting Roy
% statistic is wrong in both shape and value.
%
% Run from the limo_tools root (so limo_decomp is on the path).

rng(42);
p = 5;                      % measures / electrodes
E = cov(randn(30,p));       % error SSCP-like matrix (p x p, pos-def)
H = cov(randn(30,p));       % hypothesis SSCP-like matrix (p x p)

[eigen_vectors, eigen_values] = limo_decomp(E,H);   % correct 2-output form
buggy = limo_decomp(E,H);                            % what limo_mglm captured (1-output)

fprintf('size(buggy captured)      = [%d %d]  (eigenvector MATRIX)\n', size(buggy));
fprintf('size(true eigen_values)   = [%d %d]  (eigenvalue VECTOR)\n', size(eigen_values));
fprintf('buggy == eigen_vectors ?   %d   (1 => the bug captured eigenvectors)\n', isequal(buggy, eigen_vectors));

% Roy's largest-root statistic theta = max(ev)/(1+max(ev))
theta_correct = max(eigen_values) / (1+max(eigen_values));       % scalar, correct
theta_buggy   = max(buggy)        ./ (1+max(buggy));             % 1 x p row vector, WRONG

fprintf('\nRoy theta (correct, scalar) = %.6f\n', theta_correct);
fprintf('Roy theta (buggy)           = [%s]  <-- wrong shape & value\n', ...
        strtrim(sprintf('%.4f ', theta_buggy)));

assert(isscalar(theta_correct), 'fixed code yields a scalar Roy statistic');
assert(~isequal(theta_correct, theta_buggy(1)), 'buggy vs fixed differ');
disp('PASS: fixed code uses eigenvalues; buggy code used eigenvectors.');
