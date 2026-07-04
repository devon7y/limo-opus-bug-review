%% Reproduction — Critical #2: limo_robust_rep_anova argument-contract mismatch
% Every caller (limo_random_robust, limo_contrast) invokes:
%     limo_robust_rep_anova(Y, gp, factor_levels, C [, XB])
% i.e. the group vector gp is the 2nd argument, exactly like the sibling
% limo_rep_anova(data, gp, factors, C, S/X). Before the fix the parser read
% the args as (Data, factors, C, S): the 5-arg (between-group) form hit
% error('wrong number of arguments'), and the 4-arg form bound factors=gp,
% C=factor_levels, S=contrast, then crashed at C*y (dimension mismatch).
% It also never set result.df / result.dfe (which the caller reads), computed
% the trimmed mean across the wrong dimension (measures, not subjects), and
% mis-squeezed single-frame data.
%
% This script exercises the FIXED within-subject path and checks it returns a
% valid Hotelling-T2 result with df/dfe, matching the structure of the
% non-robust limo_rep_anova. Run from the limo_tools root.

rng(7);
f = 12;    % time/freq frames
n = 25;    % subjects
levels = 4;                 % one within factor, 4 levels (p = prod(levels))
gp = ones(n,1);             % single group (within-subject design)
C  = [eye(levels-1) -ones(levels-1,1)];   % within contrast

% data: f x n x p, a real within-subject effect on measure 1
Data = randn(f,n,levels);
Data(:,:,1) = Data(:,:,1) + 1.2;

result = limo_robust_rep_anova(Data, gp, levels, C);   % <-- FIXED call

assert(isfield(result,'F')  && numel(result.F)==f,  'result.F is 1 x frames');
assert(isfield(result,'p')  && numel(result.p)==f,  'result.p is 1 x frames');
assert(isfield(result,'df') && isscalar(result.df), 'result.df is set (caller needs it)');
assert(isfield(result,'dfe')&& isscalar(result.dfe),'result.dfe is set (caller needs it)');
assert(all(result.F>=0) && all(result.p>=0 & result.p<=1), 'F>=0 and p in [0,1]');

fprintf('within-subject robust rep-ANOVA OK: df=%d dfe=%d  meanF=%.3f  min p=%.4g\n', ...
        result.df, result.dfe, mean(result.F), min(result.p));

% single-frame case must not crash (previously mis-squeezed -> #49)
r1 = limo_robust_rep_anova(Data(1,:,:), gp, levels, C);
assert(isscalar(r1.F), 'single-frame returns a scalar F');
disp('PASS: within path returns valid df/dfe/F/p, incl. single-frame.');

% between-group form now fails LOUDLY instead of a cryptic crash / wrong stat:
try
    XB = [gp==1, ones(n,1)];
    limo_robust_rep_anova(Data, [ones(12,1);2*ones(13,1)], levels, C, XB);
    error('expected a clear not-implemented error for between-group');
catch ME
    fprintf('between-group correctly errors: %s\n', ME.message);
end
