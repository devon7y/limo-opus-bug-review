%% Reproduction — Critical #3: reversed subject loop in limo_random_select getdata
% In getdata (single-list branch, ~line 1956) the loop ran BACKWARD while the
% write pointer `index` (initialised to 1, incremented +1 per kept subject) ran
% FORWARD. The assembled data cube's subject axis therefore came out reversed
% relative to file order -- and relative to the regressor design matrix X, which
% is built in file order. For a 2nd-level regression this silently pairs each
% subject's data with the WRONG regressor row.
%
% This script isolates the exact index mechanism (no LIMO data needed) and shows
% the reversal, then the regression consequence. It reproduces the pre-fix loop
% and the fixed loop side by side.

nsub  = 6;
files = compose('subject_%d', 1:nsub);   % file order = subject order

% ---- pre-fix: backward loop, forward compacting index ----
index = 1; order_bug = zeros(1,nsub);
for i = nsub:-1:1                 % <-- buggy direction
    order_bug(index) = i;         % data(...,index) holds file i
    index = index + 1;
end

% ---- fixed: forward loop ----
index = 1; order_fix = zeros(1,nsub);
for i = 1:nsub                    % <-- fixed direction
    order_fix(index) = i;
    index = index + 1;
end

fprintf('data column ->  subject index\n');
fprintf('  pre-fix : [%s]  (reversed!)\n', strtrim(sprintf('%d ',order_bug)));
fprintf('  fixed   : [%s]  (matches file/regressor order)\n', strtrim(sprintf('%d ',order_fix)));

% ---- regression consequence ----
% true model: y_subject = beta * x_subject + noise, x in file order
rng(1); x = (1:nsub)';                 % regressor, file order (design matrix rows)
beta_true = 2.0;
y_fileorder = beta_true*x + 0.01*randn(nsub,1);

% GLM pairs data column k with regressor row k:
y_bug = y_fileorder(order_bug)';       % data assembled reversed
y_fix = y_fileorder(order_fix)';       % data assembled correctly
Xd = [x ones(nsub,1)];
b_bug = Xd \ y_bug(:);
b_fix = Xd \ y_fix(:);
fprintf('\nrecovered slope  true=%.3f  fixed=%.3f  buggy=%.3f\n', beta_true, b_fix(1), b_bug(1));
assert(abs(b_fix(1)-beta_true) < 0.05, 'fixed recovers the true slope');
assert(abs(b_bug(1)-beta_true) > 0.5,  'buggy slope is wrong (Y<->X scrambled)');
disp('PASS: forward loop restores Y<->X alignment; backward loop corrupts regression.');
