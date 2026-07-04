# LIMO-EEG Toolbox v4.2.1 — Verified Bug Report

Two **Opus 4.8** multi-agent passes over the current stable release `v4.2.1` (synced with `origin/v4.2.1`): a 333-agent round 1, then a round 2 seeded with MATLAB `checkcode` and told to find only bugs the first pass missed. Every candidate was re-checked by an independent adversarial verifier that had to construct a concrete failing input against the real code or reject it.

**287 deduplicated confirmed defects** — 4 critical · 83 high · 123 medium · 77 low (269 CONFIRMED, 18 PLAUSIBLE) across 87 files. 218 from round 1; **69 new in round 2** (0 duplicates), tagged `R2-new` below.

The 4 round-1 criticals were reproduced in MATLAB R2025a and fixed (PRs #234–#237). Round-2 verification was partially cut short by a session limit, so its count is a floor. Findings are deduplicated and ranked by severity, then verdict. `external/` (FieldTrip, PSOM, apcluster) and `deprecated/` were out of scope. Line numbers reference the v4.2.1 working tree. Fixes are minimal suggestions.

| Severity | Count | Verdicts |
|---|---:|---|
| 🔴 Critical | 4 | 4 CONFIRMED |
| 🟠 High | 83 | 83 CONFIRMED |
| 🟡 Medium | 123 | 121 CONFIRMED, 2 PLAUSIBLE |
| ⚪ Low | 77 | 61 CONFIRMED, 16 PLAUSIBLE |

---

## 🔴 Critical (4)

#### 1. `limo_mglm.m:182` — 🔴 CRITICAL · CONFIRMED

**Single-output calls to limo_decomp capture the eigenVECTORS matrix, not the eigenvalues, so every Roy/Pillai F and p is computed from the wrong quantity.**

- **Why:** limo_decomp is declared `function [eigen_vectors,eigen_values] = limo_decomp(E,H,type)` (verified in limo_decomp.m: it does `[eigen_vectors,D]=eig(...)` and `eigen_values=diag(D)`). Every place that calls it with a single output — lines 182, 315, 361, 454, 465, 520, 587, 704, 792, 803, 835 (e.g. `Eigen_values_R2 = limo_decomp(E,H)`) — therefore receives eigen_vectors (a p x p matrix) but stores it in a variable named `Eigen_values_*` and treats it as the eigenvalue vector in all subsequent F formulas (max(Eigen_values), sum(Eigen_values./(1+Eigen_values)), etc.). Note that at line 214 the author DOES use the two-output form `[Eigen_vectors_cond,Eigen_values_cond]=limo_decomp(...)`, confirming the intended order and that the single-output calls are wrong. The correct call is `[~,Eigen_values_R2] = limo_decomp(E,H)`.
- **Category:** `statistical-correctness`

#### 2. `limo_random_select.m:1956` — 🔴 CRITICAL · CONFIRMED

**In getdata case 1 the subject loop runs backward (N:-1:1) while writing into a forward-incrementing index, so the data subject axis is reversed relative to file (and regressor) order, scrambling the Y<->X pairing in second-level regression.**

- **Why:** Lines 1956-2008: `for i=size(LIMO.data.data,1):-1:1` iterates subjects from last to first, but assigns `data(...,index)` with `index` starting at 1 and incremented each kept subject (lines 1987/1989/2007). Thus data(...,1) is the LAST file, data(...,end) is the FIRST file. For a one-sample t-test order is irrelevant, so this is harmless there. For regression (same getdata case 1), the regressor matrix X is loaded straight from the user's file in forward subject order (lines 273-289) and passed unchanged with the data to limo_random_robust case 4, which sets LIMO.data.Cont=regressors and builds the design pairing row i of X with data column i (verified in limo_random_robust.m lines 600-682, no reordering). Because the data subject axis is reversed but X is not, every subject's EEG is regressed against a different (reversed-position) subject's regressor value. The bug is confirmed by an internal inconsistency: ANCOVA uses getdata case 2 (forward loop, lines 2087-2211) together with a forward covariate-removal loop (lines 1040-1048), whereas regression uses reversed getdata case 1 together with a forward removal loop (lines 300-333) and forward NaN removal (`sub_toremove` from X applied to `data`, lines 326-332) - so the covariate/removal bookkeeping assumes forward order that getdata case 1 does not produce.
- **Category:** `correctness`

#### 3. `limo_robust_rep_anova.m:57` — 🔴 CRITICAL · CONFIRMED

**limo_robust_rep_anova's argument parser omits the group vector `gp` that every caller passes, so the between-group form always errors and the within form silently misassigns factors/C/S.**

- **Why:** The function parses inputs as (Data, factors, C, S): nargin==2 -> (Data,factors); nargin 3/4 -> (Data,factors,C[,S]); anything else -> error('wrong number of arguments') at line 65. But ALL eight call sites (limo_random_robust.m:1092,1102,1112,1130,1349,1357,1365,1377 and limo_contrast.m:780,840,929,987) call it as limo_robust_rep_anova(Y, gp, factor_levels, C[, XB]) -- i.e. with the group vector in slot 2. The header comment is itself inconsistent (line 3 documents (data,gp,factors) while line 18 documents (data,factors,C)). Consequences: (a) the 1-within/1-between calls pass 5 arguments -> nargin==5 -> immediate error at line 65; (b) the within-only calls pass 4 arguments -> factors=gp (a subjects x 1 vector of ones), C=factor_levels, S=C(caller's real contrast matrix). Because size(ones(n,1),2)==1, nb_factors is forced to 1 so a multi-factor within design is misrouted to the single-factor case, C is set to the level vector instead of a contrast matrix, and S (expected to be a per-frame p x p covariance) is set to the caller's 2D contrast matrix, so squeeze(S(time,:,:)) and inv(C*S*C') are garbage/error.
- **Category:** `control-flow-arg-mismatch`

#### 4. `limo_tfce_handling.m:303` — 🔴 CRITICAL · CONFIRMED

**Multi-channel time-frequency null TFCE is computed with type 2 (2D) instead of type 3 (3D), so the H0 distribution is built with a different, wrong algorithm than the observed statistic.**

- **Why:** In the final 'else' branch (F/ess files: ANOVA, ANCOVA, repeated-measures F contrasts), the observed multi-channel Time-Frequency map is TFCE'd with type 3 (line 270: limo_tfce(3,squeeze(Fval(:,:,:,1)),...)), correctly treating [channels x freq x time] as a 3D cluster problem. But the matching H0 call on line 303 passes type 2 with squeeze(H0_Fval(:,:,:,1,b)) which is a 3D array [channels x freq x time]. Inside limo_tfce, type 2 does [x,y,b]=size(data) -> x=channels, y=freq, b=time; because b(time)>1 it selects subtype 2 ('bootstrapped data under H0') and returns NaN(x,y,b)=[channels,freq,time], which fits the tfce_H0_score(:,:,:,b) slot so nothing errors. The effect: each time point is treated as an independent 2D channel-by-freq bootstrap sample and TFCE-integrated separately, instead of one 3D spatio-spectro-temporal integration. The null is therefore computed with a completely different estimator and on a different scale than the observed type-3 score, invalidating every max-stat / corrected p-value derived from comparing them.
- **Category:** `resampling/permutation`

## 🟠 High (83)

#### 5. `limo_AIC_BIC.m:136` — 🟠 HIGH · CONFIRMED

**aic and bic are overwritten every channel iteration and never indexed by channel, so the function returns only the last good channel's values.**

- **Why:** The loop `for channel = 1:length(array)` (line 117) computes `ll` for `array(channel)` and then assigns `aic = -2.*ll + 2*p;` / `bic = -2.*ll + p*log(n);` (lines 133-138) to plain scalars-per-frame variables, not to `aic(array(channel),:)`. There is no preallocation (`aic = NaN(nchan,nframes)`) and no channel index on the LHS. Each iteration clobbers the previous one, so after the loop `aic`/`bic` hold only the last non-NaN channel's `[1 x frames]` vector. For a normal mass-univariate LIMO GLM with many channels this silently discards AIC/BIC for every channel except the last, and the returned array has the wrong shape (`[1 x frames]` instead of `[channels x frames]`). The Time-Frequency reshape at lines 143-144 then also operates on this malformed 1-row array.
- **Category:** `indexing/dimension`

#### 6. `limo_LI.m:173` — 🟠 HIGH · CONFIRMED

**The guard tests for a variable named 'channel' that never exists, so the user-supplied 'channelpairs' (stored in 'channels') is always discarded and recomputed.**

- **Why:** The optional input parsed at line 61-62 stores the user's channel-pair matrix in the variable `channels`. At line 173 the code guards recomputation with `if ~exist('channel','var')` — but the variable is `channels`, not `channel`. `exist` requires an exact name match (no prefix matching), so the condition is ALWAYS true and line 174 unconditionally overwrites `channels` with `limo_pair_channels(LIMO.data.chanlocs)`. The whole 'channelpairs' option is therefore silently ignored, defeating the documented (and 'strongly advised') ability to supply correct left/right pairings. All downstream LI, null, and bias computations use the auto-detected pairing instead of the user's.
- **Category:** `logic/typo`

#### 7. `limo_STAPLE.m:64` — 🟠 HIGH · CONFIRMED

**The rater loop always writes into column N of DD instead of column `map`, so every expert's segmentation is discarded except the last file loaded.**

- **Why:** The loop `for map = N:-1:1` loads each statistical map and should store it in column `map` of DD, but line 64 hard-codes `DD(:,N) = data(:)`. Since the index is always N, each iteration overwrites the same column; when the loop finishes only column N holds data (from the final iteration, map=1), and columns 1..N-1 remain zero. Every subsequent computation `D = double(DD==cluster)` then treats raters 1..N-1 as all-zero maps. The EM sensitivity/specificity estimates (p,q), the weight matrix W, and the thresholded STAPLE label map are all computed from this corrupted D, so the entire consensus estimate is wrong for any N>1. Note `map` IS used correctly elsewhere (nclusters(map), map==1), confirming line 64 is a typo.
- **Category:** `indexing`

#### 8. `limo_batch.m:258` — 🟠 HIGH · CONFIRMED

**`if isempty(STUDY)` references STUDY unconditionally, throwing an undefined-variable error whenever STUDY was neither passed as the 4th argument nor present in the base workspace.**

- **Why:** STUDY is only assigned at line 249 (when nargin==4) or line 254 (when a struct STUDY exists in the base workspace). For every other call — e.g. the documented programmatic forms `limo_batch('model specification',model)` or `limo_batch('both',model,contrast)` with no STUDY and none in base — STUDY is never created. Line 258 then evaluates `isempty(STUDY)`, and referencing an undefined variable errors in MATLAB (`Unrecognized function or variable 'STUDY'`). The guard clearly intends to catch an explicitly-passed empty STUDY (as in the line 72 example) but is missing an `exist` check. A concrete symptom of the bug: the entire non-STUDY branch at lines 288-298 (labeled 'if not part of a EEGLAB STUDY - e.g. run locally or FieldTrip') is unreachable, because reaching line 262's `if exist('STUDY','var')` being false requires passing line 258 without STUDY defined — which crashes first. The only way to reach the non-STUDY branch today is to explicitly pass STUDY=[] as a 4th argument.
- **Category:** `control-flow`

#### 9. `limo_batch_design_matrix.m:271` — 🟠 HIGH · CONFIRMED

**Time-Frequency component-cluster reordering preallocates `newY` with the wrong dimensionality and assigns mismatched shapes, corrupting or crashing 4D reordering.**

- **Why:** In the Time-Frequency / Components branch, `Y` is 4D `[components x freq x time x trials]` (produced by line 255's 4-subscript indexing). Line 271 preallocates `newY = NaN(nb_clusters,size(Y,2),size(Y,3));` which is only 3D and uses `size(Y,3)` (time) as its last dimension, completely dropping the trials dimension. Line 278 then does `newY(c,:,:,:) = Y(which_ics,:,:);`: the RHS indexes the 4D `Y` with only three subscripts, so MATLAB collapses the last two dims and returns `[1 x n_freq x (n_time*n_trials)]`, while the LHS `newY(c,:,:,:)` expects a `[1 x n_freq x n_time x n_trials]` block. The third-dimension sizes (`n_time*n_trials` vs `n_time`) do not match, so the assignment errors for any dataset with more than one trial/subject. This differs from the correct 3D handling in the Time and Frequency branches (lines 70/77 and 168/175), which use `newY(c,:,:)` consistently.
- **Category:** `indexing-dimension`

#### 10. `limo_batch_gui.m:133` — 🟠 HIGH · CONFIRMED

**Multi-selected .set files are stored as a 1xN row cell of bare basenames (no path), so downstream batch processing loses the folder and only processes the first subject.**

- **Why:** uigetfile(...,'MultiSelect','on') returns FileName as a 1xN ROW cell of basenames. The multiselect branch (lines 102-108) only validates the extensions and then stores handles.FileName = FileName unchanged, unlike the single-.set branch (lines 110-112) which prepends PathName to build a full path. Two consequences in limo_batch: (a) limo_batch documents/uses model.set_files as full-path Nx1 cells and iterates with size(model.set_files,1) (limo_batch.m lines 150 and 319) — for a 1xN row cell size(...,1)==1, so only ONE subject is ever imported/analyzed; (b) the stored names lack PathName, so pop_loadset cannot find the files unless the cwd happens to be the data folder.
- **Category:** `data-handling`

#### 11. `limo_batch_gui.m:490` — 🟠 HIGH · CONFIRMED

**Done_Callback references an undefined variable `file` inside exist(...), throwing 'Unrecognized function or variable file' on the common no-regressor and unrecognized-channel-file paths.**

- **Why:** The intent is exist('warndlg2','file') (the string 'file' as the second arg), but the code writes the bareword `file`, which is never assigned anywhere in Done_Callback. MATLAB evaluates the argument `file` first and errors because the variable does not exist. This occurs at line 490 (reached whenever both CatName and ContName are empty, i.e. the very common mean-only design) and identically at line 477 (unrecognized channel-location file). Because the error is thrown before warndlg2 is ever called, the callback aborts.
- **Category:** `control-flow`

#### 12. `limo_central_estimator.m:109` — 🟠 HIGH · CONFIRMED

**The non-legacy (documented default) interval indexes the UNSORTED bootstrap matrix bb instead of sorted_data, so the returned bounds are two arbitrary bootstrap replicates rather than the alpha/1-alpha quantiles.**

- **Why:** Line 82 creates sorted_data = sort(bb,2). The legacy branch correctly indexes sorted_data. The non-legacy branch on lines 109-110 instead indexes bb (the raw, unsorted bootstrap estimates): HDI(1,:)=bb(:,round(alphav*Nb)); HDI(2,:)=bb(:,round((1-alphav)*Nb)). Selecting column 25 and column 975 of an unsorted array returns the estimates from the 25th and 975th bootstrap iterations — random values, not the 2.5% and 97.5% percentiles. The commented-out line 108 (`quantile(...)`) confirms quantiles were intended. This branch is the documented default: nargin==1 sets legacy_mode=false (lines 39-43), so a plain call limo_central_estimator(Y) returns a meaningless interval whose lower bound can exceed its upper bound.
- **Category:** `resampling/permutation`

#### 13. `limo_central_tendency_and_ci.m:360` — 🟠 HIGH · CONFIRMED

**Non-weighted within-subject estimator (Mean/Median/Trimmed mean/HD) is computed over a trial dimension that is zero-padded at all unselected trials, corrupting the central-tendency estimate.**

- **Why:** In the 6/7-argument programmatic branch, when Estimator1 is anything other than 'Weighted Mean', trials are selected with a LOGICAL vector: `index = logical(sum(LIMO.design.X(:,parameters)==1,2))` (line 338). The assignment `tmp(channel,:,index) = squeeze(Yr(channel,:,index))` uses this logical index on the LHS 3rd dimension. MATLAB expands `tmp` so its 3rd dimension has length = total number of trials, placing selected trials at their true positions and filling every UNSELECTED position with numeric 0 (not NaN). The subsequent reductions `mean(tmp,3,'omitnan')` (line 373), `median(tmp,3,'omitnan')` (369), `limo_trimmed_mean(tmp,20)` (367) and `limo_harrell_davis(tmp,0.5)` (371) therefore average/median/trim over ALL trials including the injected zeros. `omitnan` does not remove them because they are 0, not NaN. Contrast the correct reference pattern in the ERP GUI branch (line 740: `tmp = squeeze(Yr(:,:,index))`) and the weighted branch (line 357), both of which keep only the n_selected trials. The mean becomes sum(selected)/n_total instead of mean(selected), and median/TM/HD are pulled toward 0.
- **Category:** `indexing/statistics`

#### 14. `limo_central_tendency_and_ci.m:727` — 🟠 HIGH · CONFIRMED · R2-new

**weighted_mean is read unconditionally but only assigned when Estimator1 is 'Mean'/'All', so choosing Trimmed mean / HD / Median crashes with an undefined-variable error.**

- **Why:** In the nargin==1 ERP branch, weighted_mean is set only inside `if strcmpi(Estimator1,'All') || strcmpi(Estimator1,'Mean')` at line 695. It is then read unconditionally at line 727 (`if strcmpi(weighted_mean,'yes')`), line 791, and line 854. limo_central_tendency_questdlg (verified) returns Estimator1 in {Mean, Trimmed mean, HD, Median}. When the user picks Trimmed mean, HD, or Median as the within-subject estimator, weighted_mean is never created and the first `strcmpi(weighted_mean,'yes')` at line 727 (or 787-791 for pooled) throws 'Unrecognized function or variable weighted_mean'.
- **Category:** `used-before-defined`

#### 15. `limo_check_neighbourghs.m:36` — 🟠 HIGH · CONFIRMED

**The 'Compute' branch captures the wrong output of limo_expected_chanlocs and leaves expected_chanlocs undefined, crashing the on-demand neighbour computation.**

- **Why:** limo_expected_chanlocs is declared as [expected_chanlocs, channeighbstructmat] = limo_expected_chanlocs(...). Lines 34 and 36 call it with a single output, so the variable named channeighbstructmat actually receives the FIRST return value, which is the expected_chanlocs STRUCT, not the neighbour matrix. Worse, the Compute branch never assigns the variable expected_chanlocs at all. Immediately after the if/else, line 40 does LIMO.data.expected_chanlocs = expected_chanlocs, referencing an undefined variable -> hard error. Even if that line were removed, line 41 would call unique() on a struct (channeighbstructmat holds a chanlocs struct) which errors, and LIMO.data.neighbouring_matrix would be set to a chanlocs struct rather than a binary matrix.
- **Category:** `data-handling`

#### 16. `limo_check_weight.m:404` — 🟠 HIGH · CONFIRMED

**Inner loop `for f=1:size(Yr,2)` reuses the outer subject-loop variable `f`, corrupting it for all subsequent per-subject logic in the Time-Frequency bias branch.**

- **Why:** The outer loop `for f=1:length(LIMO_files)` (line 178) uses `f` as the subject index throughout, including `W{f}`, `Bias{f}` and the terminal `if f==length(LIMO_files)` guards. In the Time-Frequency CheckBias branch, line 404 introduces `for f=1:size(Yr,2)` (a frame loop) that overwrites `f`. After this loop `f` equals size(Yr,2), not the subject index. Then `Bias{f} = tmp` (line 435) and `if f==length(LIMO_files)` (line 437) use the corrupted value, so results are stored under the wrong cell index and the final-subject aggregation either fires early, never, or on the wrong iteration.
- **Category:** `control-flow`

#### 17. `limo_combine_components.m:49` — 🟠 HIGH · CONFIRMED

**In the 'max' branch, `ind` indexes into `whichic` (via `var(icaact(whichic,:),...)`) but is used directly to index `data`, returning the wrong component.**

- **Why:** `varica = var(icaact(whichic,:), [], 2)` has length(whichic) rows, so `[tmp ind] = max(varica)` returns a position within `whichic`, not an absolute row index into `data`. `data(ind,:,:)` therefore selects the wrong component unless `whichic` starts at 1 and is contiguous. Same defect as the maxvar branch.
- **Category:** `indexing/dimension`

#### 18. `limo_combine_components.m:60` — 🟠 HIGH · CONFIRMED

**In the default 'maxvar' branch, `ind` is a position within `whichic` but is used to index `data` directly, returning the wrong component's time series.**

- **Why:** `varica` is built by looping `iComp = 1:length(whichic)`, so `[tmp ind] = max(varica)` yields `ind` in the range 1..length(whichic), i.e. a position within the selection list, NOT an absolute component/row index into `data`. The result must be `data(whichic(ind),:,:)`, but the code uses `data(ind,:,:)`. Whenever `whichic` is not exactly `1:k` starting at 1, the function silently returns the wrong component. Callers in limo_batch_design_matrix.m (lines 79/177/280) pass `which_ics = unique(Cluster_matrix.clust(c).ics(tmp))`, which are arbitrary cluster component indices, so this misfires in normal use. Because nargin==4 selects 'maxvar' by default, this is the branch actually exercised by the batch pipeline.
- **Category:** `indexing/dimension`

#### 19. `limo_concatcells.m:37` — 🟠 HIGH · CONFIRMED

**Size-consistency check falsely errors when two matrices to concatenate have identical sizes.**

- **Why:** The guard requires `sum(size(in{data}) == ref) ~= (last_dim-1)` to trigger the error, i.e. it demands that EXACTLY one dimension differ between in{data} and in{1}. But concatenating two matrices of identical size along the last dimension is a completely valid operation. When in{data} has the same size as ref, `size(in{data})==ref` is all-ones, so `sum(...) == last_dim`, which is not equal to `last_dim-1`, so the function raises 'data to concatenate are of different sizes' and aborts. The condition should test whether MORE than one dimension differs (i.e. `sum(size(in{data})==ref) < last_dim-1`), not whether exactly one differs. As written, any legitimate concatenation of equal-sized blocks crashes with a misleading message. (Secondary: if in{data} has a different number of dimensions than ref, `size(in{data})==ref` compares vectors of unequal length and throws an 'incompatible sizes' error instead of the intended message.)
- **Category:** `control-flow`

#### 20. `limo_contrast.m:231` — 🟠 HIGH · CONFIRMED

**For a user-specified contrast in bootstrapped repeated-measures (type 4), the matched contrast INDEX is taken as max() of a logical vector, which is always 1 when any match exists — so contrast{1} is always bootstrapped regardless of which contrast matched.**

- **Why:** cellfun returns a logical vector indicating which stored contrast equals the input. `max(...)` returns the maximum VALUE (0 or 1), not the position. This value is then used as the cell index at line 239 (`C = LIMO.contrast{index}.C`) and in the output filename (line 881). If the requested contrast is contrast #3, max still yields 1, so contrast #1 is evaluated and saved under ess_1 instead of the intended one.
- **Category:** `logic`

#### 21. `limo_contrast.m:298` — 🟠 HIGH · CONFIRMED

**Two-sided p for the WLS Time-Frequency T-contrast is computed from a mis-indexed t-value (a colon is missing), so the whole p-map is wrong or the call crashes.**

- **Why:** con is 4-D, NaN(nch,nfreq,ntime,5), with the t-values written to con(channel,freq,:,4) on the previous line. Line 298 reads con(channel,freq,4) with only three subscripts. In MATLAB the last subscript then folds dims 3 and 4 into a size (ntime*5) block, so index 4 selects linear position 4 = (time=4, stat=1), i.e. the C*Beta mean at time bin 4, not the t statistic. abs() of that single number is then broadcast over all time bins, so every time point gets the same nonsensical p. The non-TF branch (line 365) correctly writes con(channel,:,4).
- **Category:** `indexing/dimension`

#### 22. `limo_contrast.m:416` — 🟠 HIGH · CONFIRMED

**The IRLS F-contrast error term is written to all frames (colon) inside a per-frame loop, and dfe(channel) is used instead of the per-frame dfe, corrupting se, F and p for every frame but the last.**

- **Why:** Inside the frame loop (line 409) line 416 assigns the scalar E(frame)/dfe(channel) to ess(channel,:,end-3) using a colon, so each iteration overwrites the entire se column; the final saved se has every frame equal to the last frame's value. Lines 417-418 correctly index ...,frame,... The IRLS T-branch (line 374) uses the per-frame dfe(channel,frame), but here lines 416-418 use dfe(channel), which linear-indexes to dfe(channel,1) (first frame's Satterthwaite dfe) for all frames, so the F ratio and its fcdf p use the wrong denominator df on every frame.
- **Category:** `indexing/dimension`

#### 23. `limo_contrast.m:510` — 🟠 HIGH · CONFIRMED

**First-level contrast bootstrap files are written with the second-level '_desc-H0' suffix, but limo_stat_values reads first-level con/ess H0 files with the '...H0' suffix, so contrast MCC never finds the H0 file.**

- **Why:** For a first-level GLM contrast, limo_contrast builds the H0 filename unconditionally as `con_%g_desc-H0.mat` (line 510) / `ess_%g_desc-H0.mat` (line 513) and saves it (line 664 for con/ess) to H0/sub-XX_desc-con_1_desc-H0.mat. However limo_stat_values constructs the first-level H0 name as `sprintf('%scon_%sH0.mat',subname,effect_nb)` -> H0/sub-XX_desc-con_1H0.mat (line 255) and `sprintf('%sess_%sH0.mat',...)` -> ...ess_1H0.mat (line 273). The sibling condition/interaction effects use the '...H0.mat' suffix at level 1 (limo_glm_handling lines 651/684) matching the reader, so limo_contrast is the outlier: it uses the level-2 naming even at level 1. limo_display_results' existence check at line 121 also expects '...H0'.
- **Category:** `save-load-mismatch`

#### 24. `limo_contrast.m:631` — 🟠 HIGH · CONFIRMED

**The IRLS bootstrap T-contrast p-value calls tcdf on the still-NaN p slot instead of the t-value slot, so all H0 p-values are NaN.**

- **Why:** Line 630 writes the t-value to H0_con(channel,frame,1,B). Line 631 then computes 1-tcdf(squeeze(H0_con(channel,frame,2,B)),dfe), but dim-index 2 is the p slot, which is still its preallocated NaN. tcdf(NaN)=NaN, so the bootstrap null p-distribution for IRLS T-contrasts is entirely NaN. The non-IRLS branch at line 571 correctly reads index 1.
- **Category:** `data handling`

#### 25. `limo_contrast.m:1021` — 🟠 HIGH · CONFIRMED · R2-new

**Case 4 (bootstrapped rep-measures) gates the group*interaction H0 TFCE on exist('ess2','var'), but case 4 never creates a variable named 'ess2' (it uses H0_ess2), so the interaction bootstrap TFCE is never generated.**

- **Why:** In case(4) the group*interaction branch builds H0_ess and H0_ess2 (lines 946/948/949/995) and saves H0_ess2 as the interaction H0 file (filename2, line 1009). The TFCE handling block at 1016-1023 tries to also run TFCE for the interaction with `if exist('ess2','var') && ~exist(...tfce_H0_ess_gp_interaction...)`. No variable 'ess2' exists anywhere in case(4) — that name is only created in case(3) at line 787. Therefore exist('ess2','var') is always false in case(4), the branch is unreachable, and the interaction-effect H0 TFCE file is silently never computed. Any subsequent TFCE-corrected inference on the group x repeated-measures interaction contrast has no null distribution and will fail or fall back incorrectly.
- **Category:** `dead-code`

#### 26. `limo_contrast_sessions.m:117` — 🟠 HIGH · CONFIRMED

**The output contrast array `con` is allocated with a spurious 4th (trials) dimension, so the 3-subscript stat writes land in wrong positions and the saved con file is corrupt.**

- **Why:** `con = NaN(size(data1,1),size(data1,2),size(data1,3),5)` makes con a 4-D array [channels x frames x trials x 5]. But data1 is already reshaped to a 3-D [channels x frames x trials] cube and the code writes stats with only THREE subscripts: con(channel,:,1), con(channel,:,2), con(channel,:,3), con(channel,:,4), con(channel,:,5) (lines 147-150). When a 4-D array is indexed with 3 subscripts, MATLAB treats the last subscript as a linear index over the collapsed trailing dims (trials*5), column-major. So the third subscript k maps to (trial = mod(k-1,T)+1, stat = floor((k-1)/T)+1). For any T>1 the five statistics (mean, se, df, t, p) are scattered across different trial slices all within stat-slice 1 instead of into stat slices 1..5, and everything else stays NaN. The reference routine limo_contrast.m allocates the analogous non-TF con as NaN(size(Y,1),size(Y,2),5) (3-D), confirming the intended shape is [channels x frames x 5]. The in-file comment ('dim 3 = mean diff/se/df/t/p') also shows dim 3 should be the 5 stats, not trials.
- **Category:** `indexing/dimension`

#### 27. `limo_create_single_trials_gui.m:160` — 🟠 HIGH · CONFIRMED

**The ICA data-creation block is gated on scalp fields instead of the ICA fields, so ICA spec/ersp/itc requests are ignored and scalp requests wrongly trigger ICA processing.**

- **Why:** The guard for the ICA processing branch reads `strcmp(handles.ica_erp,'on') || strcmp(handles.scalp_spec,'on') || strcmp(handles.scalp_ersp,'on') || strcmp(handles.scalp_itc,'on')`. Only the first term correctly references an ICA field; the remaining three reference scalp_spec/scalp_ersp/scalp_itc. This is a copy-paste error from the scalp block at lines 149-150. As a result: (a) if the user selects only ICA spec, ERSP, or ITC (with ICA ERP off), the ICA branch never runs and no ICA single-trial data are produced; and (b) if the user selects a scalp spec/ersp/itc measure, the ICA branch runs even though no ICA measure was requested, invoking limo_create_single_trials with datatype 'ica'.
- **Category:** `control-flow-logic`

#### 28. `limo_design_matrix_tf.m:303` — 🟠 HIGH · CONFIRMED

**Full-factorial fallback references `basic_design`, which is never defined because its assignment is commented out on line 278.**

- **Why:** On line 278 the assignment `basic_design = x;` is commented out (`% basic_design = x;`). But lines 303 and 311 build the fallback design matrix with `X = [basic_design ones(size(Yr,3),1)];`. Since `basic_design` is never assigned anywhere in the function, both of these lines throw `Undefined function or variable 'basic_design'`. These lines run precisely when a full-factorial design is either too unbalanced to correct (line 300 branch) or over-specified with one observation per cell (line 308 branch) - exactly the cases the code is trying to handle gracefully. The non-TF sibling `limo_design_matrix.m` gets this right: it keeps `full_design = x;` uncommented on line 273 and uses `full_design` on lines 297/307. The TF version is broken.
- **Category:** `uninitialized-variable`

#### 29. `limo_display_results.m:1598` — 🟠 HIGH · CONFIRMED

**Second-level categorical course plots crash for any multi-factor design because a vector is used as an operand of the scalar-only && operator, and the column offset also lacks a +1.**

- **Why:** Line 1598 (and the identical guards at 1670, 1744, 1792) evaluate `regressor <= length(LIMO.design.nb_conditions) && LIMO.design.nb_conditions ~= 0`. When there is more than one categorical factor, LIMO.design.nb_conditions is a vector (the code itself anticipates this at lines 1600/1603 with `length(LIMO.design.nb_conditions)==1` and `sum(nb_conditions(1:regressor-1))`). `&&` requires scalar logical operands, so `regressor <= length(...) && [1 1]` throws 'Operands to the || and && operators must be convertible to logical scalar values.' Even if that were guarded, `start = sum(LIMO.design.nb_conditions(1:regressor-1))` is missing the `+1` needed to point at the first design column of the selected factor: for regressor=1 it yields start=0 (X(:,0) is an invalid index), and for regressor=2 with nb_conditions=[3 2] it yields start=3 selecting columns [3 4] instead of the correct [4 5].
- **Category:** `control-flow`

#### 30. `limo_eeg.m:158` — 🟠 HIGH · CONFIRMED

**Nested isfield uses a dotted field-name string so the primary Time/channels data-loading branch is always skipped.**

- **Why:** isfield(S,'a.b') tests for a single field literally named 'a.b'; it does NOT descend into S.a.b. Everywhere else in this file the nested form is written correctly: line 134 isfield(EEGLIMO.etc.datafiles,'icaerp'), line 191 icaspec, line 215 datspec, line 266 dattimef. Only line 158 is written as isfield(EEGLIMO.etc,'datafiles.daterp'), which can never be true, so for the most common analysis (Time / scalp channels) the correct daterp-loading path is dead code and control always falls through to the 'using a hack' else branch at line 171.
- **Category:** `data-handling`

#### 31. `limo_eeg.m:451` — 🟠 HIGH · CONFIRMED · R2-new

**WLS weight loop iterates 1:size(Yr,1) but indexes array(e) where array only holds non-NaN channels, causing an out-of-bounds crash when any channel is empty.**

- **Why:** `array = find(~isnan(Yr(:,1,1)))` (line 450) skips empty/NaN channels, so numel(array) can be less than size(Yr,1). The loop `for e = 1:size(Yr,1)` then evaluates `electrode = array(e)` (line 452), which indexes past the end of `array` once e exceeds the number of good channels. Additionally the weights are stored at `W(e,:)` (row e) rather than `W(electrode,:)`, so even before the crash the weights would be placed on the wrong channel rows. The loop bound should be `1:length(array)` and storage `W(electrode,:)`.
- **Category:** `indexing`

#### 32. `limo_eeg.m:452` — 🟠 HIGH · CONFIRMED · R2-new

**WLS multivariate weight loop reassigns the loaded 3D Betas array to a 2D limo_WLS output, corrupting it so the later Betas(:,t,:) assignment crashes.**

- **Why:** In case 4 multivariate, `load Betas` (line 434) loads the 3D coefficient array [channels x frames x params]. In the WLS branch the weight loop does `[Betas,W(e,:)] = limo_WLS(LIMO.design.X,squeeze(Yr(electrode,:,:))')`, overwriting Betas with limo_WLS's first output `b` (a 2D [params x frames] matrix). limo_WLS signature is `[b,W,rf] = limo_WLS(X,Y)`, so Betas is no longer the loaded 3D array. Then in the time loop, line 481 `Betas(:,t,:) = model.betas';` writes an [channels x params] slab into what is now a [params x frames] matrix, producing a size-mismatch assignment error. A scratch variable name (e.g. tmpB) should have been used instead of Betas.
- **Category:** `variable-clobbering`

#### 33. `limo_eeg.m:516` — 🟠 HIGH · CONFIRMED

**Multivariate covariate effects are populated from model.conditions instead of model.continuous, storing the wrong statistics.**

- **Why:** In the multiple-covariate branch (lines 515-521) all fields are read from model.conditions rather than model.continuous. The single-covariate branch (line 513) correctly assigns model.continuous. This copy-paste error means continuous-regressor multivariate stats are overwritten with condition-effect stats.
- **Category:** `stats-correctness`

#### 34. `limo_eeg_tf.m:351` — 🟠 HIGH · CONFIRMED

**In the bootstrap H0 loop the interaction effects are written with ':' (all bootstraps) instead of the loop index B in the 5th dimension, unlike the analogous conditions/covariates code.**

- **Why:** Inside `for B = 1:nboot`, the condition block (lines 339-344) and covariate block (lines 363-368) correctly index the boot dimension with B, e.g. `tmp_H0_Conditions(electrode,:,1,1,B) = model.conditions.F{B}`. But the interaction block writes `tmp_H0_Interaction_effect(electrode,:,1,1,:) = model.interactions.F{B}` (lines 351,352 for the single-interaction case and 355,356 for the multi-interaction case), using ':' in dim5 instead of B. tmp_H0_Interaction_effect is preallocated at line 304 with dim5 = nboot. The LHS `(electrode,:,1,1,:)` therefore has size [1 x frames x 1 x 1 x nboot] while the RHS `model.interactions.F{B}` is a per-frame vector of size [1 x frames]. The element counts (frames vs frames*nboot) do not match and the RHS is not a scalar.
- **Category:** `indexing/dimension`

#### 35. `limo_eeg_tf.m:425` — 🟠 HIGH · CONFIRMED

**Command-syntax `cd LIMO.dir` changes directory to a literal folder named 'LIMO.dir' rather than to the value of LIMO.dir, throwing an error after bootstrap that aborts before TFCE runs.**

- **Why:** Line 425 uses MATLAB command syntax, so `cd LIMO.dir` is parsed as `cd('LIMO.dir')` and attempts to enter a directory literally named 'LIMO.dir', not the path stored in the struct field LIMO.dir. This statement is outside the surrounding try/catch (the catch ends at line 424), so the error is not swallowed. Everywhere else the code correctly uses function syntax `cd(LIMO.dir)` (line 52).
- **Category:** `control-flow/io`

#### 36. `limo_eeg_tf.m:497` — 🟠 HIGH · CONFIRMED

**Single-channel H0 condition TFCE writes into channel index 2 instead of 1, injecting a phantom all-zero first channel into the null distribution.**

- **Why:** In the non-parallel branch for a single-channel design, the R2 code (line 459) writes `tfce_H0_score(1,:,:,:) = ...` and the covariate code (line 581) writes `tfce_H0_score(1,:,:,:) = ...`, but the condition code writes `tfce_H0_score(2,:,:,:) = limo_tfce(2,squeeze(H0_Condition_effect(:,:,:,1,:)),[])`. tfce_H0_score is not preallocated in this else branch, so assigning to row 2 creates a 2-row array whose row 1 is filled with default zeros and row 2 holds the actual single-channel null. Note `exist('parfor','file')` returns 0 (parfor is a language keyword, not a file), so on installations without a parfor file this else branch is the live path.
- **Category:** `indexing/dimension`

#### 37. `limo_get_effect_size.m:218` — 🟠 HIGH · CONFIRMED

**Repeated-measures main-effect/contrast Mahalanobis D is mis-parenthesized, dividing by size(X,1)*prod(rm) instead of size(X,1)/prod(rm), making the effect size wrong by a factor of prod(repeated_measure)^2.**

- **Why:** The docstring (line 46) and the two other Mahalanobis branches define N = subjects = size(LIMO.design.X,1)/prod(LIMO.design.repeated_measure) and compute effect_size = T2 ./ N (see line 237-238: N=size(X,1)/size(C,2); effect_size=T2./N, and line 242-244: N=size(X,1)/prod(repeated_measure); effect_size=T2./N). Line 218 instead writes it inline as `T2 ./ size(LIMO.design.X,1)/prod(LIMO.design.repeated_measure)`. Because ./ and / share precedence and are left-associative in MATLAB, this evaluates as (T2 ./ size(X,1)) ./ prod(rm) = T2/(size(X,1)*prod(rm)), not T2/(size(X,1)/prod(rm)). The two differ by a multiplicative factor of prod(rm)^2. This branch (the `~Rep_ANOVA_Interaction && ~Rep_ANOVA_Gp` case, lines 199-219) handles the most common repeated-measures outputs: Main_effect files and ess (contrast) files. Note also that the reachable code path for main effects is this buggy one; the final `else` branch at line 241-245 (which uses the correct single-divisor N) is dead code because the preceding if/elseif chain already covers every filename.
- **Category:** `numerics-operator-precedence`

#### 38. `limo_get_files.m:47` — 🟠 HIGH · CONFIRMED

**On non-Windows platforms a char (non-cell) `filter` argument crashes at `filter(:,2) = {';'}` because a cell cannot be assigned into a char array.**

- **Why:** Line 42 accepts whatever the caller passes as `filter` without enforcing a cell. On `~ispc` (macOS/Linux), line 47 does `filter(:,2) = {';'}`, which assigns a cell into subscripts of `filter`. If `filter` is a char row vector (e.g. '*txt'), MATLAB errors 'Conversion to char from cell is not possible'. The code assumes `filter` is always a cell array, but callers pass a bare char.
- **Category:** `data-handling`

#### 39. `limo_get_model_data.m:17` — 🟠 HIGH · CONFIRMED

**The variable `channel` is used to index Yr/Betas in every branch but is never defined (not an input, not assigned), so the function always errors.**

- **Why:** The function signature is `limo_get_model_data(LIMO, regressor, extra, p, freq_index)` — there is no `channel` input and `channel` is never assigned anywhere in the file. Yet every branch indexes with it: `Yr(channel,freq_index,:,index)` (17), `Yr(channel,:,index)` (19), `squeeze(Betas(channel,...))` (27,29), `squeeze(Yr.Yr(channel,...))` (43), `squeeze(Betas.Betas(channel,...))` (45). MATLAB raises 'Unrecognized function or variable channel' the first time any branch runs. The `p` input is passed but unused, suggesting the intended input list/indexing was mis-wired.
- **Category:** `control-flow`

#### 40. `limo_glm.m:679` — 🟠 HIGH · CONFIRMED · R2-new

**WLS-TF N-way (no-interaction) main effects store F_conditions transposed, so model.conditions.F ends up dimensioned [n_times x n_freqs x nb_factors] and the post-loop reshape loop indexes the wrong dimension and errors.**

- **Why:** For nb_factors>1 without interactions, line 679 does `model.conditions.F(:,freq,:) = F_conditions';`. F_conditions is nb_factors x n_times (line 648), so F_conditions' is n_times x nb_factors and the resulting array model.conditions.F is [n_times, n_freqs, nb_factors] (factor is the 3rd dim, not the 1st). The post-loop reshape at lines 864-866 iterates `for f = length(nb_conditions):-1:1` and calls `reshape(model.conditions.F(f,:,:), [n_freqs*n_times,1])`, treating the FIRST dimension as the factor index. model.conditions.F(f,:,:) has numel n_freqs*nb_factors, but the target is n_freqs*n_times, so reshape errors unless nb_factors==n_times. The df assignment at line 680 `model.conditions.df(:,freq,:) = [df_conditions ; repmat(dfe,...)]` is likewise shape-inconsistent with the preallocation [nb_factors x n_freqs x 2] (RHS is 2 x nb_factors), scrambling df/dfe or erroring. The same defect is duplicated in the interactions branch main-effects code at lines 741-742.
- **Category:** `dimension`

#### 41. `limo_glm.m:750` — 🟠 HIGH · CONFIRMED

**The WLS-TF two-factor interaction branch references an undefined variable E4, which crashes the analysis.**

- **Why:** In the WLS-TF case, the 'quick' interaction path computes HI = diag(T)' - H(1,:) - H(2,:) - E4'. The error sum-of-squares in this branch is stored in the variable E (computed at lines 564/566); E4 is never defined anywhere in the function (it only appears in a comment on line 230). MATLAB throws 'Undefined function or variable E4' at runtime. The analogous OLS/WLS branch (line 436) correctly uses E'. As a secondary defect, this branch also never computes pval_interactions (unlike line 439), so even if E4 were fixed the interaction p-values would remain NaN.
- **Category:** `numerics-undefined-variable`

#### 42. `limo_glm.m:883` — 🟠 HIGH · CONFIRMED

**The WLS-TF interaction reshape loop only processes the last interaction and writes results into model.conditions instead of model.interactions.**

- **Why:** In the final reshape block for WLS-TF interactions (lines 878-885) two copy-paste errors occur. First, 'for f = length(nb_interactions)' (line 879) iterates a single time with f equal to the count of interactions, rather than 'for f = 1:length(nb_interactions)', so only the last interaction is reshaped and lower-order interactions are dropped/left as 3D arrays. Second, the reshaped values are assigned to model.conditions.F and model.conditions.p (lines 883-884) instead of model.interactions.F/p. This overwrites the already-computed condition results with interaction data and leaves model.interactions.F/p in the wrong (unreshaped 3D) shape, corrupting both outputs.
- **Category:** `data-handling-copy-paste`

#### 43. `limo_glm.m:892` — 🟠 HIGH · CONFIRMED · R2-new

**WLS-TF single-covariate regression never assigns model.continuous.p, so the post-loop reshape crashes (and the in-loop df assignment is also malformed).**

- **Why:** In the WLS-TF case, the simple-regression branch (nb_factors==0 && nb_continuous==1) at lines 821-823 assigns only model.continuous.F and model.continuous.df inside the frequency loop; it never assigns model.continuous.p. After the loop, line 889 `isfield(model,'continuous')` is true (because .F exists), the code enters the `nb_factors==0 && nb_continuous==1` branch, and line 892 executes `model.continuous.p = reshape(model.continuous.p, [n_freqs*n_times,1])`, referencing a field that was never created -> 'Unrecognized field name p'. Contrast with the OLS/WLS simple-regression branch (lines 509-511) which correctly sets .F, .df AND .p. Separately, line 823 `model.continuous.df(:,freq) = [1 (size(Y,2)-rank(X))]` assigns a 1x2 row into a single-column slice of a not-yet-existing field, which is itself a shape-mismatched assignment; either way this code path is broken.
- **Category:** `missing-field/crash`

#### 44. `limo_glm.m:1110` — 🟠 HIGH · CONFIRMED

**IRLS 2-way interaction degrees of freedom use linear indexing into a 2-D df_conditions matrix instead of column indexing, yielding a wrong (and frame-dependent) interaction df.**

- **Why:** In the IRLS branch, df_conditions is preallocated as NaN(length(nb_conditions),size(Y,2)) (line 920), i.e. factors-by-frames. The 'quick way' interaction df is computed as prod(df_conditions(frame)) with a single (linear) index, so it returns ONE element rather than the product of the two factors' dfs. Column-major linear indexing means for frame=1 it returns df_conditions(1,1)=factor-1 df, for frame=2 it returns df_conditions(2,1)=factor-2 df at frame 1, etc. The correct expression is prod(df_conditions(:,frame)); indeed the general-interaction branch right below (line 1150) correctly uses df_conditions(interaction{f},frame), and the OLS analogue (line 437) correctly uses prod(df_conditions) on a 1xnf vector. The interaction df is therefore wrong, so F_interactions=(HI/df_interactions)/(E/dfe) and its p-value are wrong for every frame.
- **Category:** `numerics/stats-wrong-df`

#### 45. `limo_glm.m:1152` — 🟠 HIGH · CONFIRMED

**IRLS higher-order interaction p-values are written to an entire row instead of the current frame, so all frames get the last frame's p-value.**

- **Why:** Inside the IRLS per-frame loop, the interaction F value is correctly stored per frame with F_interactions(f,frame) (line 1151), but the p-value on line 1152 is assigned to pval_interactions(f,:) from a scalar RHS. This broadcasts the current frame's scalar p-value across every column of row f. On each successive frame the whole row is overwritten again, so after the loop pval_interactions(f,:) holds only the p-value of the final frame, replicated across all time/frequency frames. The reported interaction significance is therefore wrong at every frame except (by coincidence) the last.
- **Category:** `indexing-off-target-assignment`

#### 46. `limo_glm_boot.m:238` — 🟠 HIGH · CONFIRMED

**In the 1-way ANCOVA branch the bootstrap H0 F for the categorical effect is scaled by the full model df instead of the factor df, so the null distribution does not match the observed statistic computed in limo_glm.**

- **Why:** limo_glm.m (observed data) computes the condition effect as F_conditions = (diag(H)/df_conditions)./(E/dfe) at line 317, where df_conditions = trace(M'M)^2/trace((M'M)^2) equals the factor df (levels-1). limo_glm_boot.m computes the same effect for the H0 data at line 238 as F_conditions = (diag(H)/df)./(diag(E)/dfe), using df = rank(WX)-1 (line 188), which for an ANCOVA equals (levels-1)+nb_continuous. The p-value at line 239 then uses df_conditions, and the observed statistic uses df_conditions, but the bootstrapped statistic is divided by the larger df. Since bootstrap correction compares the observed statistic to the H0 distribution of the SAME statistic, mis-scaling the H0 F by df/df_conditions>1 shrinks the null distribution, making max-stat/cluster thresholds too low and the corrected inference anti-conservative (inflated false positives). Only the categorical+continuous (ANCOVA) 1-way branch is affected; the N-way branch at line 272 correctly uses df_conditions(f).
- **Category:** `wrong-df/error-term`

#### 47. `limo_glm_boot.m:767` — 🟠 HIGH · CONFIRMED · R2-new

**IRLS glm_iterate has the same defect: the full-model per-frame R is overwritten inside the interactions branch and then reused to compute the continuous-covariate F, corrupting covariate H0 statistics.**

- **Why:** In glm_iterate, R is the full-model residual-maker for the current frame (line 556, R = eye - WX*pinv(WX)). Inside the interactions branch it is reassigned at line 672 (reduced main-effects model) and again in the interaction loop at line 734 (R = eye - wx*pinv(wx)). WX (uppercase) is preserved. The continuous block at line 758 is an independent if that runs after the interactions branch, and at line 767 computes M = R0 - R with R0 from the full-model WX (line 765-766) but R stale from the last interaction sub-model. Thus F_continuous (line 770) and pval_continuous (line 771) for covariates in an IRLS N-way ANCOVA-with-interactions design are computed against an invalid projection, corrupting the null distribution.
- **Category:** `correctness`

#### 48. `limo_glm_handling.m:154` — 🟠 HIGH · CONFIRMED · R2-new

**WLS/IRLS per-channel df cells are indexed by absolute channel number instead of loop position, so any skipped/flat channel leaves an empty cell that makes the cell2mat consolidation crash.**

- **Why:** In the non-OLS branch, df info is stored as LIMO.model.model_df{channel} (and conditions_df/interactions_df/continuous_df) at lines 141-149, keyed by 'channel' = array(e), the ABSOLUTE channel index. At level 1, array = find(~isnan(Yr(:,1,1))) (line 41), which is non-contiguous whenever leading channels are NaN, and additionally any channel whose data are flat produces model=[] (lines 118-120) so its cell is never assigned. On the final iteration (e==size(array,1)) the code runs cell2mat(LIMO.model.model_df)' at line 154 (and again at 164, 175, 186). cell2mat over a cell array containing empty [] entries errors ('Dimensions of arrays being concatenated are not consistent'), aborting the whole first-level WLS/IRLS analysis at the very end after all channels were computed. Even when it does not error, the size checks at lines 155/165/176/187 compare against size(Yr,1)*2 (all channels) while the cell count equals length(array), so the df reshaping is silently misaligned when array != 1:nchan. The OLS branch is unaffected (it does not use cells). Correct code would key the cells by e (loop index) and size against numel(array).
- **Category:** `indexing-crash`

#### 49. `limo_glm_handling.m:717` — 🟠 HIGH · CONFIRMED

**Level-1 Covariate H0 file is saved with a spurious extra 'desc-' in its name, so downstream MCC code cannot locate it.**

- **Why:** subname already ends in '_desc-' (line 18), so `sprintf('%sdesc-Covariate_effect_%gH0',subname,i)` produces a filename like `sub-01_desc-desc-Covariate_effect_1H0.mat` with a doubled 'desc-'. The sibling Condition (line 651: `%sCondition_effect_%gH0`) and Interaction (line 684: `%sInteraction_effect_%gH0`) writers do NOT add that extra 'desc-', and the observed covariate file (line 342) is `%sCovariate_effect_%g.mat`. The reader that builds the H0 filename for bootstrap multiple-comparison correction, limo_stat_values.m line 225, expects `sprintf('%sCovariate_effect_%sH0.mat',subname,effect_nb)` = `sub-01_desc-Covariate_effect_1H0.mat` (no second 'desc-'). The names never match, so the covariate H0 distribution is not found.
- **Category:** `data-handling/filename-mismatch`

#### 50. `limo_itc.m:207` — 🟠 HIGH · CONFIRMED

**In the one-sample branch the 4th-dim write index sub+j (j=cond-1) collides across subjects whenever Ncond>=2, overwriting earlier subjects and leaving later slots NaN.**

- **Why:** Ybig is preallocated as nan(...,Nsub*Ncond). The intended layout should place subject `sub`, condition `cond` at a unique slot such as (sub-1)*Ncond+cond. Instead the code uses index sub+j with j running 0..Ncond-1, i.e. slot = sub+cond-1. For Ncond=2: subject 1 writes slots {1,2}, subject 2 writes {2,3}, etc. — slot 2 is written by both subjects (subject 1 cond2 then overwritten by subject 2 cond1), so data is corrupted and the highest slots stay NaN. The standard ITC 'double electrode count' case yields Ncond=2, so this is hit in normal use.
- **Category:** `indexing`

#### 51. `limo_itc.m:312` — 🟠 HIGH · CONFIRMED

**In the two-sample branch the 4th-dim write index sub-1+cond collides across subjects whenever a group has more than one condition (Nconds>1), corrupting Y1/Y2.**

- **Why:** Y1/Y2 are preallocated as nan(...,Nsub*Nconds(i)). The write index sub-1+cond only equals the correct unique slot when Nconds(i)==1. When conds1 or conds2 selects multiple conditions (e.g. conds2='2,3' -> Nconds(2)=2), subject 1 writes {1,2}, subject 2 writes {2,3}, overlapping at slot 2 and leaving trailing slots NaN, mislabeling and overwriting subject data fed into the two-sample t-test. Same defect at line 317 for Y2.
- **Category:** `indexing`

#### 52. `limo_itc_import_data.m:36` — 🟠 HIGH · CONFIRMED

**In the empty-`defaults.end` branch for Time analysis, the code assigns `LIMO.data.start = max(EEGLIMO.times)` instead of `LIMO.data.end`, clobbering the start value and leaving the end undefined.**

- **Why:** This branch handles the case where the user supplied no end time, so it should set the analysis window's upper bound: `LIMO.data.end = max(EEGLIMO.times)`. Instead it overwrites `LIMO.data.start` (already set correctly a few lines above) with the maximum time, and never sets `LIMO.data.end`. The result is a corrupted epoch window: start now equals the last sample time and end is missing/stale. This is a straightforward copy-paste error from the start-branch above.
- **Category:** `data-corruption`

#### 53. `limo_lateralization.m:110` — 🟠 HIGH · CONFIRMED

**The tfce null map is loaded from the non-tfce H0 t-test file, so tfce_H0_LI_Map.mat is saved containing ordinary bootstrap t-values instead of tfce-scored null data.**

- **Why:** Inside the `if tmp_LIMO.design.tfce ~= 0` block, line 107 correctly loads the tfce statistic (`tfce/tfce_one_sample_ttest_parameter_1.mat`), but line 110 loads `H0/H0_one_sample_ttest_parameter_1.mat` — the untransformed bootstrap H0 file (identical to line 100), NOT the tfce H0 file. limo_tfce_handling writes the tfce null under a `tfce`-prefixed / `tfceH0` name (e.g. `H0/tfce_H0_one_sample_ttest_parameter_1.mat`). The result saved at line 112 as `H0/tfce_H0_LI_Map.mat` therefore contains raw t H0 values, not tfce H0 scores. Any later tfce-based multiple-comparison correction on the lateralization map draws its null from the wrong distribution, invalidating tfce p-values.
- **Category:** `data-handling/copy-paste`

#### 54. `limo_mglm.m:270` — 🟠 HIGH · CONFIRMED

**In a pure 1-way categorical MANOVA (no covariates) the discriminant block uses Eigen_vectors_cond, which was never assigned on that path, crashing.**

- **Why:** For nb_factors==1, Eigen_vectors_cond is only produced in the `nb_conditions ~= 0 && nb_continuous ~= 0` branch via `[Eigen_vectors_cond,Eigen_values_cond]=limo_decomp(E,H)` (line 214). In the far more common `nb_conditions ~= 0 && nb_continuous == 0` branch (lines 203-204) only Eigen_values_cond is set (`Eigen_values_cond = Eigen_values_R2`); Eigen_vectors_cond is never defined. The discriminant block at line 267-280 then runs whenever there are enough observations and line 270 (`a = inv(chol(E))*Eigen_vectors_cond;`) references the undefined variable.
- **Category:** `uninitialized-variable`

#### 55. `limo_mglm.m:275` — 🟠 HIGH · CONFIRMED · R2-new

**Discriminant projection multiplies eigenvectors by Y in the wrong order/orientation, crashing the 1-factor MANCOVA path**

- **Why:** In the 1-way block, when covariates are present Eigen_vectors_cond is assigned (line 214) so the discriminant branch (else at 269) actually executes. `a = inv(chol(E))*Eigen_vectors_cond` is p-by-p (p = number of electrodes = size(Y,2)). The projection loop does `z(:,d) = a(:,d)'*Y`, i.e. (1-by-p) * (n-by-p). The inner dimensions (p and n) do not agree, so MATLAB throws 'Incorrect dimensions for matrix multiplication'. To obtain discriminant scores per observation the code must compute `Y*a(:,d)` (n-by-1). This is independent of the already-reported guard bug (267) and the no-covariate undefined-variable bug (270): those kill the *no-covariate* discriminant, whereas this crash bites the *covariate* (MANCOVA) case which otherwise reaches line 275.
- **Category:** `indexing-dimension`

#### 56. `limo_mglm.m:502` — 🟠 HIGH · CONFIRMED

**The N-way-with-interactions branch calls the non-existent function `repamt` and uses undefined variables wx/wY (and Wx/WY), so any design with interactions crashes before computing anything.**

- **Why:** Lines 500-504 (and duplicated at 688-690) read `if strcmp(method,'IRLS'); betas = pinv(Wx)*WY; else; w = repamt(W,1,size(Y,2)); betas = pinv(wx)*wY; end`. `repamt` is a typo for `repmat` (no such function exists in the toolbox — verified), and `wx`, `wY`, `Wx`, `WY` are never defined anywhere (the intended expressions are presumably `w.*x` and `w.*Y`). The `else` branch covers both OLS and WLS, so the failure is independent of method.
- **Category:** `crash`

#### 57. `limo_mglm.m:895` — 🟠 HIGH · CONFIRMED

**A continuous-only design (no factors) reaches the final update block referencing continuous F/p/df variables that are never created, causing an undefined-variable error.**

- **Why:** When nb_factors==0 and nb_continuous>0, control enters the `if nb_factors==0` branch at line 766 which computes ONLY the R2 quantities; it never assigns F_continuous_Pillai, pval_continuous_Pillai, F_continuous_Roy, pval_continuous_Roy, df_continuous, or dfe_continuous (those are only set in the `else` branch at lines 822-856 when factors are present). The final block at line 894 `if nb_continuous > 0` then reads F_continuous_Pillai (line 895) etc., which do not exist.
- **Category:** `crash-undefined-variable`

#### 58. `limo_mstat_values.m:214` — 🟠 HIGH · CONFIRMED

**The Covariate_effect branch reads the variable R2 and loads H0_R2.mat, but only the Covariate_effect variable is loaded, so R2 is undefined and the call errors.**

- **Why:** At line 49 `load(FileName)` loads the selected file; when FileName matches 'Covariate_effect...' (guarded at line 211) the loaded workspace variable is `Covariate_effect`, not `R2`. Lines 214/216/227/229/241/245/253/257 all reference `R2` and MCC_data is set to 'H0_R2.mat', and the titles say 'R^2'. This is a copy-paste of the R2 branch that was never adapted: `R2` is undefined in this branch, so evaluating squeeze(R2(:,2)) throws 'Undefined function or variable R2'. Even if R2 happened to exist, the covariate statistics (and their H0 file) would never be read, producing results for the wrong effect.
- **Category:** `data handling`

#### 59. `limo_power_spec_from_erp.m:40` — 🟠 HIGH · CONFIRMED

**The function signature takes (EEG,options) but the body reads legacy positional args via nargin, so options is never parsed and winsize is left undefined when the documented 2-arg form is used, crashing at spectopo.**

- **Why:** The signature is `function [...] = limo_power_spec_from_erp(EEG,options)` (max nargin = 2), yet the defaults use `if nargin<4`, `if nargin<3`, `if nargin<2`. When the function is called as documented with (EEG,options), nargin==2: the `nargin<2` guard is false, so `winsize` is never assigned. Line 50 then references `winsize` in the spectopo call -> 'Undefined function or variable winsize'. Separately, none of options.maxfreq/options.winsize/options.power_dataset_savename are ever read, so even the 1-arg call silently ignores the user's requested maxfreq and always uses 50 Hz and winsize=EEG.srate. The whole `options` mechanism is dead and the documented interface is broken.
- **Category:** `control-flow`

#### 60. `limo_prederror.m:59` — 🟠 HIGH · CONFIRMED · R2-new

**Time-Frequency data (4D) is trial-shuffled with only three subscripts, mis-indexing/collapsing the trials dimension and later crashing.**

- **Why:** For Time-Frequency analyses Yr is a 4D cube [channels x freq x time x trials] — the code proves this itself: the placeholder at lines 48-49 allocates NaN(size(Yr,1),size(Yr,2),size(Yr,3),3,k) and line 69 indexes Data(channel,freq,:,testindex) with four subscripts. But line 59 does `Data = Yr(:,:,shuffling_index)` with only three subscripts. On a 4D array the third subscript spans the merged (time*trials) dimension, so shuffling_index (length = number of trials) picks a garbage subset and the result is a 3D array [channels x freq x N]. Design is shuffled correctly by trial at line 60, so Data and Design become misaligned, and line 55's array/find still assumes 4D. limo_prederror never calls limo_tf_4d_reshape, so nothing flattens Yr first. It should be `Yr(:,:,:,shuffling_index)` for the Time-Frequency case.
- **Category:** `indexing/dimension`

#### 61. `limo_random_effect.m:319` — 🟠 HIGH · CONFIRMED · R2-new

**N-Ways ANOVA menu option is padded with spaces, so the string passed to limo_random_select fails its exact-match validation and errors out.**

- **Why:** In ANOVA_Callback the questdlg option for the N-way model is the literal padded string '     N-Ways ANOVA     ' (line 319). Whatever the user picks becomes `answer`, and `answer` is passed verbatim as the stattest argument to limo_random_select at lines 338/341. limo_random_select validates it at line 88-92 with tests = {...,'N-Ways ANOVA',...} and `if sum(strcmpi(stattest,tests))==0, error('input argument error, stat test unknown'), end`. strcmpi is an exact (case-insensitive but not trimmed) comparison, and '     N-Ways ANOVA     ' != 'N-Ways ANOVA' because of the leading/trailing spaces, so the sum is 0 and limo_random_select throws. The 'ANCOVA' and 'Repeated Measures ANOVA' options are unpadded and match, so only the N-way path is broken. Note the internal update_dir dispatch at line 323 uses the same padded literal so it works there, masking the problem until limo_random_select is reached.
- **Category:** `wrong-argument-value`

#### 62. `limo_random_robust.m:708` — 🟠 HIGH · CONFIRMED

**N-way ANOVA case calls the non-existent function 'filenames' (typo for 'fieldnames') when data is passed as a file name, causing an undefined-function crash.**

- **Why:** Line 708 uses filenames(data) but no such function exists in MATLAB or in the toolbox (verified: no filenames.m anywhere in the repo). The intended call is fieldnames(data) as used in every other case. This branch runs only when the data argument is a char filename, so it is a latent crash on that code path.
- **Category:** `data handling`

#### 63. `limo_random_robust.m:1342` — 🟠 HIGH · CONFIRMED

**Bootstrap H0 loop for repeated-measures ANOVA with a between-group factor indexes the group design matrix X with linear indexing instead of row indexing, collapsing it to a single column and crashing/mis-computing the null.**

- **Why:** In the main analysis the between-group design is sliced correctly as XB = X(find(~isnan(tmp(1,:,1))),:) (line 1087), producing an [N x (k+1)] matrix. In the H0 bootstrap parfor (line 1342) the ',:' is missing, so X(find(...)) uses linear (column-major) indexing. For a full-data channel find(...)=1:N and X(1:N) returns just the first column of X (group-1 indicator), an [N x 1] vector, not the [N x (k+1)] design. This wrong XB is passed to limo_rep_anova as the group design (size check at limo_rep_anova line 133 passes because size(gp,1)==size(XB,1)), where case 3/4 then does X(:,1:k) with k>=2 columns on a 1-column matrix.
- **Category:** `indexing/dimension`

#### 64. `limo_random_robust.m:1402` — 🟠 HIGH · CONFIRMED · R2-new

**Bootstrap H0 save for Repeated-Measures ANOVA uses squeeze() which drops the singleton channel dimension for single-channel analyses, causing a size-mismatch assignment error.**

- **Why:** At line 1402 `H0_Rep_ANOVA(:,:,:,:) = squeeze(tmp_boot_H0_Rep_ANOVA(:,:,i,:,:));` (and identically at line 1413 for `H0_Rep_ANOVA_Interaction_with_gp`). `tmp_boot_H0_Rep_ANOVA` is [channels,frames,nb_effects,2,bootstrap]. When there is only 1 channel, `squeeze(...(:,:,i,:,:))` collapses BOTH the singleton channel dim (dim 1) and the singleton effect dim (dim 3), yielding a [frames,2,bootstrap] 3-D array, while the LHS `H0_Rep_ANOVA` was preallocated 4-D as NaN(1,frames,2,bootstrap). The explicit `(:,:,:,:)` assignment then fails with a left/right size mismatch. The authors already knew about this: the corresponding observed-effect save at lines 1169-1170 deliberately uses `reshape` 'instead of squeeze in case there is only 1 channel', but the bootstrap/H0 saves here still use squeeze.
- **Category:** `indexing/dimension error`

#### 65. `limo_random_select.m:2013` — 🟠 HIGH · CONFIRMED · R2-new

**getdata case 1's single-vs-multi guard tests electrode length, so a scalar Component routes to the multi-channel branch and is indexed with the subject index, crashing for >1 subject.**

- **Why:** For one-sample t-test / regression with Type='Components' and '1 channel/component only', LIMO.design.electrode is [] (only LIMO.design.component is set by match_channels). The guard at line 2013 `if length(LIMO.design.electrode)==1` is therefore false even for a single component, so execution falls into the 'multiple single channels' else-branch (line 2046). There, lines 2065/2067/2071/2073 index `tmp(LIMO.design.component(i),...)` using the per-subject loop index i. A single scalar component works for i=1 but errors at i=2.
- **Category:** `indexing-error`

#### 66. `limo_random_select.m:2135` — 🟠 HIGH · CONFIRMED · R2-new

**In getdata case 2, the Component single-channel branches reference LIMO.design.electrode instead of LIMO.design.component, so component analyses crash or return empty.**

- **Why:** getdata(2,...) serves two-samples t-test, N-Ways ANOVA and ANCOVA. For LIMO.Type='Components' with '1 channel/component only', the guard at line 2135 tests `length(LIMO.design.electrode)==1`, but match_channels never sets LIMO.design.electrode for Components (it sets LIMO.design.component, lines 1874/1901); electrode stays [] (init line 120). So the guard is always false and control drops to the 'multiple single channels' branch, where lines 2187/2189/2193/2195 index `tmp(LIMO.design.electrode(subject_nb),...)` = `[](subject_nb)`. The single-channel branch (lines 2153/2155/2159/2161) is also wrong, using `tmp(LIMO.design.electrode,...)`. Compare getdata case 1, which correctly uses LIMO.design.component (lines 2031/2065/2071).
- **Category:** `wrong-field-name`

#### 67. `limo_rep_anova.m:229` — 🟠 HIGH · CONFIRMED

**For single-frame data (size(Data,1)==1), squeeze(nanmean(Data,2)) returns a [p x 1] column instead of [1 x p], so cases 2/3/4 index it wrongly and crash; only case 1 guards this.**

- **Why:** Case 1 explicitly special-cases a single time/freq frame (line 202 `if size(Data,1) == 1`). Cases 2, 3 and 4 do not. With Data=[1 x n x p], nanmean(Data,2) is [1 x 1 x p] and squeeze() collapses BOTH leading singletons to give a [p x 1] column vector, not the [f x p] = [1 x p] the loop code assumes. Then case 2 line 236 does `y(frame,:)'` with frame=1 -> that is the scalar y(1,1); `c*scalar` scalar-expands to a [df x p] matrix, and the quadratic form evaluates to a [p x p] matrix that is assigned into the scalar slot Tsquare(frame) -> error. Case 3 (line 292 `yp = squeeze(nanmean(Data,2))'` then line 296 `C*yp(:,frame)`) and case 4 (line 349/363 `y=squeeze(nanmean(Data,2))'` then `c*y(:,frame)`) fail the same way because the transpose of the [p x 1] column is [1 x p] and y(:,1) is a scalar.
- **Category:** `indexing/dimension`

#### 68. `limo_results.m:312` — 🟠 HIGH · CONFIRMED

**Two-sample bootstrap-on-demand loads the wrong, non-existent file 'Yr1.mat' twice instead of the two group files 'Y1r.mat' and 'Y2r.mat'.**

- **Why:** For a two-samples t-test result, check_boot_and_tfce calls limo_random_robust with type=2, which expects varargin{2}=data1 and varargin{3}=data2 (see limo_random_robust.m case {2}, lines 268-281). The saved group data files are named 'Y1r.mat' and 'Y2r.mat' (limo_random_select.m lines 586-587/806-807), but this call passes the string 'Yr1.mat' — a filename that does not exist — and passes it for BOTH group arguments. So the load in limo_random_robust fails outright (Unable to read file 'Yr1.mat'). Even if the name were corrected to Y1r.mat, passing the same file for both groups would make data1==data2 and produce a degenerate/zero-difference two-sample bootstrap.
- **Category:** `data-handling`

#### 69. `limo_results.m:315` — 🟠 HIGH · CONFIRMED

**Paired-samples bootstrap-on-demand loads the wrong, non-existent file 'Yr1.mat' twice instead of the paired files 'Y1r.mat' and 'Y2r.mat'.**

- **Why:** For a paired t-test result, limo_random_robust type=3 expects varargin{2}=data1 and varargin{3}=data2 (case {3}, lines 438-451). The paired data are stored as 'Y1r.mat' and 'Y2r.mat', but this call passes 'Yr1.mat' (nonexistent) for both arguments. The load fails; and even corrected the two conditions would be identical, giving zero paired differences.
- **Category:** `data-handling`

#### 70. `limo_robust_ci.m:45` — 🟠 HIGH · CONFIRMED

**In the 3-argument (direct data) path, a single-electrode 2D input is replaced by an all-NaN array without ever copying the real data into it.**

- **Why:** When data is passed directly and is 2D (one electrode), lines 45-46 create `tmp = NaN(1,size(data,1),size(data,2))` and then do `data = tmp`, but never assign the original values into tmp (there is no `tmp(1,:,:) = data;`). The genuine data is overwritten with NaNs. Contrast with the correct pattern used later at lines 256-257 (`tmp_data(1,:,:) = squeeze(...)`). Consequently every robust estimate (Trimmed mean / HD / Median) computed in the Analysis section is NaN. The stray `clear Data` (capital D) clears a nonexistent variable, further evidence the copy line was dropped.
- **Category:** `data-handling`

#### 71. `limo_robust_ci.m:49` — 🟠 HIGH · CONFIRMED

**The estimator-type check in the 3-argument path references an undefined variable `Estimator` (should be `Estimator2`), crashing for every estimator except 'Trimmed mean'.**

- **Why:** Lines 49-50 read `strcmp(Estimator2,'Trimmed mean') || strcmp(Estimator,'HD') || strcmp(Estimator2,'Median') || strcmp(Estimator,'All')`. The variable set on line 48 is `Estimator2`; `Estimator` is never defined. Because `||` short-circuits, passing Estimator2='Trimmed mean' evaluates the first clause true and avoids the undefined reference. But for Estimator2='HD', 'Median', or 'All', the first clause is false and MATLAB evaluates `strcmp(Estimator,'HD')`, throwing 'Unrecognized function or variable Estimator' before the correct 'Median' clause is even reached.
- **Category:** `control-flow`

#### 72. `limo_robust_rep_anova.m:103` — 🟠 HIGH · CONFIRMED

**The robust repeated-measures ANOVA computes the trimmed mean across the wrong dimension (measures instead of subjects), producing wrong-shaped means that mismatch the contrast/covariance and crash or silently corrupt the test.**

- **Why:** Data is [frames x subjects x measures] (confirmed by caller limo_random_robust line 1082 and by the non-robust limo_rep_anova line 201 which uses nanmean(Data,2) to average over subjects, keeping the p measures). limo_trimmed_mean's second argument is PERCENT, not a dimension, and it always trims/averages over dim 3 (see limo_trimmed_mean.m lines 8, 57-65). So case 1 (line 103) calls limo_trimmed_mean(Data,2) which trims 2% over the measures dimension and averages it away, returning y with shape [frames x subjects] instead of [frames x measures]; case 2 (line 124) has the identical defect with 20%. The covariance S is correctly [p x p] over subjects (line 97 limo_robust_cov), but y no longer has length p, so C*y(time,:)' (C is (p-1) x p) is a dimension mismatch. The intent (matching limo_rep_anova) requires averaging over subjects while preserving the p measures.
- **Category:** `indexing/dimension`

#### 73. `limo_robust_rep_anova.m:124` — 🟠 HIGH · CONFIRMED

**limo_trimmed_mean is called to compute the cell means but it reduces the measures dimension (dim 3), not the subjects dimension, and its 2nd argument is a trim-percentage that is passed inconsistently (2 vs 20).**

- **Why:** Data is [f frames x n subjects x p measures]; the cell means to compare must be averaged over subjects (dim 2), exactly as the non-robust limo_rep_anova does with squeeze(nanmean(Data,2)) -> [f x p]. But limo_trimmed_mean ALWAYS trims/averages over the last (3rd) dimension (its code: n=size(data,3); datasort=sort(data,3); TM=nanmean(datasort(:,:,g+1:n-g),3)), and its second argument is the trimming PERCENT, not a dimension. So limo_trimmed_mean(Data,20) at line 124 (and limo_trimmed_mean(Data,2) at line 103) returns a [f x n] matrix of each subject's trimmed mean across the p measures -- the wrong quantity and the wrong shape. Additionally the two call sites disagree: line 103 passes 2 (2% trim) while line 124 passes 20 (20% trim), and neither matches, since limo_robust_cov uses 20% winsorization -- so even the intended robust estimator is internally inconsistent.
- **Category:** `dimension-reduction`

#### 74. `limo_semi_partial_coef.m:100` — 🟠 HIGH · CONFIRMED

**isfield checks the misspelled field name 'boostrap' instead of 'bootstrap', so the entire H0/bootstrap/TFCE inference block never executes.**

- **Why:** Line 100 guards the whole under-H0 and TFCE section with `if isfield(LIMO.design,'boostrap')` (note the missing 't'). The actual LIMO field is `LIMO.design.bootstrap`, which is what line 101 reads (`LIMO.design.bootstrap == 1`). Because `isfield(LIMO.design,'boostrap')` is essentially always false, the guarded block (lines 101-174) is dead: no H0 semi-partial coefficients and no TFCE scores are ever computed or saved. Any downstream correction that expects H0_semi_partial_coef_*.mat / tfce_* files will then fail or fall back silently to no correction.
- **Category:** `data handling`

#### 75. `limo_semi_partial_coef.m:213` — 🟠 HIGH · CONFIRMED

**The interactions loop uses the stale index variable i from the categorical loop instead of its own loop variable j, giving wrong reduced-model column sets or an out-of-bounds crash.**

- **Why:** The interactions loop runs `for j=1:length(LIMO.design.nb_interactions)` (line 211) but indexes `LIMO.design.nb_interactions(i)` on lines 213, 215 and 220, where i is left over from the categorical loop `for i=1:length(LIMO.design.nb_conditions)` and equals length(nb_conditions). This selects the wrong interaction size (or errors if i>length(nb_interactions)), and the j==1 branch `effect = index:LIMO.design.nb_interactions(i)` does not use the running `index` offset correctly, so `effect` typically becomes an empty range (start>stop) and no interaction regressor set is built; index is also incremented by the wrong amount, corrupting subsequent continuous-variable column selection.
- **Category:** `control flow`

#### 76. `limo_semi_partial_coef.m:280` — 🟠 HIGH · CONFIRMED

**The partial-F p-value passes the wrong degrees of freedom to fcdf (model df as numerator, restriction count as denominator) instead of (restrictions, residual df), producing wrong p-values.**

- **Why:** The F statistic on line 279 is F = (N-df-1)*deltaR2 / ((df-df_reduced)*(1-R2)) = deltaR2/(1-R2_full) * (N-p_full)/q, i.e. a standard nested partial-F distributed as F(q, N-p_full) where q = df-df_reduced (the number of removed columns) and N-p_full = N-df-1 (residual df). But line 280 computes `1 - fcdf(F, df, dfe)` with df = rank(full)-1 (the full model df) as the numerator df and dfe = df-df_reduced = q as the denominator df. The correct call is `1 - fcdf(F, dfe, N-df-1)`. Both arguments are wrong: numerator should be q (=dfe), denominator should be N-df-1. The identical error is repeated in the IRLS branch at line 311.
- **Category:** `numerics/stats`

#### 77. `limo_stat_values.m:201` — 🟠 HIGH · CONFIRMED

**After fileparts strips the extension, the R2 dispatch test contains(FileName,'R2.mat') can never match, so R2 maps never get thresholded at any MCC level.**

- **Why:** Line 65 (`[~,FileName,ext] = fileparts(FileName);`, added in commit 3256402 '1st level plot fixes') removes the '.mat' extension, leaving FileName='R2' (2nd level) or 'sub-XX_desc-R2' (1st level). Both R2 branches (line 121 for Time-Frequency and line 201 for the other case) still test `contains(FileName,'R2.mat')`. Since the search string 'R2.mat' is longer than / not a substring of the stripped name, the test is always false. Every other branch searches for substrings without the extension (e.g. 'Condition_effect','con_','ess_') and still works; only the two R2 branches carry the stale '.mat'. When neither R2 branch fires, M/Pval/MCC_data are never set, so all four correction blocks (MCC==1 uncorrected at 283, cluster at 290, max at 353, tfce at 384 which all require ~isempty(M)) are skipped and the function returns empty M and mask.
- **Category:** `save-load-mismatch`

#### 78. `limo_stat_values.m:328` — 🟠 HIGH · CONFIRMED · R2-new

**t-test cluster correction never squares T because the guard tests lowercase 'ttest' while t-test filenames use capital 'Ttest'**

- **Why:** In the MCC==2 cluster branch the code does `if contains(FileName,'ttest') || contains(FileName,'LI_Map')` then calls `limo_clustering(M.^2,Pval,bootM.^2,bootP,...)`, else calls it on the raw signed values. LIMO saves t-test files as 'One_Sample_Ttest_parameter_N', 'Paired_Samples_Ttest_...', 'Two_Samples_Ttest_...' (capital 'Ttest', confirmed in limo_random_robust.m lines 171/337/506). MATLAB `contains` is case-sensitive, so `contains(FileName,'ttest')` is always FALSE for real t-test files. The dispatch that actually sets M at line 180 correctly uses capital 'Ttest', so M (signed T values) is populated and reaches line 328, but the squaring branch is dead. Cluster correction therefore runs on signed T / signed bootT instead of T^2, so negative-going effects fall below threshold and the cluster-forming statistic is wrong.
- **Category:** `statistical-correctness`

#### 79. `limo_tfce.m:720` — 🟠 HIGH · CONFIRMED

**The 3D negative-value branch builds `thresholded_maps` with 2D/3D indexing that is dimensionally incompatible with the 4D `pos_tfce`/`neg_tfce` arrays, crashing whenever the second output is requested for signed 3D data.**

- **Why:** In case{3} (3D data), subtype{1}, the mixed-sign branch produces `pos_tfce` and `neg_tfce` of size (x,y,z,l) (4-D: channels x freq x time x thresholds). The nargout==2 block at lines 719-725 was copy-pasted from the 1D/2D versions and never updated for 4-D. `size(pos_tfce,3)` and `size(neg_tfce,3)` return z (the time dimension), NOT the number of thresholds l. So `thresholded_maps = NaN(size(pos_tfce,1),size(pos_tfce,2), size(neg_tfce,3)+size(pos_tfce,3))` allocates an (x, y, 2*z) 3-D array. The subsequent `thresholded_maps(:,:,size(neg_tfce,3):-1:1) = neg_tfce` selects x*y*z destination elements but `neg_tfce` supplies x*y*z*l elements, so for any l>1 (always true in practice, since l is the number of TFCE height steps, ~200) MATLAB throws 'Unable to perform assignment because the left and right sides have a different number of elements' and the whole TFCE computation aborts. The positive-only 3D branch (lines 654-657) is correct (uses 4-D `= tfce` and a triple-squeeze trim); only this signed branch is broken. Contrast with the 2D branch (lines 449-455) which is correct because there the tfce arrays are genuinely 3-D.
- **Category:** `indexing/dimension`

#### 80. `limo_tfce_handling.m:219` — 🟠 HIGH · CONFIRMED · R2-new

**Single-channel time-frequency con/t-test H0 TFCE indexes a pre-squeezed 3D array with a spurious 4th subscript, crashing for every bootstrap after the first.**

- **Why:** In the con/One-sample/Two-samples/Paired branch, line 217 does H0_tval = squeeze(H0_tval(:,:,:,end-1,:)). For a single-channel analysis H0_tval starts as [1 x freq x time x 5 x nboot]; selecting end-1 gives [1 x freq x time x 1 x nboot] and squeeze removes BOTH the leading channel singleton and the stat singleton, yielding a 3-D array [freq x time x nboot]. The parfor body at line 219 then calls limo_tfce(2,H0_tval(:,:,:,b),[],0). Indexing a 3-D array with four subscripts requires the 4th (b) to reference a singleton trailing dimension: b=1 returns the ENTIRE [freq x time x nboot] cube (all bootstraps, not slice b), and b>=2 throws 'Index in position 4 exceeds array bounds'. Even the b=1 case then mismatches the assignment tfce_H0_score(1,:,:,1) which expects [1 x freq x time]. The correct slice is H0_tval(:,:,b). Contrast with the R2 branch (line 153) and F branch (line 289), which squeeze inside the loop and index the correct dimension. The observed-data path for single channels works; only this H0 path is broken.
- **Category:** `indexing/dimension`

#### 81. `limo_tfce_handling.m:226` — 🟠 HIGH · CONFIRMED · R2-new

**Single-channel non-TF con/t-test H0 TFCE both mis-sizes tfce_H0_score and indexes the wrong bootstrap dimension after squeezing away the channel singleton.**

- **Why:** In the same con/t-test branch, non-time-frequency single-channel case: line 223 does H0_tval = squeeze(H0_tval(:,:,end-1,:)). H0_tval starts [1 x time x 5 x nboot]; after selecting end-1 and squeezing, both the channel singleton and stat singleton vanish, giving a 2-D array [time x nboot]. Two defects follow: (1) line 224 preallocates tfce_H0_score = NaN(1,size(H0_tval,2),nboot) but size(H0_tval,2) is now nboot (not time), so the array is NaN(1,nboot,nboot) with the wrong middle dimension. (2) line 226 calls limo_tfce(1,H0_tval(:,:,b),neighbouring_matrix,0): H0_tval(:,:,b) on a 2-D array is the whole matrix for b=1 and out-of-bounds for b>=2. The correct slice is H0_tval(:,b). Note the TF sibling (line 216) preallocates BEFORE the squeeze so its size is right, but this non-TF path preallocates AFTER the squeeze (line 224), compounding the error.
- **Category:** `indexing/dimension`

#### 82. `limo_tfce_handling.m:289` — 🟠 HIGH · CONFIRMED

**Single-channel time-frequency null TFCE uses type 1 (1D) instead of type 2 (2D freq x time), silently mis-computing the H0 distribution relative to the observed statistic.**

- **Why:** For a single channel (size(H0_Fval,1)==1) Time-Frequency F/ess file, the observed data is TFCE'd with type 2 on a [freq x time] map (line 264: limo_tfce(2,squeeze(Fval(:,:,:,1)),[])). The corresponding H0 call on line 289 instead passes type 1 with squeeze(H0_Fval(:,:,:,1,b)), which is a 2D [freq x time] matrix. In limo_tfce type 1, isvector([freq x time]) is false, so it takes subtype 2 with [x,b]=size(data) -> x=freq, b=time, treating each time column as an independent 1D vector over frequency and returning NaN(1,x,b)=[1,freq,time], which fits tfce_H0_score(1,:,:,b) so it does not error. Instead of a single 2D freq-by-time TFCE it performs many independent 1D-over-frequency TFCEs, one per time point. The resulting null is on a different scale and structure than the observed type-2 map, corrupting the corrected inference. It also passes neighbouring_matrix where the observed call passed [] (single-channel data has no spatial neighbourhood).
- **Category:** `resampling/permutation`

#### 83. `limo_tfcluster_make.m:56` — 🟠 HIGH · CONFIRMED · R2-new

**spm_bwlabel is called with a logical argument (no double() cast) on its preferred code path, which crashes because spm_bwlabel requires a double input.**

- **Why:** Lines 56 (4D branch) and 87 (3D branch) call spm_bwlabel(squeeze(bootp(...))<=alphav, 6). The first argument is a logical array. The spm_bwlabel MEX gateway requires a double-precision input and errors on non-double data. Every sibling function casts explicitly: limo_ecluster_make.m:58, limo_ecluster_test.m:61, and limo_tfcluster_test.m:60/92 all use spm_bwlabel(double(...),6). limo_tfcluster_make is the only one that omits the cast, and spm_bwlabel is the FIRST-preferred branch (exist('spm_bwlabel','file')==3 is checked before bwlabeln), so on any system that has SPM installed the H0 threshold computation aborts immediately.
- **Category:** `crash-type-error`

#### 84. `limo_tfcluster_test.m:44` — 🟠 HIGH · CONFIRMED · R2-new

**The default-alpha guard tests nargin<3 but alphav is the 4th argument, so calling with the documented default (3 args) leaves alphav undefined and the function crashes.**

- **Why:** Signature is limo_tfcluster_test(orif,orip,th,alphav). The guard at line 44 reads `if nargin < 3; alphav = 0.05; end`, but to default the 4th argument it must test `nargin < 4`. When the function is called with 3 arguments (orif,orip,th) — the documented way to accept the default alpha of 0.05 — nargin==3, `3 < 3` is false, so alphav is never assigned. The very next use at line 54 (U = round((1-alphav)*b)) then references an undefined variable and errors. There is no other assignment to alphav anywhere in the function.
- **Category:** `default-arg-nargin`

#### 85. `limo_trimmed_mean.m:103` — 🟠 HIGH · CONFIRMED

**The nested tvar function divides percent by 100 a second time, so the winsorized trimmed standard error and the trim count g are computed with ~0% trimming, producing wildly wrong confidence intervals.**

- **Why:** In limo_trimmed_mean, percent is converted to a fraction on line 32 (e.g. 20 -> 0.2). That fraction is passed to tvar on line 72. Inside tvar, line 103 computes g=floor((percent/100)*size(x,2)) = floor(0.002*ncols) and line 112 computes k=(1-2*percent/100)^2 = (1-0.004)^2 = 0.992. Both are wrong: they treat the already-fractional percent (0.2) as if it were on a 0-100 scale, dividing by 100 again. The correct values are g=floor(0.2*ncols) and k=(1-2*0.2)^2=0.36. Consequently: (a) no winsorization is actually performed inside tvar (g'~0), so wv is the ordinary variance rather than the winsorized variance; (b) k is 0.992 instead of 0.36; (c) tvar returns g~0, so line 74 df = n-2*g-1 becomes n-1 instead of n-2*floor(0.2n)-1. The returned se = sqrt(tv) and df are both wrong, so the trimmed-mean CI (TM(:,:,1) and TM(:,:,3)) is far too narrow and uses the wrong t critical value. The point estimate on line 62 is unaffected because it uses the correctly-scaled g from line 58.
- **Category:** `numerics/stats`

#### 86. `limo_trimmed_mean.m:112` — 🟠 HIGH · CONFIRMED

**The trimming fraction is divided by 100 twice, so the trimmed-mean confidence interval is computed with essentially zero winsorizing, the wrong scale factor k, and the wrong degrees of freedom.**

- **Why:** In the main function, the user-supplied percent (e.g. 20) is converted to a fraction at line 32 (percent = percent/100 -> 0.20) and used correctly to trim at line 58. That same fraction is then passed to the nested tvar (call at line 72), but tvar was written to expect percent in the 0-100 range: line 103 computes g = floor((percent/100)*size(x,2)) and line 112 computes k = (1-2*percent/100)^2. Receiving 0.20 instead of 20, tvar gets g = floor(0.002*n) which is 0 for any realistic n (<500), so loval/hival become the min/max and NO winsorizing occurs (winvar collapses to the ordinary variance), and k = (1-0.004)^2 ~ 0.992 instead of the correct (1-0.4)^2 = 0.36. Worse, tvar's g output overwrites the loop variable g so the CI degrees of freedom at line 74 become df = n-2*0-1 = n-1 instead of n-2*floor(0.2n)-1. Separately, line 113 divides by length(x) (the largest matrix dimension = number of frames) rather than the sample count size(x,2) (subjects), further mis-scaling the standard error. The point estimate (trimmed mean) at lines 62/65 is correct; only the CI (se and df) is corrupted. limo_trimci.m implements the same statistic correctly (percent kept as 0-100, divided once, and uses na), confirming tvar is the outlier.
- **Category:** `numerics-stats`

#### 87. `np_spectral_clustering.m:197` — 🟠 HIGH · CONFIRMED

**The corrected cluster p-value compares the observed cluster mass to the single scalar bootstrap threshold instead of to the whole H0 max distribution, so every significant cluster is assigned the identical minimal p-value 1/Nboot regardless of its actual mass.**

- **Why:** boot_threshold (line 181) is a scalar (the (1-alpha) percentile of boot_values). Inside the branch `if cluster_mass(C) >= boot_threshold`, the statement `sum(cluster_mass(C) >= boot_threshold)` reduces a 1x1 logical, which is always TRUE here, so p = 1/length(boot_values) for every cluster that passes threshold. The correct p-value is the proportion of the null max distribution at least as large as the observed mass, i.e. it must compare cluster_mass(C) against the full vector boot_values, not the scalar boot_threshold. As written, the returned cluster_pvalues carry no information about cluster magnitude. The line `P = min(p,1-p)` (also here) computes a value that is never used. The package's own test (np_spectral_clustering_test.m H1 branch, lines 51-55) feeds two clusters of clearly different mass (+5 over 50 frames vs +2.5 over 100 frames) and gets identical corrected p-values, which the author misattributes to 'the mass is the same' - this is actually this bug.
- **Category:** `resampling/permutation`

## 🟡 Medium (123)

#### 88. `limo_BrownForsythe.m:43` — 🟡 MEDIUM · CONFIRMED

**The channel loop iterates over the count 1..length(array) and uses that counter directly as a channel index instead of indexing into `array`, so when any channel is NaN/missing the wrong channels are tested and valid ones are silently dropped.**

- **Why:** Line 42 builds `array = intersect(find(~isnan(Y1r(:,1,1))), find(~isnan(Y2r(:,1,1))))` = the list of valid (non-NaN) channel indices, clearly intending to loop over those channels. But line 43 loops `for channel = length(array):-1:1` and then indexes the data directly with the loop counter: `Y1r(channel,:,:)` (lines 45,48) and writes `dataout(channel,:,...)` (lines 67-68). This only coincides with the intended channels when the valid set is exactly {1,...,length(array)} (contiguous starting at 1). If any early channel is missing, the counter addresses the wrong rows: NaN channels get processed (yielding NaN F/p) and genuine high-index channels beyond length(array) are never computed, remaining at their preallocated NaN in `dataout`. This mis-maps and drops channels from the variance-homogeneity test.
- **Category:** `indexing-channel-mapping`

#### 89. `limo_LI.m:197` — 🟡 MEDIUM · CONFIRMED

**The null-permutation loop hardcodes 27 channel pairs instead of size(channels,1), crashing for smaller montages and never permuting extra pairs on larger ones.**

- **Why:** Lines 197-199 build a random subset of channel-pair rows using `randperm(27)`, then line 201 indexes `Rchannels(RSelect,:)` and `channels(RSelect,2/1)`. The number 27 is unrelated to the actual number of pairs in `channels`. If the montage has fewer than 27 pairs (the toolbox's own documented example in limo_lateralization uses 13 pairs), `RSelect` can contain indices > size(channels,1), causing an index-out-of-bounds error and aborting the null estimation. If it has more than 27 pairs, rows 28..end are never swapped, biasing the null toward the observed lateralization.
- **Category:** `indexing/hardcoded-dimension`

#### 90. `limo_LI.m:294` — 🟡 MEDIUM · CONFIRMED

**The bias loop reuses the H0_LI array from the permutation null without reinitializing it, so stale permutation values contaminate biasCI when the number of H0 maps differs from 1000 or the split/single shape changes.**

- **Why:** H0_LI is allocated as NaN(1,1000) or NaN(2,1000) and filled by the 1000-iteration permutation loop (lines 193-217), then stored via line 219. The bias section (lines 294-301) writes into the SAME variable H0_LI for m=1:length(H0_maps) without clearing it. length(H0_maps) equals the bootstrap count, which need not be 1000. Columns beyond length(H0_maps) still hold the old permutation-null values, and if the bias branch splits into 2 rows while the permutation branch was single (1 row), MATLAB grows row 2 with zeros. LI_stats.bias = sort(H0_LI,2) at line 303 then includes these stale/zero entries, corrupting biasCI.
- **Category:** `stats/uninitialized-reuse`

#### 91. `limo_STAPLE.m:134` — 🟡 MEDIUM · CONFIRMED

**The thresholded STAPLE map divides the probability threshold by the number of raters, making the cutoff far too permissive.**

- **Why:** W is a per-voxel posterior probability of belonging to the ground truth, naturally thresholded at 0.5. Line 134 instead thresholds at `threshold/N` (default 0.5/N). For N raters this cutoff shrinks with the number of experts, so with, say, N=8 the threshold is 0.0625, and nearly all voxels with any non-trivial weight are retained as ground truth. The label map staple_thmap and the labelled output therefore over-include voxels as consensus-positive. The plain (unnormalized) threshold 0.5 is the standard STAPLE decision rule.
- **Category:** `logic`

#### 92. `limo_batch.m:362` — 🟡 MEDIUM · CONFIRMED

**In the char-session reuse branch, a char session string is compared with `==` against a numeric eval result, so a matching session directory is never recognized (and multi-digit sessions crash arrayfun).**

- **Why:** At line 359 the code enters the `ischar(STUDY.datasetinfo(subject).session)` branch, so `session` is a character string like '2'. Line 362 computes `session == eval(x.name(5:end))`, where `x.name` is e.g. 'ses-2' and `eval('2')` yields the numeric 2. `'2' == 2` compares char code 50 against 2, which is false, so `find(arrayfun(...))` returns [] even when the directory truly matches. Line 363 then does `root = fullfile(reuse([]).folder, reuse([]).name)`, producing an empty/garbled root that is later mkdir'd, corrupting the output path. Worse, for a multi-character session like '10', `'10' == 10` returns a 1x2 logical, and arrayfun (UniformOutput=true) errors because the anonymous function did not return a scalar.
- **Category:** `numerics`

#### 93. `limo_batch.m:409` — 🟡 MEDIUM · CONFIRMED

**For a non-STUDY 'both' run, LIMO_files is only populated for subject 1 because the `~isfield` guard becomes false after the first iteration, so contrasts run for a single subject.**

- **Why:** Lines 409-411 build batch_contrast.LIMO_files inside the per-subject loop only when `strcmp(option,'both') && ~isfield(batch_contrast,'LIMO_files')`. On the first subject the field is created (and the whole cell is transposed), so `isfield(batch_contrast,'LIMO_files')` is true for every subsequent subject and the guard skips them. Consequently batch_contrast.LIMO_files ends up with a single element instead of N. The later loop at line 450 (`for subject = 1:length(batch_contrast.LIMO_files)`) then processes only one subject's contrasts, silently dropping subjects 2..N. This path is reached when 'both' is used, the caller did not supply contrast.LIMO_files, and the run is non-STUDY (STUDY passed as [] to reach the else branch at line 288, where line 393's per-subject assignment does not run).
- **Category:** `control-flow`

#### 94. `limo_batch.m:471` — 🟡 MEDIUM · CONFIRMED

**In the contrast-building loop, subname is read from STUDY.datasetinfo(subject) unconditionally, which crashes in non-STUDY runs and mis-labels contrast output files when the LIMO_files list order/length does not match STUDY.datasetinfo.**

- **Why:** The loop at lines 450-477 runs for both 'contrast only' and 'both' options. Line 471 sets `subname = STUDY.datasetinfo(subject).subject;` with no check that STUDY exists, and indexes it by `subject`, which here iterates 1:length(batch_contrast.LIMO_files). (a) In a non-STUDY run (STUDY cleared/empty), STUDY is undefined and the line throws. (b) In a 'contrast only' run where batch_contrast.LIMO_files was loaded from an arbitrary .txt list (documented at line 73), the subject index into STUDY.datasetinfo has no relationship to that list: it either exceeds numel(datasetinfo) (index-out-of-range crash) or silently pulls the wrong subject's ID, which is then baked into the contrast output filename at line 473 (`..._desc-con_N.mat`), mislabeling results. Note line 667 later recomputes the same name via `limo_get_subname(path)`, confirming the correct source of subname is the file path, not STUDY order.
- **Category:** `control-flow`

#### 95. `limo_batch_design_matrix.m:150` — 🟡 MEDIUM · CONFIRMED

**Component fallbacks request `1:length(EEGLIMO.icawinv)` components (channel count) instead of `size(icawinv,2)` (component count).**

- **Why:** `EEGLIMO.icawinv` is a `[n_channels x n_components]` matrix. Line 51 correctly asks for `1:size(EEGLIMO.icawinv,2)` components. But the Frequency-components fallback (line 150) and the Time-Frequency-components fallback (line 253) use `1:length(EEGLIMO.icawinv)`. `length` returns the largest dimension, which for a typical decomposition with n_channels >= n_components equals n_channels. So the code requests indices up to n_channels from `eeg_getdatact(...,'component',...)`, exceeding the number of available components (n_components).
- **Category:** `indexing-dimension`

#### 96. `limo_batch_design_matrix.m:265` — 🟡 MEDIUM · CONFIRMED · R2-new

**In the Time-Frequency component-clustering branch, `nb_subjects` is set to the count of UNIQUE subjects, but it is used to `repmat` for a cellfun against the per-dataset list, causing a size mismatch (crash) when subjects have more than one dataset.**

- **Why:** Line 265 sets `nb_subjects = length(unique({STUDY.datasetinfo.subject}))`. Line 269 then does `find(cellfun(@strcmp, dsetinfo', repmat({data_dir},nb_subjects,1)))`. `dsetinfo` is built from `{STUDY.datasetinfo.filepath}` so its length equals the number of datasetinfo entries (D). cellfun requires both cell arrays to be the same size, so `repmat({data_dir},nb_subjects,1)` must produce D elements. The Frequency sibling branch (line 162) deliberately uses `length({STUDY.datasetinfo.subject})` (= D, non-unique) — with the `unique` form explicitly commented out — precisely so the sizes match. The TF branch uses the `unique` form, so whenever the number of unique subjects is less than the number of datasets, `nb_subjects != D` and cellfun throws 'All of the input arguments must be of the same size and shape'.
- **Category:** `dimension-mismatch`

#### 97. `limo_batch_design_matrix.m:289` — 🟡 MEDIUM · CONFIRMED

**Unconditional `limo_struct2mat` call on `dattimef` runs before the type checks and crashes when `dattimef` is a cell array of files.**

- **Why:** Line 289 `signal = abs(limo_struct2mat(EEGLIMO.etc.datafiles.dattimef)).^2;` executes unconditionally, before the `~iscell(...)` test on line 290 and the multi-file (cell) handling in the catch on lines 304-308. The very existence of the `~iscell` guard on line 290 shows `dattimef` can be a cell. When it is a cell, `limo_struct2mat` reaches `F = fieldnames(in)` with `in` a cell (it only special-cases `ischar`), which errors. So multi-file channel Time-Frequency imports crash on line 289 before the intended cell-handling path is ever reached. Even in the single-file case, line 289's result is always overwritten (line 291/298/302/306), making the whole line redundant work whose only observable effect is the crash risk.
- **Category:** `data-handling`

#### 98. `limo_boot_threshold.m:19` — 🟡 MEDIUM · CONFIRMED

**Operator precedence makes the F-vs-T branch test always true, so T-statistics are always thresholded one-tailed (positive tail only) with one-tailed p-values instead of two-tailed.**

- **Why:** The expression parses as (all(sorted_values(:))) >= 0. all(...) returns a scalar logical 0 or 1, and both 0>=0 and 1>=0 are true, so the condition is unconditionally true and the else (T-value) branch is dead. The intended test was all(sorted_values(:)>=0), which distinguishes non-negative F distributions from signed T distributions. Consequently, when called with T values (which the else branch and comments explicitly support), the code (a) builds mask only from values >= sorted_values(:,:,U), ignoring the negative tail entirely, and (b) computes one-sided pvalues = 1 - tmp/nboot rather than the two-sided min(tmp/nboot, 1-tmp/nboot). Both the significance mask and the p-values are wrong for any signed statistic.
- **Category:** `logic/operator-precedence`

#### 99. `limo_bootttest1.m:121` — 🟡 MEDIUM · CONFIRMED

**In the 3D case, squeeze collapses a singleton channel or frame dimension, so the subsequent mean/std over dim 3 operate on the wrong axis and the assignment into m/sd/t dimension-mismatches or mis-computes.**

- **Why:** case(3) assumes data(:,:,boot(:,B)) is [channels x frames x n] and reduces over nd=3. If size(data,1)==1 (single channel) or size(data,2)==1 (single frame), squeeze removes that singleton, yielding a 2D array [frames x n] (or [channels x n]). Then mean(boot_data,3) and std(boot_data,0,3) reduce over a nonexistent singleton dim (no-op), returning a [frames x n] result rather than a [1 x frames] slice. Assigning m(:,:,B) = that result (m preallocated as [1 x frames x Nboot]) errors on size mismatch, and even where it does not error the statistic is taken across the wrong dimension.
- **Category:** `indexing/dimension`

#### 100. `limo_central_estimator.m:34` — 🟡 MEDIUM · CONFIRMED · R2-new

**`legacy_mode` is silently forced true for 2- and 3-argument calls, contradicting the documented default (false) and the 1-argument default (false).**

- **Why:** The header documents legacy_mode default = 'false'. The nargin dispatch sets legacy_mode=false only for nargin==1; nargin==2 (line 36) and nargin==3 (line 34) both hardcode legacy_mode=true. Since legacy vs non-legacy changes BOTH the Bayesian-bootstrap sampling distribution (exprnd at line 63 vs gamrnd at line 65) and the interval method (narrowest-interval HDI at lines 83-106 vs quantile indexing at lines 108-110), the statistical procedure silently flips depending purely on how many arguments the caller supplies. A user passing prob_coverage explicitly (3 args) gets a different method than one relying on the default (1 arg), with no way to know.
- **Category:** `wrong-default`

#### 101. `limo_central_tendency_and_ci.m:372` — 🟡 MEDIUM · CONFIRMED · R2-new

**The within-subject 'Weighted Mean' computes mean(w.*x) over trials (divides by N), not the weighted mean sum(w.*x)/sum(w), biasing the estimate whenever trial weights do not sum to the number of trials.**

- **Why:** For Weighted Mean, tmp is filled with weighted data w_i*x_i at lines 357 (and 352-354 for TF, 736/800 in the ERP branch), then line 372/373 collapses trials with `mean(tmp,3)` = sum_i(w_i x_i)/N. A proper weighted mean is sum_i(w_i x_i)/sum_i(w_i). LIMO WLS trial weights lie in [0,1] and do not generally sum to N, so dividing by N systematically attenuates the estimate rather than producing the intended weighted average.
- **Category:** `statistical-correctness`

#### 102. `limo_central_tendency_and_ci.m:538` — 🟡 MEDIUM · CONFIRMED · R2-new

**Loading a channel-vector .mat file uses `channel_vector.cell2mat(fieldname(channel_vector))`, which references the non-existent function `fieldname` and a bogus dynamic-field syntax, crashing the channel-optimized Betas/Con path.**

- **Why:** Line 538: `channel_vector = channel_vector.cell2mat(fieldname(channel_vector));`. `fieldname` is not a MATLAB function (the builtin is `fieldnames`), and `channel_vector.cell2mat(...)` is parsed as accessing a struct field/method named cell2mat rather than calling cell2mat on the fieldnames. The correct idiom, used elsewhere in this very file (lines 110, 321, 564), is `channel_vector.(cell2mat(fieldnames(channel_vector)))`.
- **Category:** `undefined-function`

#### 103. `limo_central_tendency_and_ci.m:666` — 🟡 MEDIUM · CONFIRMED · R2-new

**In the ERP 1-channel path, `channel_vector.getfield(channel_vector)` passes the struct itself as the field-name argument to getfield, which crashes.**

- **Why:** Line 666: `channel_vector = channel_vector.getfield(channel_vector);`. getfield(S, FIELD) requires FIELD to be a char field name; here the struct is passed as the field name, so MATLAB errors ('Argument must be...' / invalid field). This is the ERP-branch analogue of the line 538 bug; the correct idiom is `channel_vector.(cell2mat(fieldnames(channel_vector)))`.
- **Category:** `wrong-argument`

#### 104. `limo_central_tendency_and_ci.m:789` — 🟡 MEDIUM · CONFIRMED

**size() is called without a dimension argument inside a scalar `||` guard, producing a 1x2 vector that throws a non-scalar error whenever the first condition is false.**

- **Why:** In the 'Pool Conditions' path the guard is `if max(parameters) <= sum(...)+sum(...) || max(parameters) == size(LIMO.design.X)`. `size(LIMO.design.X)` (no dim arg) returns the 1x2 vector [nrows ncols]. When the first `<=` clause evaluates false, MATLAB evaluates the second operand of `||`, which becomes `scalar == [nrows ncols]` = a 1x2 logical. The `||` operator requires a logical scalar and throws 'Operands to the || and && operators must be convertible to logical scalar values.' Every other analogous guard in the file correctly uses `size(LIMO.design.X,2)` (e.g. lines 333, 725), confirming the intent was the number of columns (regressors).
- **Category:** `indexing/control-flow`

#### 105. `limo_central_tendency_and_ci.m:1069` — 🟡 MEDIUM · CONFIRMED

**The Time-Frequency Harrell-Davis branch is missing the `index = 1; h = waitbar(...)` initialization that every sibling estimator block has, so it references an uninitialized/stale waitbar handle and counter and errors when computing HD (or 'All') on TF data.**

- **Why:** For the Mean (line 942), Trimmed mean (1003) and Median (1126) blocks, `index = 1; h = waitbar(0,...)` is executed BEFORE the `if strcmpi(limo.Analysis,'Time-Frequency')` split. In the HD block that initialization was placed only inside the non-TF `else` (line 1091), so the Time-Frequency branch (lines 1065-1088) never resets `index` nor creates `h`. Its loop calls `waitbar(index/...)` (1069) with no valid waitbar figure (the previous block's `h` was already `close`d at line 1043/982, or `h`/`index` are entirely undefined when Estimator2=='HD' with no preceding block) and then `close(h)` at 1105 on an invalid/undefined handle. This throws an error during a legitimate analysis path.
- **Category:** `control-flow/uninitialized-variable`

#### 106. `limo_chancluster_test.m:1` — 🟡 MEDIUM · CONFIRMED

**The file's first line is a call to itself rather than a function declaration, so MATLAB parses it as a script that errors immediately on undefined inputs.**

- **Why:** Line 1 reads '[mask, cluster_p] = limo_chancluster_test(ori_f,ori_p,boot_f,boot_p,alphav);' with no leading 'function'. MATLAB therefore treats the whole file as a script, not a function. Running it executes line 1 which references undefined variables ori_f/ori_p/boot_f/boot_p/alphav (Undefined function or variable error), and nargin/error later are invalid in script context. The documented FORMAT '[mask,pval] = limo_chancluster_test(...)' cannot be invoked at all.
- **Category:** `control-flow/crash`

#### 107. `limo_chancluster_test.m:34` — 🟡 MEDIUM · CONFIRMED

**The dimensionality guard uses || where && is required, so it is always true and always throws 'data must be 1D or 2D'.**

- **Why:** ndim = numel(size(ori_f)) is always >= 2 in MATLAB (size returns at least 2 elements), and for any value of ndim the expression 'ndim ~= 1 || ndim ~= 2' is a tautology (a number cannot be simultaneously equal to both 1 and 2), so the condition is always true and the error always fires. The operator should be && (and, given numel(size()) is never 1, the real intent is to accept ndim==2).
- **Category:** `logic/crash`

#### 108. `limo_cluster_attributes.m:55` — 🟡 MEDIUM · CONFIRMED

**The percentile index U is computed from nboot but H0_extend/H0_height are only appended for bootstraps that contained at least one cluster, so U can exceed the array length (index-out-of-bounds crash) and, even when it doesn't, the threshold percentile is biased because zero-cluster bootstraps are dropped instead of counted as mass 0.**

- **Why:** In the H0 loop (lines 37-49) `index` is only incremented when num~=0, so length(H0_extend) equals the number of bootstraps that yielded any cluster, which is <= nboot. Line 53 sets U = round((1-p_value)*nboot) (e.g. 950 for nboot=1000, p_value=0.05). Line 55 then does H0_extend(U). If fewer than U bootstraps produced a cluster the reference exceeds the array bounds and MATLAB throws 'Index exceeds the number of array elements'. Statistically the correct null distribution of the maximum should include a 0 for every bootstrap with no supra-threshold cluster (as limo_cluster_test / limo_getclustersum do); dropping them shrinks the distribution and shifts the (1-alpha) threshold, making the extend/height masks anti-conservative.
- **Category:** `indexing/dimension`

#### 109. `limo_clusterica.m:138` — 🟡 MEDIUM · CONFIRMED

**The dipole-orientation angle matrix is normalized by max(S), which is the per-column maximum (a row vector) rather than the global maximum, so via implicit expansion each column is scaled by a different factor and the resulting matrix is no longer symmetric, corrupting the similarity used for clustering.**

- **Why:** S is an [nIC x nIC] symmetric matrix of pairwise orientation angles (degrees). max(S) returns a 1 x nIC row vector of column maxima; S./max(S) broadcasts that row across all rows, dividing column j by its own column max. This is not the intended 'normalize to 1' (a global scaling) - it produces a generally non-symmetric matrix with different scaling per column. Contrast line 128 (M = D./max(D(:))) and line 140 (M = D./max(D(:))), which correctly use the global max. The corrupted S is then averaged with the euclidean-distance matrix D at line 139 (D = (D+S)./2), so the combined dipole similarity matrix M fed to apcluster (line 183) is mis-scaled and asymmetric, degrading/altering the cluster assignment.
- **Category:** `indexing/dimension`

#### 110. `limo_combine_catvalues.m:63` — 🟡 MEDIUM · CONFIRMED

**`limo_combine_catvalues` calls `limo_quick_design`, which does not exist anywhere in the toolbox, so the function errors out for every input.**

- **Why:** Line 63 does `[x,nb_conditions]= limo_quick_design(cat_values(:,combine));`. A repo-wide search finds no definition of `limo_quick_design` (only this call site references the name). Unless the user happens to have an unrelated file of that name on their MATLAB path, execution aborts with an 'Undefined function' error before any combination is performed. The entire routine is therefore non-functional as shipped.
- **Category:** `data handling`

#### 111. `limo_combine_components.m:59` — 🟡 MEDIUM · CONFIRMED

**The 'maxvar' branch selects the component via `max` of the residual variance, which corresponds to the component accounting for the LEAST variance, contradicting the stated goal of picking max variance accounted for.**

- **Why:** `dataMinusIca = mean(data,3) - invweights(:,comp)*icaact(comp,:)` removes a component's back-projected contribution, and `varica(iComp) = mean(var(dataMinusIca,[],2))` is the residual variance after removal. A component that accounts for a lot of variance leaves a SMALL residual, so residual variance is inversely related to variance-accounted-for. The comment (line 52) says the goal is 'the ica which has the max mean variance accounted for', which requires `min(varica)`, but the code uses `max(varica)`, thereby selecting the component that explains the least variance.
- **Category:** `numerics/stats`

#### 112. `limo_compute_H0.m:38` — 🟡 MEDIUM · CONFIRMED

**type is captured with cell indexing (varargin(1)) so 'type == 0' compares a cell to a double and errors, and the argument dispatch references a misspelled 'varagin', making the function non-functional.**

- **Why:** Line 35 does type = varargin(1), which yields a 1x1 cell (not its contents). Line 38 then evaluates if type == 0, i.e. {0} == 0, which raises 'Undefined operator == for input arguments of type cell'. Even if that were fixed, the input-parsing block (lines 42-54) repeatedly calls varagin(2), varagin(3), varagin(4) — a misspelling of varargin — so those lines throw 'Undefined function or variable varagin'. Additional undefined symbols follow (parameter at lines 65/89/136, LIMO at line 109, cleaer at line 153). The function cannot execute for any input.
- **Category:** `data handling/crash`

#### 113. `limo_compute_H0.m:45` — 🟡 MEDIUM · CONFIRMED · R2-new

**Misspelled 'varagin' (missing r) on all argument-capture lines throws 'Undefined function or variable varagin'**

- **Why:** Lines 41, 42, 43, 45, 49, 52, and 53 read arguments via `varagin(...)` instead of `varargin(...)`. `varagin` is never defined, so the very first argument-capture line that executes raises 'Undefined function or variable "varagin"'. This is separate from the already-reported bug about `type` being captured as a cell via `varargin(1)`: here the identifier itself is misspelled, so no data/nboot/data1/data2 is ever assigned and the function cannot run at all. [Note: no static callers of limo_compute_H0 were found in the repo, so this is a latent/legacy defect rather than an active crash path.]
- **Category:** `undefined-variable`

#### 114. `limo_compute_H0.m:153` — 🟡 MEDIUM · CONFIRMED · R2-new

**'cleaer boot_table' typo runs before varargout{1} is set, crashing even the implemented type-0 limo_trimci path**

- **Why:** Line 153 is `clear data; varargout{2} = boot_table; cleaer boot_table`. `cleaer` is not a MATLAB command/function, so command-syntax `cleaer boot_table` errors with 'Unrecognized function or variable cleaer'. Because this executes before line 154 (`varargout{1} = H0`), even the one fully-implemented branch (type 0 with test='limo_trimci') fails at the very end and never returns H0. [Note: no static callers of limo_compute_H0 were found in the repo, so this is a latent/legacy defect rather than an active crash path.]
- **Category:** `typo-crash`

#### 115. `limo_contrast.m:417` — 🟡 MEDIUM · CONFIRMED

**IRLS F-contrast uses dfe(channel) (frame-1 only) instead of the per-frame Satterthwaite dfe, giving the wrong error df and p-values for all frames but the first.**

- **Why:** For IRLS, dfe is a [channels x frames] matrix (Satterthwaite df per frame), as shown by the IRLS T-branch which correctly uses `dfe(channel,:)` at line 369 and `dfe(channel,frame)` at lines 374/376. In the IRLS F-branch, lines 416-418 use `dfe(channel)`, which for a 2-D matrix is linear index (channel,1) — the first frame's df only. The F ratio denominator and the fcdf df are therefore taken from frame 1 for every frame.
- **Category:** `numerics/stats`

#### 116. `limo_contrast.m:571` — 🟡 MEDIUM · CONFIRMED

**The bootstrapped H0 T p-value is computed one-tailed (no abs, no *2) whereas the observed con T p-value is two-tailed, an inconsistency between the null and observed p distributions.**

- **Why:** Observed T p-values (lines 298, 365, 376) are two-sided: `(1-tcdf(abs(t),df)).*2`. The bootstrap H0 T p-value at line 571 is one-sided `1-tcdf(t,df)` with no absolute value and no factor of 2. If any downstream correction compares observed two-tailed p to the H0 p distribution, the tails are mismatched (and negative t give p near 1 rather than small).
- **Category:** `numerics/stats`

#### 117. `limo_contrast.m:630` — 🟡 MEDIUM · CONFIRMED

**IRLS bootstrap T-contrast standard error uses the unweighted design (pinv(X'*X)) whereas the observed statistic uses the weighted design (pinv(WX'*WX)), so the null T distribution is not on the same scale as the observed T.**

- **Why:** The non-bootstrap IRLS T (line 373) scales the SE with `pinv(WX'*WX)` using the weighted design WX (line 372). The bootstrap counterpart (line 630) uses `pinv(X'*X)` on the unweighted X even though WX is available (line 621). Because IRLS weights differ from 1, the H0 T statistic uses a different SE normalization than the observed T, invalidating max-stat/cluster comparisons that assume the two are computed identically.
- **Category:** `numerics/stats`

#### 118. `limo_contrast.m:717` — 🟡 MEDIUM · CONFIRMED · R2-new

**The multivariate bootstrap (case 2, Multivariate) transposes and matrix-multiplies the full N-D Betas array (`Betas'*X'*M*X*Betas`) instead of a per-time 2-D slice, which errors on N-D transpose; the surrounding block also linear-indexes Y/centered_data with boot_table(:,B).**

- **Why:** In case(2) the Multivariate branch (lines 675-730) never slices Betas by time or bootstrap. Betas here is the loaded (H0) parameter array, at least 3-D (channels x time x beta, and 4-D channels x time x beta x nboot for H0). Line 717 computes H = (Betas'*X'*M*X*Betas). MATLAB's ' (ctranspose) is undefined for N-D arrays, so this throws 'Transpose on ND array is not defined.' Additionally line 686/687/690 do Y = centered_data(boot_table(:,B)) and X = design(boot_table(:,B)), which linear-index the multidimensional arrays into vectors rather than resampling rows, so even if the transpose were fixed the statistics would be meaningless. The multivariate contrast bootstrap is non-functional.
- **Category:** `dimension-error`

#### 119. `limo_contrast.m:769` — 🟡 MEDIUM · CONFIRMED

**The robust single-group repeated-measures branch crashes on horzcat of a scalar with a 3-D array, and even if it ran the se on line 771 is always 0.**

- **Why:** In the gp_values==1, non-'Mean' branch Y is 3-D [nframes x nsubj x nmeasures] (squeeze of Yr(channel,:,:,:)). [1 Y] is horzcat(1,Y), which errors ('Dimensions of arrays being concatenated are not consistent') for a 3-D Y, and the result shape would not fit ess(channel,:,1) anyway. If that were fixed, line 771 computes se as sqrt(C*cov(squeeze(ess(channel,time,1)))*C'), but ess(channel,time,1) is a scalar so cov(scalar)=0 and the se is identically 0; the 'Mean' branch on line 766 correctly uses cov(squeeze(Y(time,:,:))).
- **Category:** `indexing/dimension`

#### 120. `limo_contrast.m:940` — 🟡 MEDIUM · CONFIRMED · R2-new

**Case 4 single-group branch saves H0_ess with `save([subname filename], ...)` where filename is already an absolute path (built at line 881), corrupting the save path when subname is non-empty; the else branch correctly uses `save(filename, ...)`.**

- **Why:** Line 881 sets filename = fullfile(LIMO.dir,['H0' filesep 'ess_' num2str(index) '_desc-H0.mat']) — a full absolute path. In the gp_values==1 branch, line 940 does `save([subname filename], 'H0_ess', '-v7.3')`, prepending the subname string (e.g. 'sub-01_desc-') in front of the absolute path. The group branch at line 1001 correctly does `save(filename, ...)` without subname. With a non-empty subname the concatenation yields a relative path like 'sub-01_desc-/Users/.../ess_1_desc-H0.mat' interpreted relative to cwd (LIMO.dir/H0), whose parent directory does not exist, so save errors out or writes to the wrong location. Even with empty subname the two branches are inconsistent.
- **Category:** `save-load-mismatch`

#### 121. `limo_contrast_checking.m:117` — 🟡 MEDIUM · CONFIRMED · R2-new

**Contrast estimability/invariance test is vacuous: it projects a vector already guaranteed to lie in col(X), so the invalid-contrast branch (go=0) is unreachable.**

- **Why:** In the 2-argument validity path the code computes lambda = X*C' (line 118), then check = int16(X*pinv(X) * lambda) and compares it to int16(lambda) (lines 117-120). But lambda = X*C' is by construction a linear combination of the columns of X, i.e. it already lies in the column space of X. The projector P = X*pinv(X) maps any vector already in col(X) to itself, so P*lambda == lambda holds identically (up to floating-point noise far below the int16 rounding grid). Consequently sum(check) always equals size(X,1), the `go = 0` branch on line 122 is never taken, and every contrast is reported valid. A correct estimability test must check that the contrast lies in the ROW space of X, e.g. C*(pinv(X)*X) approx == C. LIMO routinely uses rank-deficient design matrices (full dummy coding plus an intercept), so non-estimable contrasts genuinely exist and are silently accepted.
- **Category:** `statistical-correctness`

#### 122. `limo_contrast_execute.m:118` — 🟡 MEDIUM · CONFIRMED

**The Multivariate branch references undefined variables (Yr, time, Betas) and overwrites LIMO.contrast with a scalar, so it crashes if ever reached.**

- **Why:** In the `strcmp(LIMO.design.type_of_analysis,'Multivariate')` branch, line 117 does `LIMO.contrast = handles.F;` which clobbers the entire contrast cell array with a scalar flag, and line 118 calls `limo_contrast(squeeze(Yr(:,time,:))', squeeze(Betas(:,time,:))', [], LIMO, handles.F,1);`. None of Yr, time, or Betas are ever loaded or defined in this function (Yr/Betas are only cleared at line 124, never assigned). Reaching this branch throws 'Undefined function or variable Yr'. Additionally the argument list (squeezed Y, squeezed Betas, [], LIMO, handles.F, 1) does not match the limo_contrast signature used elsewhere.
- **Category:** `control flow`

#### 123. `limo_contrast_sessions.m:149` — 🟡 MEDIUM · CONFIRMED

**The stored standard error uses group-1 variance for BOTH variance terms (sd(1,:) twice) instead of group-2 variance for the second term.**

- **Why:** limo_ttest (case 2) returns sd = sqrt([s1.*n1 ; s2.*n2]) = [std_group1 ; std_group2], a 2xF matrix (row 1 = group1 SD, row 2 = group2 SD). The code does `sd = sd.^2` (now [var1; var2]) then `a = sd(1,:)./size(Y1,2); b = sd(1,:)./size(Y2,2);` and `con(:,:,2)=sqrt(a+b)`. Term b uses sd(1,:) (group-1 variance) divided by n2, when it must use sd(2,:) (group-2 variance). The correct Welch SE is sqrt(var1/n1 + var2/n2); this computes sqrt(var1/n1 + var1/n2). The t-value itself is taken directly from limo_ttest so it is correct, but the SE that is saved into the con file (dim index 2) is wrong whenever the two sessions have unequal variance.
- **Category:** `numerics/stats`

#### 124. `limo_create_boot_table.m:49` — 🟡 MEDIUM · CONFIRMED · R2-new

**Subject-count guard requires >=5 subjects but the error message says 'need at least 3', rejecting valid 4-subject datasets**

- **Why:** Line 49 `if size(data,3)-1 <= Nmin` with Nmin=3 aborts whenever subjects-1 <= 3, i.e. for 4 or fewer subjects, so it actually requires at least 5 subjects. The thrown message on line 50 says 'need at least 3 subjects', which is inconsistent with the actual threshold. A legitimate 4-subject second-level analysis is refused with a misleading message. (Line 42's low-count warning likewise hardcodes 3 instead of Nmin.)
- **Category:** `off-by-one`

#### 125. `limo_create_files.m:36` — 🟡 MEDIUM · CONFIRMED

**The type-validation condition `~strcmp(type,'raw') || ~strcmp(type,'modeled')` is a tautology that is true for every input, so the function always errors when called programmatically.**

- **Why:** By De Morgan's law, no single string can be both 'raw' and 'modeled', so `~strcmp(type,'raw') || ~strcmp(type,'modeled')` evaluates to true for ANY value of `type`. When type='raw', the first term is false but the second is true; when type='modeled', the first is true. Either way the branch throws `error('type of output not recognized')`. The operator must be `&&` (error only if it is neither raw nor modeled). As written, the entire non-GUI (three-argument) code path is dead — the function cannot be driven from a script or from limo_batch.
- **Category:** `control-flow`

#### 126. `limo_create_single_trials_gui.m:89` — 🟡 MEDIUM · CONFIRMED

**Unchecking any ICA checkbox writes 'off' to the corresponding scalp field instead of the ICA field, so the ICA field stays 'on' and cannot be cleared.**

- **Why:** In ica_erp_Callback (line 89), ica_spec_Callback (line 95), ica_ersp_Callback (line 101), and ica_itc_Callback (line 107), the else branch (checkbox unchecked, h==0) sets handles.scalp_erp/scalp_spec/scalp_ersp/scalp_itc to 'off' respectively, rather than handles.ica_erp/ica_spec/ica_ersp/ica_itc. This is a copy-paste error. Consequently, once an ICA checkbox has been checked (setting e.g. handles.ica_erp='on'), unchecking it never resets the ICA field back to 'off'; instead it corrupts the corresponding scalp field. The stale ICA 'on' value then drives limo_create_single_trials into producing ICA data the user just deselected, and simultaneously silently disables the matching scalp measure.
- **Category:** `control-flow-logic`

#### 127. `limo_display_results.m:409` — 🟡 MEDIUM · CONFIRMED

**The non-R2 MANOVA eigenvalue plotting branch indexes with an undefined variable Condition_effect_EV, causing an immediate crash.**

- **Why:** In the multivariate (Condition/Covariate) eigenvalue branch, the eigenvalues are loaded into the variable EV (lines 406-408), but line 409 trims them with `EV = EV(1:size(Condition_effect_EV,1),:)`. Condition_effect_EV is never assigned anywhere in the function (grep confirms line 409 is its only occurrence), so MATLAB throws 'Undefined function or variable Condition_effect_EV'. The parallel R2 branch (line 371) correctly uses the loaded variable's own size.
- **Category:** `data-handling`

#### 128. `limo_display_results.m:1414` — 🟡 MEDIUM · CONFIRMED

**The ess course-plot Bonferroni correction is mis-parenthesized: it multiplies alpha by the number of contrast rows instead of dividing, giving too-narrow or invalid (negative-probability -> NaN) confidence intervals.**

- **Why:** For ess files the CI is `trimci(:,2) +/- finv(1-p./2*size(C,1),df,data(:,3)).*data(:,2)`. Because `*` and `./` share precedence and evaluate left to right, `p./2*size(C,1)` equals `(p/2)*size(C,1)`, so the probability is `1-(p/2)*size(C,1)`. The intended Bonferroni bound is `1 - p/(2*size(C,1))` (as done correctly for repeated measures at line 1961 with `p./(2*size(C,1))`). With multi-row contrasts this inflates alpha; e.g. size(C,1)=40, p=0.05 gives probability 0, finv=0 -> zero-width CI, and size(C,1)>40 gives a negative probability so finv returns NaN and the CI/plot breaks.
- **Category:** `numerics-stats`

#### 129. `limo_display_results.m:1803` — 🟡 MEDIUM · CONFIRMED

**Frequency-domain categorical course plot at level 2 passes an RGB triple as the plot LineSpec (missing 'Color') and the following patch uses an undefined timevect, so the plot crashes.**

- **Why:** In the level-2 regression/ANOVA categorical branch, the 'Time' path (line 1798) correctly calls `plot(timevect,...,'Color',brewcolours(i,:),...)`, but the 'Frequency' path at line 1803 was copied without the 'Color' keyword: `plot(freqvect,squeeze(average(i,:)),brewcolours(i,:),'LineWidth',1.5)`. plot's third positional argument must be a LineSpec string; a 1x3 numeric RGB there raises an error. Additionally, line 1810 unconditionally builds the CI patch with `timevect`, which is only assigned inside the 'Time' sub-branch (line 1797) and is undefined when LIMO.Analysis is 'Frequency'.
- **Category:** `indexing-dimension`

#### 130. `limo_display_results.m:1961` — 🟡 MEDIUM · CONFIRMED

**Repeated-measures ANOVA main-effect confidence band is computed from the covariance of a single frame (frame 1) and replicated to all frames, producing incorrect error bars.**

- **Why:** S is filled per time/frequency frame inside the loops at lines 1926-1929 (Mean) and 1937-1948 (Trimmed), each running `for time_or_freq = size(Data,1):-1:1`, so after the loop time_or_freq==1. The CI at lines 1961-1963 is executed once, outside any loop, using `S(time_or_freq,:,:)` i.e. S(1,:,:), then `repmat(bound',[length(avg),1])` copies this single-frame bound to every frame. The commented-out original (lines 1959-1960) also indexes S(time_or_freq,...), indicating a per-frame loop was intended. Consequently every frame's confidence interval reflects only the first frame's covariance rather than its own.
- **Category:** `numerics-stats`

#### 131. `limo_ecluster_make.m:89` — 🟡 MEDIUM · CONFIRMED

**The 2D (single-channel) branch returns the H0 cluster-mass distribution as a [nboot x 1] column while the 3D branch returns [Nchan x nboot], so limo_ecluster_test collapses the whole null distribution to a single scalar and reports corrected cluster p-values of ~1 for genuinely significant clusters.**

- **Why:** For 3D input (line 51) boot_values is [Ne x b] (channels-in-dim1, bootstraps-in-dim2). For 2D input (line 89) it is instead [b x 1] (bootstraps in dim1). limo_ecluster_test consumes this as boot_maxclustersum and at lines 90-92 does `if size(boot_maxclustersum,1) > 1; boot_maxclustersum = max(boot_maxclustersum,[],1); end` — logic meant to take the max across channels. With the 2D column [b x 1], size(,1)=nboot>1, so it takes max over the bootstrap dimension, collapsing the entire null distribution to one number (the global maximum cluster mass). Then at line 108 `p = 1 - sum(maxval(C) >= boot_maxclustersum)./length(boot_maxclustersum)` divides by length 1, and since any observed significant cluster mass that merely exceeds the 95th-percentile th.elec is almost always smaller than the global bootstrap maximum, sum(...) = 0 and p = 1. The significance mask itself is still correct (it is thresholded against th.elec, line 105), but the returned corrected p-value map is wrong.
- **Category:** `resampling/dimension`

#### 132. `limo_ecluster_test.m:91` — 🟡 MEDIUM · CONFIRMED

**In the single-channel temporal-clustering path the H0 null distribution is collapsed to a single scalar, corrupting every reported cluster p-value.**

- **Why:** limo_ecluster_test assumes boot_maxclustersum is oriented [channels x nboot] so that max(.,[],1) collapses the channel axis to [1 x nboot]. But for single-channel data limo_clustering (line 101) calls limo_ecluster_make on squeeze(bootM) which is 2D [frames x nboot]; the 2D branch of limo_ecluster_make (line 89) returns boot_values as a COLUMN vector [nboot x 1]. In limo_ecluster_test, size(boot_maxclustersum,1)=nboot>1 is therefore true, and max(.,[],1) reduces the whole bootstrap distribution to one scalar (the global maximum cluster sum). The per-cluster p-value at line 108, p = 1 - sum(maxval(C) >= boot_maxclustersum)./length(boot_maxclustersum), then compares each observed cluster mass against this single maximum with length 1, so for essentially every cluster sum(...)=0 and p=1 (and even when it equals the max, p=0 is reset to 1/1=1). Thus cluster_pval returned to limo_stat_values is ~1 everywhere, contradicting the mask (which is still correct because it uses th.elec).
- **Category:** `dimension/statistics`

#### 133. `limo_eeg.m:111` — 🟡 MEDIUM · CONFIRMED · R2-new

**In case 3, a missing local LIMO.mat does not trigger the catch fallback, so LIMO is never defined and cd(LIMO.dir) crashes instead of prompting the user.**

- **Why:** The try block (lines 97-110) only loads LIMO when `exist(fullfile(pwd,'LIMO.mat'),'file')` is true. If no LIMO.mat exists in pwd, the if-body is skipped, the try completes with no error, and the catch (which runs the uigetfile prompt) is never entered. Execution falls through to line 111 `cd(LIMO.dir)` with LIMO undefined. The intended file-picker fallback only fires on a load error, not on a missing file, so the graceful path is dead.
- **Category:** `control-flow`

#### 134. `limo_eeg.m:502` — 🟡 MEDIUM · CONFIRMED

**Multivariate interaction effects are populated from model.conditions instead of model.interactions, storing the wrong statistics.**

- **Why:** In the multiple-interactions branch (lines 501-507) every field is read from model.conditions (model.conditions.EV, model.conditions.Roy.F/p, model.conditions.Pillai.F/p) rather than from model.interactions. The single-interaction branch two lines above (line 499) correctly uses model.interactions. This is a copy-paste from the conditions block (lines 487-492) and causes condition statistics to be saved as interaction statistics.
- **Category:** `stats-correctness`

#### 135. `limo_eeg.m:577` — 🟡 MEDIUM · CONFIRMED

**save is passed a nonexistent variable name 'Interaction_effectV' (typo), which errors and drops the interaction result.**

- **Why:** The variable built on line 576 is Interaction_effect, and name is 'Interaction_effect_%g'. The save call on line 577 references the string 'Interaction_effectV', which is not a workspace variable, so MATLAB throws 'Variable ''Interaction_effectV'' not found.' The parallel condition/covariate branches (lines 556/597) correctly pass the matching variable name.
- **Category:** `data-handling`

#### 136. `limo_eeg.m:792` — 🟡 MEDIUM · CONFIRMED

**Case 6 references an undefined variable FileName when deciding .txt vs .mat for the contrast file, causing a crash.**

- **Why:** The selected file is stored in contrast_file (line 790). Lines 792 and 794 test FileName(end-3:end), but FileName is never defined in this scope, so the code errors with 'Undefined function or variable FileName' (unless a stray FileName happens to exist in the loaded workspace). The intended variable is contrast_file.
- **Category:** `control-flow`

#### 137. `limo_eeg.m:832` — 🟡 MEDIUM · CONFIRMED · R2-new

**Multivariate contrast results are gated on strfind for lowercase 'multivariate', but type_of_analysis is 'Multivariate', so the block never runs and multivariate contrast results are never stored.**

- **Why:** `if strfind(LIMO.design.type_of_analysis,'multivariate')` is case-sensitive. The only values assigned to type_of_analysis are 'Mass-univariate' and 'Multivariate' (lines 419/427). Neither contains the lowercase substring 'multivariate' ('Mass-univariate' contains 'univariate'; 'Multivariate' differs by capital M). strfind therefore returns [] for both, and `if []` is false, so `LIMO.contrast{...}.multivariate = result` is never executed. Multivariate contrasts computed by limo_contrast are silently discarded.
- **Category:** `string-comparison`

#### 138. `limo_eeg_tf.m:287` — 🟡 MEDIUM · CONFIRMED

**exist is passed the numeric value of nboot instead of the string 'nboot', so the nboot-defaulting guard is broken.**

- **Why:** The intent is `if LIMO.design.bootstrap > 599 || ~exist('nboot','var')` to set nboot from the design. As written, `exist(nboot,'var')` passes the number 1000 (nboot's value, set at line 33) as the first argument; exist requires a char/string name. Depending on MATLAB version this either errors ('Argument must be a text scalar') or returns 0. Because of ||-short-circuit the second operand is only evaluated when LIMO.design.bootstrap <= 599.
- **Category:** `control-flow`

#### 139. `limo_eeg_tf.m:449` — 🟡 MEDIUM · CONFIRMED

**The observed (non-null) R2 TFCE score is saved into the H0 (null) directory instead of the TFCE directory where all other observed TFCE scores are written.**

- **Why:** For conditions, interactions and covariates the observed TFCE score is written after `cd('TFCE')` (lines 483, 525, 567) and the bootstrap null is written into H0 (e.g. line 471 tfce_H0_R2). For R2, the observed tfce_score is instead saved to `['H0' filesep 'tfce_R2']` at line 449, i.e. inside the null directory, while the R2 null is saved as tfce_H0_R2 (line 471). This misplaces the observed statistic relative to every other effect and relative to where downstream thresholding looks for observed TFCE scores (limo_stat_values reads observed scores from the 'tfce' directory).
- **Category:** `data-handling`

#### 140. `limo_eeg_tf.m:517` — 🟡 MEDIUM · CONFIRMED

**Interaction TFCE loops use length(LIMO.design.fullfactorial) (a 0/1 flag, length 1) instead of length(LIMO.design.nb_interactions), so only the first interaction term is ever processed.**

- **Why:** LIMO.design.fullfactorial is a scalar flag (0 or 1), so length(LIMO.design.fullfactorial)==1 always. Lines 517 and 530 use it as the loop bound for the observed and H0 interaction TFCE, whereas the correct count length(LIMO.design.nb_interactions) is used everywhere else (lines 227, 399). Designs with more than one interaction term (e.g. a three-factor fullfactorial with multiple two-way and three-way interactions) will only TFCE-process Interaction_effect_1 / H0_Interaction_effect_1.
- **Category:** `logic/copy-paste`

#### 141. `limo_expected_chanlocs.m:260` — 🟡 MEDIUM · CONFIRMED

**After interactively deleting external (EX) channels from EEGLIMO.chanlocs, the per-channel subject counter is not updated, so the low-count removal indexes the wrong channels.**

- **Why:** counter is built to align 1:1 with EEGLIMO.chanlocs (reference channels first, appended channels after). Lines 244-257 remove EX channels from EEGLIMO.chanlocs but never remove the corresponding entries from counter. Line 260 then does EEGLIMO.chanlocs(find(counter < min_subjects)) = []. Because counter still contains the removed EX positions, find(...) returns indices in the pre-removal numbering; applied to the now-shorter chanlocs array these indices are shifted (and can exceed bounds), so the wrong channels are dropped from the expected cap, or an out-of-range assignment error occurs.
- **Category:** `indexing`

#### 142. `limo_get_anova_files.m:21` — 🟡 MEDIUM · CONFIRMED · R2-new

**dir('AN(C)OVA*') treats the parentheses literally, so it never matches the real 'ANOVA'/'ANCOVA' folders and dirContent is always empty.**

- **Why:** Line 21 does dirContent = dir('AN(C)OVA*'). MATLAB's dir only honors * and ? as wildcards; every other character, including '(' and ')', is matched literally. The clear intent is a regex-style 'match ANOVA or ANCOVA', but as written the pattern only matches names beginning with the literal characters 'AN(C)OVA'. LIMO creates folders named 'ANOVA', 'ANCOVA', 'Rep_Meas_ANOVA' (see limo_random_effect.m update_dir calls), none of which contain '(C)'. Therefore dirContent is always empty, and the function always falls into the isempty(dirContent) branch (line 23) presenting the 'you need to run an ANOVA first' dialog even when valid ANOVA result folders exist. The automatic ANOVA-folder detection/selection path (lines 41-55) is effectively dead.
- **Category:** `indexing-glob`

#### 143. `limo_get_anova_files.m:31` — 🟡 MEDIUM · CONFIRMED

**Calls limo_get_result_files (plural), which does not exist in the toolbox (only limo_get_result_file singular), causing an undefined-function crash on the 'Run 1st-level contrast' path.**

- **Why:** When no AN(C)OVA folder is found and the user selects the second option ('Run 1st-level contrast'), the code executes `[Names,Paths,Files,txtFile] = limo_get_result_files(varargin);`. No function named limo_get_result_files exists anywhere in the repo (verified: only limo_get_result_file.m, singular). This throws 'Undefined function or variable limo_get_result_files'. Additionally, even with the correct name, `varargin` (a cell) is passed as a single argument rather than expanded with varargin{:}, and limo_get_result_file returns [FileName,PathName,FilterIndex] (3 outputs), not the 4 expected here — so the call is doubly broken.
- **Category:** `data-handling-typo`

#### 144. `limo_get_effect_size.m:147` — 🟡 MEDIUM · CONFIRMED

**Two-samples Cohen's d reuses the one-sample formula mu/(se*sqrt(n)), but the two-samples file stores se as the SE of the difference (sqrt(var1/n1+var2/n2)), not sd/sqrt(n), so d is mis-scaled (roughly halved for equal n).**

- **Why:** The one-sample and paired-samples files store se = sd/sqrt(n) (limo_random_robust.m lines 187 and 520), so mu/(se*sqrt(n)) correctly recovers mu/sd = Cohen's d. But the two-samples file stores se = sqrt(sd1^2/n1 + sd2^2/n2) (limo_random_robust.m line 351-352), the standard error of the mean difference, and df = n1+n2-2 so n = df+1 = n1+n2-1. Substituting into mu/(se*sqrt(n)) does NOT yield the pooled-SD-based Cohen's d. For equal n and variances, se*sqrt(n1+n2-1) approximately equals 2*sd_pooled, so the reported d is about half the true independent-samples Cohen's d. The same line 95-109 code path handles one_sample, two_samples, and paired_samples uniformly, which is only valid for the first and third.
- **Category:** `statistics-normalization`

#### 145. `limo_get_effect_size.m:264` — 🟡 MEDIUM · CONFIRMED

**Cluster loop uses size(num,2) as the cluster count, but num=unique(mask) is a column vector for 2D/3D masks, so size(num,2)==1 and only the first cluster is ever summarized.**

- **Why:** `num = unique(mask)` (line 262) returns a COLUMN vector when mask is a matrix (channels x frames) or higher-dimensional array, regardless of how many unique cluster labels exist. Therefore size(num,2) is 1, and `for c = size(num,2):-1:1` iterates only for c=1, computing clusters(1) from num(1) and ignoring every other cluster. The loop should count the number of unique labels via numel(num) or size(num,1). (Only in the degenerate single-channel case where mask is a 1-row vector does unique return a row vector and the loop happen to work.)
- **Category:** `indexing-dimension`

#### 146. `limo_get_model_data.m:39` — 🟡 MEDIUM · CONFIRMED

**In the 'Adjusted' branch `allvar` (all regressors except the one of interest) is computed but never used; confounds are subtracted using the FULL model, yielding residuals instead of adjusted data.**

- **Why:** Lines 39-40 build `allvar = 1:size(X,2)-1; allvar(regressor)=[];` clearly intending to subtract only the nuisance regressors. But `confounds` at line 53 is `X*Betas` over the entire design (all columns), and `Ya = Yr - confounds` at line 55 removes every modelled effect including the regressor of interest. The result is the model residuals, not data adjusted for confounds while preserving the regressor's effect. The dead `allvar` variable is direct evidence the subtraction was meant to be restricted to `X(:,allvar)*Betas(allvar,:)`.
- **Category:** `numerics-stats`

#### 147. `limo_glm.m:283` — 🟡 MEDIUM · CONFIRMED · R2-new

**HC4 branch stores the parameter variance (diagonal of the sandwich covariance) into betas_se without taking the square root, so reported standard errors are variances, not standard errors.**

- **Why:** At line 283 the HC4 option computes `model.betas_se(:,t) = diag((pinv(WX'*WX))*WX'*diag(HC4(:,t))*WX*(pinv(WX'*WX)))`, i.e. the diagonal of the heteroskedasticity-consistent covariance matrix, with no sqrt. Every other betas_se computation in the file takes a square root: the standard OLS/WLS branch (line 285, `sqrt(...)`) and the IRLS branch (line 989, `sqrt(diag((E/dfe)*pinv(WX'*WX)))`). Since the field is named betas_se (standard error), the HC4 path returns squared units (variances), which is wrong for any downstream use as a standard error (e.g. t = beta/betas_se).
- **Category:** `statistical`

#### 148. `limo_glm.m:285` — 🟡 MEDIUM · CONFIRMED

**OLS/WLS parameter standard errors are computed as a single scalar (identical for every regressor) using a bogus pooled denominator instead of the per-parameter sqrt(diag((E/dfe)*pinv(WX'WX))).**

- **Why:** The right-hand side is entirely scalar: sqrt(E(t)/dfe) is scalar and sqrt(sum(sum((WX-mean(WX)).^2))) collapses the whole design matrix to one number. Assigning a scalar to model.betas_se(:,t) fills the column so every beta gets the SAME standard error, and that value is not a valid SE for any coefficient (it divides by the total sum of squared, mean-centred design entries pooled across all columns). The correct formula is literally in the adjacent comment (line 286) and is the one actually used in the IRLS branch (line 989: sqrt(diag((E/dfe)*pinv(WX'*WX)))). So OLS and WLS report wrong, undifferentiated betas_se; the same defect is duplicated in the WLS-TF branch at line 601.
- **Category:** `numerics/stats-wrong-SE`

#### 149. `limo_glm.m:876` — 🟡 MEDIUM · CONFIRMED

**WLS-TF interaction reshape block copies the conditions (main-effect) results into the interactions fields, loops over the wrong index, and overwrites conditions instead of interactions.**

- **Why:** In the final reshape section for 'WLS-TF', the interaction block (lines 874-887) is broken three ways: (1) for nb_factors==2 it does model.interactions.F = reshape(model.conditions.F,...) and likewise for .p, silently replacing the interaction F/p with the main-effect F/p; (2) the else branch uses 'for f = length(nb_interactions)', which iterates a single time at the maximum index instead of 'for f = 1:length(nb_interactions)', leaving lower interaction rows unpopulated; (3) inside that else branch it writes back into model.conditions.F/model.conditions.p (lines 883-884) instead of model.interactions.F/p, corrupting the already-reshaped conditions and never producing reshaped interactions. Contrast the correct conditions block at lines 863-870.
- **Category:** `data-handling/copy-paste`

#### 150. `limo_glm_boot.m:451` — 🟡 MEDIUM · CONFIRMED · R2-new

**F_CONTVALUES/p_CONTVALUES have inconsistent orientation between OLS/WLS and IRLS: OLS/WLS transpose to [frames x ncovariates] (line 451-452) while IRLS returns [ncovariates x frames] untransposed (line 540, 770).**

- **Why:** In the OLS/WLS branch, F_CONTVALUES{B} = F_continuous' and p_CONTVALUES{B} = pval_continuous' (lines 451-452), where F_continuous is NaN(nb_continuous,size(Y,2)); the transpose makes the stored cell [frames x nb_continuous]. In the IRLS path, glm_iterate allocates F_continuous = NaN(nb_continuous,size(Y,2)) (line 540) and returns it WITHOUT transposing, so F_CONTVALUES{B} is [nb_continuous x frames]. The two methods therefore hand back covariate F/p cubes with swapped axes. For nb_continuous>1 (multi-covariate regression/ANCOVA) any downstream code in limo_glm_handling that assumes a single orientation will index the wrong axis for one of the two method families; for nb_continuous==1 the row/column mismatch can also break concatenation.
- **Category:** `correctness`

#### 151. `limo_glm_boot.m:748` — 🟡 MEDIUM · CONFIRMED

**In the IRLS higher-order interaction loop the p-value is written to the entire row (f,:) with a scalar each frame, so after the frame loop every frame holds only the last-processed frame's p-value.**

- **Why:** Inside glm_iterate's `for frame = size(Y,2):-1:1` loop, line 748 does pval_interactions(f,:) = 1 - fcdf(F_interactions(f,frame), df_interactions(f,frame), dfe(frame)); The RHS is a scalar (all terms indexed by the single current frame), but the LHS (f,:) assigns it to ALL frames of row f, overwriting them every iteration. Since the loop counts down, the surviving value is frame 1's p-value broadcast across every frame. The neighboring lines 745-747 correctly use (f,frame). This corrupts the null p-value map for interactions (F_interactions itself is stored correctly). It is reached only for IRLS with nb_factors>1 and interactions that are not the 2-factor/no-covariate quick case (i.e. 3+ factors, or 2 factors with a covariate).
- **Category:** `indexing-broadcast`

#### 152. `limo_glm_handling.m:820` — 🟡 MEDIUM · CONFIRMED

**TFCE interaction loop iterates over length(fullfactorial) (always 1) instead of length(nb_interactions), so only the first interaction ever gets TFCE.**

- **Why:** fullfactorial is a scalar flag (the enclosing guard is `LIMO.design.fullfactorial == 1`), so `length(LIMO.design.fullfactorial)` is always 1 and the loop `for i=1:length(LIMO.design.fullfactorial)` runs exactly once, computing TFCE only for Interaction_effect_1. Every sibling loop in the file correctly uses `length(LIMO.design.nb_interactions)` (e.g. lines 322, 682) which enumerates all interaction terms, and the observed Interaction_effect_i.mat files for i>1 are all created at line 322. Those i>1 interaction effects therefore never receive a TFCE map, so any TFCE-corrected inference on higher-order interactions is silently missing.
- **Category:** `control-flow/indexing`

#### 153. `limo_glm_null.m:24` — 🟡 MEDIUM · CONFIRMED

**For continuous/regression designs the null data is built with an independent per-channel randperm, destroying the shared cross-channel resampling that spatial clustering under H0 relies on.**

- **Why:** When nb_conditions==0 (pure regression), null_y = y(randperm(size(y,1),size(y,1)),:) applies a fresh independent random permutation. limo_glm_boot is called once per channel (limo_glm_handling channel loop), and the shared boot_table (built by limo_create_boot_table specifically so 'almost the same resampling is applied across channels' to preserve spatial noise correlation) is applied AFTER this permutation. The effective original-trial index for channel c at bootstrap B becomes perm_c(boot_table(:,B)); since perm_c differs per channel, different subjects/trials are selected per channel within the same bootstrap, so the spatial correlation structure needed for valid spatial-temporal cluster/max-stat correction is broken. The categorical branch (deterministic within-group centering + shared boot_table) correctly preserves this structure, so the continuous branch is inconsistent. The per-channel permutation is also redundant because resampling Y rows against a fixed X already breaks the Y-X link.
- **Category:** `resampling-spatial-structure`

#### 154. `limo_harrell_davis.m:57` — 🟡 MEDIUM · CONFIRMED · R2-new

**Harrell-Davis weights are computed for the full length n but then subset by non-NaN mask, yielding wrong order-statistic weights (that no longer sum to 1) whenever NaNs are present.**

- **Why:** The weight vector w (line 50) is `betacdf(vec./n,...)-betacdf((vec-1)./n,...)` with vec=1:n and n=size(data,3) (full third-dim length, NaNs included). At lines 57 and 96 the estimate is `sum(w(~isnan(tmp_data))'.*tmp_data(~isnan(tmp_data)))`. When tmp_data contains k NaNs, only n-k weights are selected, but those weights were derived for an n-length sample. HD weights depend on the effective sample size, so the retained weights neither sum to 1 nor correspond to the correct order-statistic positions of the reduced sample -> biased quantile estimate. Additionally the <=10-observation guard (line 70) uses the NaN-inclusive count, so a slice with many NaNs can proceed with too few valid points.
- **Category:** `nan/empty-mishandling`

#### 155. `limo_harrell_davis.m:80` — 🟡 MEDIUM · CONFIRMED

**The confidence-interval constant selection tests q against decile-index thresholds (1,2,8,9) but q is a fraction in [0,1], so the conditions are always true and the wrong Wilcox c-constant is applied for small samples.**

- **Why:** q is documented and used as a quantile fraction in [0,1] (e.g. 0.5 for the median; limo_central_estimator calls it with .5, limo_robust_ci with .5). The branch conditions on lines 80 and 86, `q<=2 || q>=8` and `q<=1 || q>=9`, are written for q expressed as an integer decile (1-9). Because 0<q<1, `q<=2` and `q<=1` are ALWAYS true and `q>=8`/`q>=9` never matter. As a result, for n<=40 the code ALWAYS overwrites the correct default c=1.96+.5064*n^-.25 with c=36.2/n+1.31 (the constant Wilcox tabulated only for the 1st/9th deciles), regardless of which quantile is requested. The middle branch (n<=21 -> c=-6.23/n+5.01) is dead because the n<=40 branch always overrides it. This yields the wrong CI coverage constant for the median and every non-extreme quantile at small n.
- **Category:** `logic`

#### 156. `limo_itc.m:448` — 🟡 MEDIUM · CONFIRMED

**The regression branch repeats the sub-1+cond write-index collision, corrupting Y1 when more than one condition is selected.**

- **Why:** Same pattern as the two-sample branch: Y1 = nan(...,Nsub*Nconds(1)) but the write uses index sub-1+cond, which is only unique when Nconds(1)==1. With multiple selected conditions the per-subject slots overlap, so the regressor rows in cont_data no longer align with the correct subject/condition data (and the length check at line 426 passes while the mapping is still wrong).
- **Category:** `indexing`

#### 157. `limo_itc_gui.m:311` — 🟡 MEDIUM · CONFIRMED

**Done_Callback reads handles.chanlocs which is never initialized, crashing if the user does not first click Select_chanlocs.**

- **Why:** handles.chanlocs is only created inside Select_chanlocs_Callback (line 347). It is not initialized in the OpeningFcn (lines 43-67). Done_Callback unconditionally reads it at line 311. If the user completes the dialog without selecting a chanlocs file, MATLAB throws 'Reference to non-existent field chanlocs', aborting the Done handler so the GUI never returns its defaults.
- **Category:** `data-handling`

#### 158. `limo_itc_import_data.m:130` — 🟡 MEDIUM · CONFIRMED

**In the Time-Frequency lowf branch the value is read from the nonexistent field `EEGLIMO.etc.limo_psd_freqlist` rather than `EEGLIMO.etc.tf_freqs`, causing a crash or a wrong frequency.**

- **Why:** Every other reference in this Time-Frequency block uses `EEGLIMO.etc.tf_freqs` (including the `position = min(abs(EEGLIMO.etc.tf_freqs - defaults.lowf))` on the line just above). Line 130 instead indexes `EEGLIMO.etc.limo_psd_freqlist`. Grep of the codebase shows the only place that field is produced (limo_power_spec_from_erp.m) has its assignment commented out, so `EEGLIMO.etc.limo_psd_freqlist` normally does not exist and the reference throws 'Reference to non-existent field'. Even if present, it is a different vector than tf_freqs, so LIMO.data.lowf would be set from the wrong array.
- **Category:** `wrong-field`

#### 159. `limo_itc_import_data.m:143` — 🟡 MEDIUM · CONFIRMED

**The high-frequency value is stored into the misspelled field `LIMO.data.hightf` instead of `LIMO.data.highf`, so LIMO.data.highf is never set on this branch.**

- **Why:** Downstream code (limo_display_image.m, limo_display_results.m, limo_check_weight.m, limo_display_image_tf.m) consistently reads `LIMO.data.highf` to build frequency axes (e.g. `linspace(LIMO.data.lowf,LIMO.data.highf,...)`). In the branch where the user supplies a valid `defaults.highf`, this code writes `LIMO.data.hightf` (a typo) and leaves `LIMO.data.highf` unset. The other two branches (empty / out-of-range) correctly set `LIMO.data.highf`, making this an inconsistent copy-paste typo.
- **Category:** `wrong-field`

#### 160. `limo_mglm.m:157` — 🟡 MEDIUM · CONFIRMED

**The WLS branch with user-supplied weights multiplies by undefined variables WX and WY, crashing whenever weights are provided.**

- **Why:** In all four method blocks (lines 157, 299, 438, 777) the `strcmp(method,'WLS')` case, when W is non-empty, does `Betas = pinv(WX)*WY;`. `WX` and `WY` are never defined (the weighted design/data are not formed); the intent was presumably `pinv(W.*X)*(W.*Y)` or similar. Compounding this, when weights are passed positionally the code at line 112 does `W = varargin(7)` using parentheses (cell) rather than braces, so W is a 1x1 cell rather than the weight matrix.
- **Category:** `undefined-variable`

#### 161. `limo_mglm.m:180` — 🟡 MEDIUM · CONFIRMED · R2-new

**Escoufier/RV effect-size denominator uses element-wise `.^2` instead of the matrix square, so model.R2.V drops all off-diagonal covariance and is inflated**

- **Why:** The generalized R2 (Robert & Escoufier RV coefficient) is computed as `trace(Sxy*Syx) / sqrt(trace(Sxx.^2)*trace(Syy.^2))`. The numerator uses genuine matrix products, but the denominator uses `Sxx.^2` / `Syy.^2`, which is ELEMENT-WISE squaring. `trace(Sxx.^2)` sums only the squared diagonal entries (sum_i Sxx(i,i)^2), whereas the RV coefficient requires `trace(Sxx*Sxx)` = sum over ALL i,j of Sxx(i,j)^2 (the squared Frobenius norm). Whenever the regressors or the electrodes are correlated (nonzero off-diagonal covariances — essentially always), the denominator is too small and Rsquare_multi (reported as model.R2.V) is systematically inflated and can exceed 1. This is the same mistake in all four branch copies (lines 180, 324, 463, 801) and is unrelated to the already-reported eigenvector-capture bug.
- **Category:** `statistical-correctness`

#### 162. `limo_mglm.m:618` — 🟡 MEDIUM · CONFIRMED

**Interaction F statistics use the leftover main-effect eigenvalues (Eigen_values_cond) instead of the interaction eigenvalues (Eigen_values_inter).**

- **Why:** In the interaction Roy/Pillai computations, several formulas reference `max(Eigen_values_cond)` — a variable left over from the preceding main-effects loop — rather than `max(Eigen_values_inter)` that was just computed for the interaction. This occurs at lines 618 (Roy F, 2-factor quick path), 632 (Pillai F, s==1 quick path), 735 (Roy F, general path), and 749 (Pillai F, s==1 general path). The interaction F is therefore computed from the wrong effect's eigenvalue.
- **Category:** `statistics-correctness`

#### 163. `limo_mglm.m:841` — 🟡 MEDIUM · CONFIRMED

**The continuous-effect error df subtracts length(nb_conditions)=1 instead of the actual number of condition/interaction columns, inflating dfe and biasing the p-value.**

- **Why:** At line 825 nb_conditions is reassigned to the SCALAR total `sum(nb_conditions)+sum(nb_interactions)` (number of dummy+interaction columns). Line 840-842 then does `if nb_conditions~=0, dfe_continuous = dfe_continuous - length(nb_conditions); end`; length() of a scalar is 1, so it removes only 1 df regardless of how many categorical columns the model has. The intended correction is to subtract the number of those columns (i.e. the value nb_conditions), so dfe_continuous is too large and F_continuous p-values are anti-conservative.
- **Category:** `statistics-df`

#### 164. `limo_mglm.m:884` — 🟡 MEDIUM · CONFIRMED

**The output-assembly block reads interaction results from variables named with plural `interactions`, but they were computed under singular `interaction`, so the names are undefined.**

- **Why:** Lines 884-891 assign from `F_interactions_Pillai`, `pval_interactions_Pillai`, `df_interactions_Pillai`, `dfe_interactions_Pillai`, `F_interactions_Roy`, etc. The variables actually computed in the interactions branch are singular: `F_interaction_Pillai`, `pval_interaction_Pillai`, `df_interaction_Pillai`, ... (lines 611-635, 728-752). None of the plural names are ever defined, so the guarded block `if nb_interactions ~= 0` will error on the first line. (This block is only reached once the earlier repamt/undefined-variable crash on line 502 is fixed, but it is an independent latent defect.)
- **Category:** `name-mismatch`

#### 165. `limo_mstat_values.m:80` — 🟡 MEDIUM · CONFIRMED · R2-new

**On the bootstrap error/fallback path the code cd's into 'H0' but never cd's back, leaving the working directory corrupted**

- **Why:** The pattern `try cd('H0');load(MCC_data); cd ..` (lines 80, 154, 225) changes into the H0 subdirectory before loading. If `load(MCC_data)` fails (bootstrap file absent) or any statement before `cd ..` throws (e.g. the already-reported size(M,2) loop, or U rounding to 0), control jumps to the catch block WITHOUT executing `cd ..`. The catch computes the theoretical-threshold fallback and returns, but the process is left with its current directory inside 'H0'. The caller (limo_display_results) then loads/saves subsequent files relative to the wrong directory, causing file-not-found errors or writes to the wrong location.
- **Category:** `state-corruption`

#### 166. `limo_mstat_values.m:89` — 🟡 MEDIUM · CONFIRMED

**The bootstrap p-value loop iterates over size(M,2) but M is a column vector [channels x 1], so it computes a p-value for only the first channel and returns M as a scalar.**

- **Why:** M = squeeze(R2(:,4)) (or Condition_effect(:,3)) is a [channels x 1] column vector, so size(M,2)==1 and the loop 'for column = 1:size(M,2)' runs exactly once, computing tmp(1)=sum(M(1)>sorted_values(1,:)). M is then overwritten as M = 1-(tmp./nboot), a 1x1 scalar, discarding p-values for channels 2..N. mask (line 88) was correctly computed for all channels, so the returned p-value map M and the mask now have mismatched sizes; after mask=mask';M=M' (line 116) M is scalar while mask is 1xchannels, causing wrong/garbage p-value display or a downstream size error. The loop clearly should iterate over rows (channels): for row = 1:size(M,1) using M(row) and sorted_values(row,:). Same defect is duplicated at lines 163-166 (Condition_effect) and 234-237 (Covariate_effect).
- **Category:** `indexing/dimension`

#### 167. `limo_pair_channels.m:89` — 🟡 MEDIUM · CONFIRMED

**When several channels share the same |theta|, the left/right radius match uses rem() as a distance and indexes the left-radius array with right-side indices, selecting the wrong contralateral electrode.**

- **Why:** To find the left electrode at the 'same' radius as a right electrode, line 89 computes min(rem(Lradius(index),R_value)). rem is the modulo remainder, not a distance: for R_value=0.3 and Lradius=[0.29,0.61], rem gives [0.29,0.01] so it picks 0.61 although 0.29 is far closer. Additionally, index are positions within the Rtheta/Rradius arrays being used to index Lradius (a different, left-side array), so the candidate set itself is mismatched.
- **Category:** `numerics`

#### 168. `limo_path_update.m:62` — 🟡 MEDIUM · CONFIRMED

**When called programmatically with a filename argument, `newpath` is never assigned yet is read at line 62 (and 71, 75, 112, 160), causing an undefined-variable crash.**

- **Why:** `newpath` is only assigned inside the `nargin==0` interactive branch (lines 38 and 41). The documented FORMAT `limo_path_update(filesin,newpath)` implies a second argument, but the function signature is `limo_path_update(filesin)` — there is no `newpath` parameter. In the `else` (nargin>0) block (lines 47-65) that handles a `.mat` char, a `.txt` char, or a cell array, `newpath` is never set, so `if ~exist(newpath,'dir')` at line 62 throws 'Unrecognized function or variable newpath'.
- **Category:** `control-flow`

#### 169. `limo_path_update.m:160` — 🟡 MEDIUM · CONFIRMED

**In the txt-update loop over `p`, the rebuilt path uses the stale outer index `i` (`Paths{i}`) and the last-iteration `common_str`, so all entries are derived from a single leftover subject.**

- **Why:** Section 4 (lines 155-164) loops `for p=1:length(Paths)` to rewrite each file entry, but line 160 references `Paths{i}` — `i` is the leftover value from the earlier `for i=size(Paths,2):-1:1` loop (which ended at 1), and `common_str` is likewise whatever it was on that loop's last iteration. Every `Files{p}` is therefore built from `Paths{1}`'s suffix rather than `Paths{p}`, while only `Names{p}` varies. The written txt list points every subject at the same source path.
- **Category:** `indexing`

#### 170. `limo_plot_difference.m:374` — 🟡 MEDIUM · CONFIRMED

**Passing the documented 'fig','off' option makes the plotting guard throw a non-scalar-logical error, aborting the function before it returns.**

- **Why:** The guard is `if strcmp(figure_flag,'on') || figure_flag == 1`. figure_flag is taken verbatim from the key/value pair (line 160-161), so 'off' is stored as a char row vector. When it is 'off', strcmp('off','on') is false, so MATLAB must evaluate the right operand of `||`. `'off' == 1` is elementwise char-vs-double comparison yielding the 1x3 logical [0 0 0], which is not scalar. The `||` operator requires a scalar-convertible operand and throws 'Operands to the || and && operators must be convertible to logical scalar values.' The intended behavior (skip the figure) never happens and the whole call errors out.
- **Category:** `control-flow`

#### 171. `limo_plots.m:131` — 🟡 MEDIUM · CONFIRMED

**FDR correction is computed on a truncated subset of p-values (only those < 0.5), giving an anti-conservative, incorrect FDR threshold.**

- **Why:** Benjamini-Hochberg/Yekutieli FDR sorts the full set of m p-values and finds the largest k with p(k) <= (k/m)*q. Passing only `pval(pval<0.5)` discards every p-value >= 0.5, shrinking m. A smaller m steepens the k/m*q line and yields a larger (more liberal) threshold pID/pN, so more cells are declared significant than a correct FDR over all tests would allow. The same defect is repeated at line 139 for the electrode-wise correlation. limo_FDR should receive the complete p-value vector (as a column), e.g. `limo_FDR(pval(:),.05)`.
- **Category:** `statistics`

#### 172. `limo_plots.m:132` — 🟡 MEDIUM · CONFIRMED

**The FDR mask is inverted: it blanks out the SIGNIFICANT correlations (p < threshold) and leaves the non-significant ones colored.**

- **Why:** After FDR, cells with pval below the threshold pN are the significant ones. Setting `r(pval<pN)=NaN` replaces exactly those significant correlations with NaN, which the custom colormap (cc(1,:) = gray, line 147) renders as gray/blank. The colored cells that remain are therefore the NON-significant correlations, the opposite of the plot's stated purpose ('correlations with FDR correction'). The correct mask keeps significant cells and grays non-significant ones, i.e. `r(pval>pN)=NaN`. The same inversion is repeated at line 140.
- **Category:** `logic`

#### 173. `limo_prederror.m:45` — 🟡 MEDIUM · CONFIRMED

**N is only defined inside the `nargin==1` branch, so calling limo_prederror with an explicit k leaves N undefined and the function crashes at Nfold = round(N/k).**

- **Why:** Lines 41-44: `if nargin == 1`, N and k=5 are set. When the user supplies k (nargin==2), that branch is skipped, so N is never assigned. Line 45 immediately does `Nfold = round(N/k)`, and N is also used at lines 56-58 (`foldindex = 1:Nfold:N`, `foldindex(k+1)=N`, `randperm(N)`). With nargin==2 this throws 'Undefined function or variable N'. The documented FORMAT `errors = limo_prederror(LIMO,k)` is therefore broken for its only non-default use.
- **Category:** `control flow`

#### 174. `limo_random_effect.m:107` — 🟡 MEDIUM · CONFIRMED · R2-new

**differences_Callback deletes handles.figure1 then keeps operating on hObject (a child of that figure), causing an invalid-handle error.**

- **Why:** Inside the `if go` block, line 105 does delete(handles.figure1), which destroys the GUI figure and all its child uicontrols, including hObject (the differences button that fired the callback). After the block, line 107 calls set(hObject,'Visible','off'), then line 109 set(hObject,'Visible','on'), and lines 110/114 guidata(hObject,handles). All of these operate on the now-deleted hObject and throw 'Invalid or deleted object'. Contrast with Central_tendency_and_CI_Callback, which deletes figure1 and then returns without touching hObject. The delete plus subsequent set/guidata on the same handle is contradictory.
- **Category:** `deleted-handle`

#### 175. `limo_random_effect.m:335` — 🟡 MEDIUM · CONFIRMED · R2-new

**ANOVA_Callback has a duplicated inner `if strcmpi(handles.type,'Channels')`, making its else unreachable and leaving Components/Sources with no handler, so non-channel ANOVA silently does nothing.**

- **Why:** Line 334 opens `if strcmpi(handles.type,'Channels')` and line 335 immediately repeats the same test. Because the inner test can only be reached when the outer test was already true, the inner else (lines 340-341, which calls limo_random_select(answer,[],...) for non-channel data) is unreachable dead code. Meanwhile the outer if has no else at all, so when handles.type is 'Components' or 'Sources' the whole body is skipped and the ANOVA does nothing and gives no message. This differs from the t-test callbacks (e.g. One_Sample_t_test_Callback lines 203-210) which correctly branch Channels vs non-Channels.
- **Category:** `dead-code`

#### 176. `limo_random_robust.m:157` — 🟡 MEDIUM · CONFIRMED

**The minimum-valid-subjects guards count total subjects instead of non-NaN subjects because isnan is applied twice to an already-logical array (sum(isnan(tmp)) is always 0), so stats can run on 1-2 valid subjects instead of aborting.**

- **Why:** tmp = isnan(data(e,1,:)) is already logical, so sum(isnan(tmp)) re-applies isnan to a logical (never NaN) and is always 0. Thus length(tmp)==sum(isnan(tmp)) reduces to nsub==0 (never true) and (length(tmp)-sum(isnan(tmp)))<3 reduces to nsub<3, i.e. it tests the TOTAL subject count, not the count of valid (non-NaN) subjects; the intended count is sum(tmp). This double-isnan recurs at lines 154,157,306,309,312,315,480,483,642,645,648,737. The per-channel computation later strips NaN subjects, so a channel present in only 2 of many subjects passes the guard and a stat is computed on 2 observations and saved.
- **Category:** `nan-handling`

#### 177. `limo_random_robust.m:337` — 🟡 MEDIUM · CONFIRMED · R2-new

**Two-samples t-test result filename uses a format string with two %g specifiers but passes only the single argument `parameter`, producing a malformed name with a dangling underscore when `parameter` is scalar.**

- **Why:** Line 337 `name = sprintf('Two_Samples_Ttest_parameter_%g_%g',parameter);` and line 368 `boot_name = sprintf('Two_Samples_Ttest_parameter_%g_%g_desc-H0',parameter);` both have two `%g` conversions but only one value. When `parameter` is a scalar, sprintf consumes it for the first `%g` and stops at the second (no argument left), yielding e.g. 'Two_Samples_Ttest_parameter_5_' with a trailing underscore and no second value. The paired-test code (line 506) correctly handles this with `sprintf('..._%d_%d',parameter(1),parameter(end))`. Callers `limo_results.m:312` and `limo_display_results.m:149` pass a SCALAR (`str2double(...)`/`str2num(...)` of a single trailing token), so the malformed name is reachable in normal use. The result file and its H0 file are then written under the truncated name, breaking any downstream code/display that expects the canonical 'Two_Samples_Ttest_parameter_X' filename.
- **Category:** `save/load filename mismatch`

#### 178. `limo_random_robust.m:351` — 🟡 MEDIUM · CONFIRMED

**Two-sample t-test (Mean method) computes the standard error using group-1 variance for both terms instead of group-1 and group-2 variances.**

- **Why:** limo_ttest(2,...) returns sd as a 2-row matrix: sd(1,:)=std of group1, sd(2,:)=std of group2 (see limo_ttest.m line 60, sd=sqrt([s1.*n(1); s2.*n(2)])). Here the code does `sd = sd.^2; a = sd(1,:)./size(Y1,3); b = sd(1,:)./size(Y2,3);` and stores se=sqrt(a+b) into two_samples(:,:,2). Both a and b use sd(1,:) (group-1 variance); b should use sd(2,:) (group-2 variance). The stored standard error is therefore sqrt(var1/n1 + var1/n2) instead of the correct sqrt(var1/n1 + var2/n2). The t and p values are unaffected (they come directly from limo_ttest), but column 2 (the 'se' used for effect/CI plotting) is wrong whenever the two groups have unequal variances.
- **Category:** `numerics-stats`

#### 179. `limo_random_robust.m:477` — 🟡 MEDIUM · CONFIRMED

**Paired t-test 'unpaired data' guard is a no-op because `length(isnan(tmp2))` always equals the sample size, so mismatched NaN patterns silently mis-pair subjects.**

- **Why:** The check `if length(tmp) ~= length(isnan(tmp2))` intends to detect that the two conditions have different missing-data (NaN) patterns and abort as 'unpaired'. But `isnan(tmp2)` has the same size as tmp2, so `length(isnan(tmp2)) == length(tmp2) == size(data2,3)`, and `length(tmp) == size(data1,3)`, which are equal for any paired design. The guard therefore never fires for its intended purpose. Downstream, Y1 (line 512) and Y2 (line 513) each drop their own NaN subjects independently; if the NaN positions differ between conditions but the counts match, the two vectors contain different subjects that get paired element-wise, silently computing wrong paired differences with no error.
- **Category:** `logic`

#### 180. `limo_random_robust.m:604` — 🟡 MEDIUM · CONFIRMED

**Regression case loads data from a filename using malformed dynamic-field syntax, causing a crash whenever the data argument is passed as a file name string.**

- **Why:** Line 604 writes data = data.cell2mat(fieldnames(data)); which MATLAB parses as accessing a struct field literally named 'cell2mat' and then indexing it, rather than the intended dynamic field access. Every other case uses the correct form data = data.(cell2mat(fieldnames(data))); (e.g. line 132). The struct returned by load has no field 'cell2mat', so this throws.
- **Category:** `data handling`

#### 181. `limo_random_robust.m:687` — 🟡 MEDIUM · CONFIRMED

**In the regression case, the variable 'go' is only assigned inside the nargin>5 option loop when a 'go' pair is present, so passing 'zscore' without 'go' leaves go undefined and crashes at the read on line 687.**

- **Why:** When nargin>5 (line 618) the loop assigns go only if it encounters the 'go' option; the else branch that sets go='No' (line 627) runs only when nargin<=5. The parallel variable answer is guarded later by exist('answer','var') (line 663), but go has no such guard. Thus a caller that supplies the 'zscore' option but not 'go' reaches line 687 with go never defined.
- **Category:** `control flow`

#### 182. `limo_random_select.m:300` — 🟡 MEDIUM · CONFIRMED

**Regression covariate row-removal for discarded subjects is off-by-one and never `return`s, so it proceeds with a mis-aligned covariate (or later crashes).**

- **Why:** When size(X,1) > N (covariate file still contains rows for discarded subjects), lines 303-309 delete rows with `index` incrementing on every path while `X(index,:) = []` shrinks X, so after the first removed subject every subsequent deletion targets a row shifted by one - the wrong covariate rows are removed. Worse, after the loop line 316 unconditionally shows an errordlg but does NOT return, so execution continues to the regression with an X whose rows no longer correspond to the retained subjects. If sum(removed)==0 the adjustment is skipped entirely yet it still continues with size(X,1)>N, so the later `tmp_data(:,:,~isnan(sum(X,2)))` (lines 397/399) uses a logical index longer than the subject dimension and crashes.
- **Category:** `resampling`

#### 183. `limo_random_select.m:316` — 🟡 MEDIUM · CONFIRMED

**In the regression covariate branch, when size(X,1) > N the code shows an error dialog but never returns, so it falls through and later crashes; it also fires the error even after a successful adjustment.**

- **Why:** Lines 300-316: if the regressor has more rows than subjects, the inner block (lines 301-314) may correctly delete rows for removed subjects, but execution then unconditionally reaches `limo_errordlg(...)` at line 316 (shown even on success) and, crucially, there is no `return`. Whether or not adjustment happened, control continues to line 336+ and computes `Yr = tmp_data(:,:,~isnan(sum(X,2)))` (lines 397-399) with a logical mask longer than the data's subject dimension, producing an index/size error instead of a clean abort. Contrast with line 313 which does return inside the catch.
- **Category:** `control-flow`

#### 184. `limo_random_select.m:1044` — 🟡 MEDIUM · CONFIRMED

**ANCOVA covariate adjustment indexes the numeric `removed` matrix with cell syntax `removed{h}(i)`, so it throws and the whole adjustment is abandoned.**

- **Why:** For ANCOVA the data are gathered via getdata(2,...) (line 945). In getdata's stattest==2 branch `removed` is built as a NUMERIC matrix (`removed(igp,i)=0/1`, lines 2129/2165/2199/2204), not a cell array. The covariate-alignment loop at lines 1040-1048 does `if removed{h}(i) == 1`. Applying `{}` content-indexing to a numeric array raises `Cell contents reference from a non-cell array object`. That error is thrown inside the try at line 1039, caught at line 1050, and because `size(X,1) ~= sum(nb_subjects)` is still true the catch shows an errordlg and returns. Additionally the deletion itself is off-by-one: `index` increments on every subject (line 1043) while `X(index,:) = []` (line 1046) shrinks X, so after the first removed subject every later index points one row too far. Net effect: whenever any subject was discarded during data gathering (so the covariate vector is longer than the retained subjects), ANCOVA can never realign the covariate and simply aborts.
- **Category:** `data-handling`

#### 185. `limo_random_select.m:1099` — 🟡 MEDIUM · CONFIRMED

**N-way ANOVA/ANCOVA with '1 channel/component only' crashes because squeeze collapses the singleton channel dimension, producing a 2-D array that cannot be assigned into the 3-D tmp_data slice.**

- **Why:** For single-channel analysis getdata builds data{i} with size [1, frames, param, subjects]. At line 1099 (non-TF) `tmp_data(:,:,index:...) = squeeze(data{i}(:,:,current_param,:))`: selecting one param gives [1,frames,1,subj], and squeeze removes BOTH singleton dims (channel and param) yielding [frames, subj]. The LHS slice tmp_data(:,:,range) has size [1, frames, k]. MATLAB multi-subscript assignment requires matching shape, so [frames,k] into [1,frames,k] errors ('size of the left side ... right side ...'). The TF branch (line 1093) has the same defect. The one-sample, two-samples and paired paths explicitly re-add the channel dim (e.g. lines 352-357, 546-547, 739-743), but this N-way path does not.
- **Category:** `dimension`

#### 186. `limo_random_select.m:1236` — 🟡 MEDIUM · CONFIRMED

**When no repeated-measures factor is entered, the code warns but does not return, so it continues with an empty/zero factor_nb and crashes downstream.**

- **Why:** Lines 1235-1237: `if isempty(factor_nb) || length(factor_nb)==1 && factor_nb==0` shows `limo_warndlg('no factor entered, Rep. ANOVA aborded')` but has no `return`. Execution continues to the data-gathering and reshaping code that relies on `prod(factor_nb)` (e.g. lines 1315, 1530, 1539-1541, 1558), which with empty factor_nb yields prod([])==1 or errors, and with factor_nb==0 makes prod 0, corrupting preallocation and the subsequent squeeze/assignment. The warning message says 'aborded' implying an intended early exit that is missing.
- **Category:** `control-flow`

#### 187. `limo_random_select.m:1359` — 🟡 MEDIUM · CONFIRMED · R2-new

**The con-file 'paths provided' branch is unreachable because `all(size(LIMO.data.data(i,j)))` is always true, and it would use char subscripts `{num2str(i),num2str(j)}` if reached.**

- **Why:** At line 1356 `if all(size(LIMO.data.data(i,j)))` uses () indexing which always yields a 1x1 cell, so size==[1 1] and all()==true for every i,j; the elseif at line 1359 is dead code. The intended distinction (single path string vs. a provided list) is lost, so when the user passes an already-expanded list of file paths the code still calls `limo_get_files([],[],[],LIMO.data.data{i,j})` (line 1357) as if it were a path-to-a-list file. If the elseif were ever reached, `LIMO.data.data{num2str(i),num2str(j)}` indexes the cell with char codes (e.g. '1'->49) -> out-of-range error, and `LIMO.data.data{i}{i,j}` (line 1360) is also wrong nesting.
- **Category:** `indexing-error`

#### 188. `limo_random_select.m:1430` — 🟡 MEDIUM · CONFIRMED · R2-new

**For Components + Time-Frequency in the repeated-measures full-scalp branch, trimming uses `tmp(:,begins_at:ends_at,:)` where begins_at/ends_at are 2-element vectors, so only the first element is used and the result has the wrong shape.**

- **Why:** In the Time-Frequency path begins_at (line 1415, via fliplr) and ends_at (lines 1416-1417) are 2-vectors [time freq]. Line 1430 `matched_data = tmp(:,begins_at:ends_at,:)` evaluates begins_at:ends_at as begins_at(1):ends_at(1), trimming only one dimension and collapsing the rest into the trailing colon. The subsequent assignment `data(:,:,:,:,matrix_index)=matched_data` (line 1441) expects a 4-D block, so it errors or stores mis-shaped data. Compare the correct 2-D form used in getdata (line 1994): `tmp(:,begins_at(1):ends_at(1),begins_at(2):ends_at(2),:)`.
- **Category:** `dimension-error`

#### 189. `limo_random_select.m:1466` — 🟡 MEDIUM · CONFIRMED

**Channel-optimized Repeated-Measures ANOVA selects each subject's channel with the group-local index `out(i,:,:)` instead of the global `subject_index`, mismatching subjects to channels for groups after the first.**

- **Why:** In the rep-measures gather loop, `out = limo_match_elec(subj_chanlocs(subject_index).chanlocs, LIMO.data.expected_chanlocs, ...)` (line 1465) returns one row per expected channel, and expected_chanlocs was reduced to one entry per subject in match_channels (channel-optimized / vector electrode case). Rows of `out` are therefore ordered by the GLOBAL subject position. The very next line assigns `matched_data = out(i,:,:)` using the inner loop variable `i`, which restarts at 1 for every group `h`. Note the same statement already uses `subject_index` for `subj_chanlocs`, so mixing `i` and `subject_index` for the same subject is the defect. For the second group onward `out(i,...)` reads the wrong subject's optimized channel, silently assigning another subject's data.
- **Category:** `indexing`

#### 190. `limo_random_select.m:1566` — 🟡 MEDIUM · CONFIRMED

**Repeated-measures ANOVA with '1 channel/component only' crashes because squeeze drops the singleton channel dimension, giving a 2-D result incompatible with the 4-D tmp_data slice.**

- **Why:** For single-channel rep-measures, data is built with a leading singleton channel dim (lines 1478/1480, size [1,frames,param,subj]). At line 1566 `tmp_data(:,:,from:to,j) = squeeze(data(:,:,current_param(j),from:to))`: the RHS is squeeze([1,frames,1,k]) = [frames,k], while the LHS slice tmp_data(:,:,from:to,j) is [1,frames,k]. Shapes do not match and MATLAB errors. The TF branch (line 1564) is likewise affected. Unlike the t-test branches, no channel dimension is re-added here.
- **Category:** `dimension`

#### 191. `limo_random_select.m:1843` — 🟡 MEDIUM · CONFIRMED

**`match_channels` references the variable `Paths`, which is not in its scope, so loading a channel/component vector from a file always errors.**

- **Why:** match_channels(stattest,analysis_type,LIMO) receives only three arguments; `Paths` is a variable of the main function, not of this subfunction. In the branch where the user leaves the channel box empty and selects a .mat file containing a channel/component vector (lines 1833-1850), line 1843 does `if length(channel_vector) ~= length(Paths)`. `Paths` is undefined here, so MATLAB raises 'Unrecognized function or variable Paths', aborting the analysis exactly when the user tries to supply a per-subject channel vector via file.
- **Category:** `control-flow`

#### 192. `limo_random_select.m:2089` — 🟡 MEDIUM · CONFIRMED · R2-new

**getdata case 2 iterates groups descending and subjects ascending while match_frames indexes the flattened first_frame/last_frame with groups ascending and subjects descending, so per-subject trim offsets are applied to the wrong subjects.**

- **Why:** match_frames flattens a cell-of-cells Paths as `for gp=1:size` (ascending) and inner `for s=size:-1:1` (descending), building first_frame/last_frame in that order (lines 1640-1655). getdata case 2 reads subjects with `for igp=length:-1:1` (descending groups) and `for i=1:size` (ascending subjects), incrementing subject_nb 1,2,3... Thus subject_nb=1 is group-last/subject-1 but first_frame(1) belongs to group-first/subject-last. begins_at/ends_at (lines 2101/2110) are then computed from the wrong subject's trim indices.
- **Category:** `dimension-order-mismatch`

#### 193. `limo_read_events.m:30` — 🟡 MEDIUM · CONFIRMED · R2-new

**The nargin==0 branch references EEG before it is ever defined, crashing the documented no-argument usage.**

- **Why:** When called with no arguments, line 30 executes `storein = EEG.filepath;` but EEG is never a parameter and is never loaded in this branch (only the nargin>=1 branch calls pop_loadset into EEG at line 32). The header comment claims the empty-input mode 'will read the EEG variable already in the workplace', but a MATLAB function cannot see base-workspace variables, so EEG is undefined in function scope. Execution errors immediately at line 30, and the subsequent EEG.event loop (lines 43-45) would fail identically. checkcode's NODEF flag on line 30 confirms this. The entire documented no-argument mode is non-functional.
- **Category:** `undefined-variable`

#### 194. `limo_robust_rep_anova.m:79` — 🟡 MEDIUM · CONFIRMED

**type = nb_factors with only case 1 and case 2 defined means a design with 3 or more within factors falls through the switch and returns an unassigned `result`.**

- **Why:** type is set directly to the number of within factors, but the switch only implements case{1} and case{2}. For nb_factors >= 3 (e.g. a 2x2x2 within design, factor_levels=[2 2 2]), type==3 matches no case, the switch body does not execute, and `result` is never assigned, so the function returns with an undefined output variable. The non-robust limo_rep_anova avoids this by grouping all nb_factors>1 into a single multi-factor case (type 2). This is masked in current practice only because the signature bug (finding above) collapses nb_factors to 1, but once the signature is fixed a legitimate >=3-factor robust design crashes.
- **Category:** `control-flow`

#### 195. `limo_robust_rep_anova.m:107` — 🟡 MEDIUM · CONFIRMED

**The robust function never populates result.df / result.dfe, but its callers read those fields unconditionally.**

- **Why:** Case 1 sets only result.F and result.p (lines 107-108); case 2 sets only result.F, result.p, result.names (lines 133-134, 142-143). It never assigns result.df or result.dfe (nor result.repeated_measure.* / result.gp.* / result.interaction.* for between-subject designs). The callers require them: limo_random_robust.m line 1098 does `LIMO.design.df(channel)=result.df` and line 1108 `LIMO.design.df(channel,:)=result.df` (and lines 1099/1109 for result.dfe). The non-robust limo_rep_anova does set result.df/result.dfe (lines 211-212, 240-241, 251-252).
- **Category:** `data-handling/api-mismatch`

#### 196. `limo_stat_values.m:135` — 🟡 MEDIUM · CONFIRMED

**The Time-Frequency first-level H0 filenames are built with an 'H0_' infix (e.g. Condition_effectH0_1) whereas the files are saved with an 'H0' suffix (Condition_effect_1H0), so TF first-level effect MCC never finds the H0 file.**

- **Why:** In the Time-Frequency branch, first-level H0 names are Condition_effectH0_%s (line 135), Covariate_effectH0_%s (145), Interaction_effectH0_%s (155), semi_partial_coefH0_%s (165), conH0_%s (175). But limo_glm_handling saves these (name computed before the TF/non-TF split) as Condition_effect_%gH0 (651), Interaction_effect_%gH0 (684), etc. -> suffix 'H0' after the effect number, not an 'H0_' infix before it. The non-TF branch of the same function (lines 215/225/235/255) uses the correct suffix form, so only the TF branch is wrong (a copy error). Result: sub-XX_desc-Condition_effectH0_1.mat is requested but sub-XX_desc-Condition_effect_1H0.mat is on disk.
- **Category:** `save-load-mismatch`

#### 197. `limo_stat_values.m:456` — 🟡 MEDIUM · CONFIRMED

**Single-channel Time-Frequency repeated-measures ANOVA cluster correction uses size(bootT,4) for the bootstrap count, but bootT is 3D [freq x time x nboot] so size(bootT,4)==1, causing a size-mismatch assignment error.**

- **Why:** For Time-Frequency data bootT = squeeze(H0_data(:,:,:,1,:)); with a single channel this collapses to [Nfreq x Ntime x nboot] (3D), so size(bootT,4)==1. tmp becomes NaN(1,Nfreq,Ntime,1) = [1 x Nfreq x Ntime], and `tmp(1,:,:,:) = bootT` (line 457) then tries to assign an [Nfreq x Ntime x nboot] array into an [Nfreq x Ntime] region. The correct index is size(bootT,3), as used in the GLM TF branch at line 305 (size(bootM,3)). Same defect on the bootP assignment at line 458.
- **Category:** `indexing/dimension`

#### 198. `limo_stat_values.m:503` — 🟡 MEDIUM · CONFIRMED

**Single-channel Time-Frequency Rep_ANOVA correction preallocates the bootstrap dim with size(bootT,4), which is 1 for a 3D bootT, causing a dimension-mismatch crash (also at line 456).**

- **Why:** For Time-Frequency Rep_ANOVA, bootT = squeeze(H0_data(:,:,:,1,:)) collapses to [freq x time x nboot] (3D) when there is a single channel, so nboot is dimension 3. Lines 503 (max branch) and 456 (cluster branch) preallocate tmp = NaN(1,size(M,2),size(M,3),size(bootT,4)); but size(bootT,4)==1, making tmp's 4th (bootstrap) dimension 1. The following tmp(1,:,:,:) = bootT then assigns a [freq x time x nboot] array into a [1 x freq x time x 1] slot -> numel mismatch error. The correct index is size(bootT,3), consistent with the GLM single-channel TF handling at line 305 which uses size(bootM,3).
- **Category:** `indexing/dimension`

#### 199. `limo_stat_values.m:510` — 🟡 MEDIUM · CONFIRMED

**Single-channel Rep_ANOVA max correction preallocates the bootstrap dim with size(bootT,3), which is 1 for a 2D bootT, causing a dimension-mismatch crash.**

- **Why:** For non-Time-Frequency Rep_ANOVA, bootT = squeeze(H0_data(:,:,1,:)) is [frames x nboot] (2D) when there is a single channel. Line 510 builds tmp = NaN(1,size(M,2),size(bootT,3)); but size(bootT,3)==1 (bootT is only 2D), so tmp is [1 x frames x 1]. The next line tmp(1,:,:) = bootT tries to place a [frames x nboot] array (numel frames*nboot) into a slot of numel frames -> assignment error. The correct index is size(bootT,2) (nboot), exactly as used in the analogous single-channel cluster branch at line 465. This is caught by the surrounding try/catch and surfaces as a 'max correction failure' dialog with no result.
- **Category:** `indexing/dimension`

#### 200. `limo_tfce_handling.m:153` — 🟡 MEDIUM · CONFIRMED

**In the R2/semi-partial branch the per-bootstrap thresholded maps are captured with a whole-variable assignment inside parfor (tfce_H0_thmaps instead of tfce_H0_thmaps{b}), so the second output is not accumulated per bootstrap and the parfor usage is invalid.**

- **Why:** tfce_H0_thmaps is preallocated as cell(1,nboot) at line 148 and then read after the loop at line 180 (thresholded_maps{2} = tfce_H0_thmaps). But inside the parfor the second output is assigned to the whole variable, not a sliced element: line 153 '[tfce_H0_score(1,:,:,b),tfce_H0_thmaps] = ...' and line 159 '[tfce_H0_score(1,:,b),tfce_H0_thmaps] = ...'. Every other branch correctly uses tfce_H0_thmaps{b} (e.g. lines 219, 226, 235, 242, 289, 303). Assigning the full variable inside parfor makes it a temporary variable that is cleared after the loop, so it cannot be legitimately read at line 180; MATLAB either rejects the parfor ('the variable cannot be classified') or leaves the returned thresholded_maps{2} holding only the pre-loop empty cell rather than the per-bootstrap maps. This corrupts (or crashes on) the second, validation output for R2/semi-partial files with bootstrap; the primary saved tfce_H0_score is unaffected.
- **Category:** `data handling`

#### 201. `limo_tfce_handling.m:259` — 🟡 MEDIUM · CONFIRMED · R2-new

**The ess-file trimming Fval = Fval(:,:,end-1:end) uses 3-D indexing that is wrong for 4-D Time-Frequency ess data, collapsing the freq/time axes.**

- **Why:** For ess (contrast) files the code trims to the last two stat pages via Fval = Fval(:,:,end-1:end). This assumes Fval is 3-D [chan x time x npages]. For Time-Frequency data an ess Fval is 4-D [chan x freq x time x npages]; the 3-subscript form (:,:,end-1:end) linearizes dimensions 3 and 4 together and selects the last two columns of that flattened axis, producing a corrupted 3-D array instead of retaining freq x time. The subsequent size(Fval,1)==1 / Time-Frequency branch then calls squeeze(Fval(:,:,:,1)) on the mangled array, feeding wrong data (or wrong shape) into limo_tfce.
- **Category:** `indexing/dimension`

#### 202. `limo_tfce_handling.m:316` — 🟡 MEDIUM · CONFIRMED · R2-new

**When the tfce file already exists (e.g. user chooses 'overwrite'), the F/other branch dereferences thresholded_maps that was never assigned, crashing with an undefined-variable error.**

- **Why:** The observed-data TFCE is computed only inside if ~isfile(tfce_file) (line 255). If tfce_file already exists, that block is skipped and the output variable thresholded_maps is never set. In the F/other branch, lines 316-317 then unconditionally execute tmp = thresholded_maps; thresholded_maps{1} = tmp, referencing the unset variable -> 'Undefined function or variable thresholded_maps'. This is reachable via limo_results.m:352 (checkfile 'yes'): answering 'Yes' to the overwrite prompt sets LIMO.design.tfce=1 but does NOT delete the existing tfce_file, so ~isfile(tfce_file) is false and computation is skipped, leading straight to the crash. The R2 and t-test branches have the same latent issue at lines 178 and 247 but only when an H0 file also exists; the F branch crashes unconditionally.
- **Category:** `used-before-defined`

#### 203. `limo_tfcluster_test.m:57` — 🟡 MEDIUM · CONFIRMED · R2-new

**The observed-data clustering prefers bwlabeln with its default 8-connectivity while limo_tfcluster_make prefers spm_bwlabel with 6/4-connectivity, so on systems with both toolboxes the null and observed clusters use different neighbourhoods, invalidating FWER control.**

- **Why:** limo_tfcluster_make checks spm_bwlabel FIRST (lines 55-56/86-87) and uses spm_bwlabel(...,6), which on a 2D freq*time slice is 4-connectivity. limo_tfcluster_test checks bwlabel/bwlabeln FIRST (lines 57-58/89-90) and calls bwlabeln(...) with NO connectivity argument, defaulting to conndef(2,'maximal')=8-connectivity. On a machine where both the Image Processing Toolbox and SPM are installed, the H0 max-cluster distribution is built from 4-connected clusters while the observed clusters are 8-connected (merging diagonal neighbours). Larger observed clusters are then compared against a null built from smaller clusters, making the cluster test anti-conservative and the corrected p-values/threshold statistically inconsistent. limo_findcluster correctly passes explicit connectivity (spm 6 vs bwlabeln 4, both 4-conn) — tfcluster_test is the odd one out by omitting the bwlabeln connectivity argument and inverting the preference order.
- **Category:** `cluster-connectivity-mismatch`

#### 204. `limo_tfcluster_test.m:69` — 🟡 MEDIUM · CONFIRMED

**Inside the per-cluster loop the code re-initializes corrected_p/mask to a full NaN/zero map and assigns the ENTIRE (e,:,:) slice each iteration, so when an electrode has more than one cluster only the last cluster's p-values and mask survive.**

- **Why:** In the th.max branch (lines 65-75) each iteration does `corrected_p = NaN(Nf,Nt); corrected_p(L==C)=...; sigcluster.max_pvalues(e,:,:) = corrected_p;` — because corrected_p is rebuilt from all-NaN every C and then written over the whole electrode slice, cluster C=1's p-values are overwritten with NaN when C=2 is processed. The significance mask has the same defect at lines 71-73 (`mask = zeros(Nf,Nt); mask(L==C)=1; sigcluster.max_mask(e,:,:)=mask;`), and the th.elec branch repeats it at lines 99-101 and 103-105. The correct pattern (used by the sibling limo_ecluster_test, which indexes `sigcluster.elec_mask(channel,L==C)=...` directly) accumulates across clusters; this function does not. Result: for any electrode whose time*frequency map contains 2+ significant clusters, all but the last cluster vanish from both the mask and the p-value output.
- **Category:** `indexing/logic`

#### 205. `limo_trimmed_mean.m:113` — 🟡 MEDIUM · CONFIRMED

**tvar normalizes the trimmed variance by length(x), which returns the largest matrix dimension rather than the number of observations, giving the wrong denominator when frames exceed trials.**

- **Why:** Inside tvar, x is the reshaped [frames x trials] matrix and the trimmed variance should be normalized by the number of observations n = size(x,2) (trials/subjects, the trimming dimension used on lines 103-106). Line 113 instead uses length(x), which for a 2-D matrix returns max(size(x)) = max(frames, trials). When the number of time/frequency frames exceeds the number of trials/subjects (typical for second-level data: hundreds of frames, a few dozen subjects), length(x) returns the frame count, so the standard error se=sqrt(tv) is divided by the wrong count and the CI is mis-scaled. (This is independent of, and compounds, the percent/100 bug on line 103.)
- **Category:** `indexing/dimension`

#### 206. `limo_ttest_permute.m:71` — 🟡 MEDIUM · CONFIRMED

**The exact sign-permutation branch builds the +/-1 sign vector from a scalar, so only the first observation's sign is flipped and it can take non-unit values (3,5,7...), corrupting the entire H0 t-distribution.**

- **Why:** For exact permutations (taken whenever n_obs<=12), the code sets temp=perm-1 (a scalar), n_temp=length(temp) which is always 1, sn=-ones(n_obs,1), then sn(1:n_temp,1)=2*temp-1, i.e. it only assigns sn(1)=2*(perm-1)-1 and leaves sn(2:end)=-1. The original mult_comp_perm_t1 algorithm this is 'taken from' expands perm-1 into its n_obs-bit binary representation so each of the n_obs signs is set independently (sn(z)=2*mod(temp,2)-1; temp=floor(temp/2)). As written, (a) every permutation differs only in the sign of observation 1, so instead of 2^n_obs distinct sign patterns there are effectively 2, and (b) for perm>=3 the value 2*(perm-1)-1 is 3,5,7,... so the data is multiplied by 3,5,... rather than +/-1, producing meaningless t-values. The returned H0 t/p distribution is therefore wrong.
- **Category:** `resampling/permutation`

#### 207. `limo_yuen_ttest.m:70` — 🟡 MEDIUM · CONFIRMED

**The NaN-detection guard uses `if isnan(a(:))` which is true only when EVERY element is NaN, so realistic partially-NaN data bypasses the NaN-aware branch and silently returns NaN statistics.**

- **Why:** `isnan(a(:))` returns a logical column vector; `if <vector>` in MATLAB is true only if ALL elements are nonzero (all true). Therefore the NaN branch (option=2) is entered only when a (or b) is entirely NaN. Any input with SOME NaNs evaluates the condition as false and falls through to option=1 (case 1), which has no NaN handling: `sort(a,3)` pushes NaNs to the high end and `var(wa,0,3)` returns NaN for any channel/frame containing a NaN, so wva/da/Ty/p all become NaN. The intended guard is `if any(isnan(a(:)))` (and `elseif any(isnan(b(:)))`). As written, the entire NaN-handling machinery the authors deliberately wrote is dead for the only realistic case (partial missingness), and results are silently voided instead of computed.
- **Category:** `numerics/stats`

#### 208. `np_spectral_clustering.m:192` — 🟡 MEDIUM · CONFIRMED

**For a two-tailed test the cluster mass is the sum of one-sided rank statistics (Wilcoxon W+ for signrank, first-sample rank sum for ranksum), which are large for positive effects and near-zero for negative effects, so negative-direction clusters are systematically under-massed and the test has no power against them even though their per-frequency p-values are significant.**

- **Why:** test_rank stores stats.signedrank (W+, ranges 0..n(n+1)/2, ~n(n+1)/4 under H0) or stats.ranksum. These are strictly non-negative and monotone in the direction of the effect: a strong negative effect (spectra1 << spectra2) yields W+ near 0. The observed cluster mass (line 192) and the H0 max distribution (line 170) both sum these one-sided statistics. The H0 max is dominated by positive-direction spurious clusters (large W+), so boot_threshold is high, while a genuine negative-direction cluster contributes a tiny mass and cannot exceed the threshold. The clustering therefore only detects effects in one direction despite tail='both' being the default, silently discarding true negative clusters.
- **Category:** `numerics/stats`

#### 209. `limo_compute_H0.m:65` — 🟡 MEDIUM · PLAUSIBLE · R2-new

**Variable 'parameter' is used in filename and fprintf but never defined anywhere in the function**

- **Why:** `parameter` is referenced on line 65 (`sprintf('H0_one_sample_ttest_parameter_%g',parameter)`), line 89, and line 136, but it is never assigned nor passed in as an argument. Even if the `varagin` typos were fixed, the type-1 path would crash at line 65 building `boot_name`, and the type-0 limo_trimci path would crash at line 136. [Note: no static callers of limo_compute_H0 were found in the repo, so this is a latent/legacy defect rather than an active crash path.]
- **Category:** `undefined-variable`

#### 210. `limo_create_files.m:44` — 🟡 MEDIUM · PLAUSIBLE · R2-new

**The programmatic path never cd's to the LIMO file's folder, so `load Yr` / `load Betas` load from the caller's cwd rather than beside the LIMO file.**

- **Why:** The GUI branch does `cd(dir)` (line 20) so the hard-coded `load Yr` (line 44) and `load Betas` (line 61) resolve relative to the LIMO folder. The else/programmatic branch loads `varargin{1}` (which may be a full path) but never changes directory. Consequently `load Yr` and `load Betas` are resolved against the caller's current working directory, which generally is NOT where Yr.mat/Betas.mat live, causing a load failure or loading stale data from an unrelated directory. Like the X defect, this is presently masked by the line-36 tautology but is a separate latent bug.
- **Category:** `wrong-working-directory`

## ⚪ Low (77)

#### 211. `limo_AIC_BIC.m:84` — ⚪ LOW · CONFIRMED

**In the key/value path, Betas is computed via pinv(X)*Yr before Yr is transposed to match n, so a row/transposed Y errors out.**

- **Why:** When Betas is not supplied, line 84 computes `Betas = pinv(X)*Yr` (pinv(X) is [p x n]) requiring size(Yr,1)==n. But the orientation fix that transposes Yr when n==size(Yr,2) happens later at lines 87-93. So if the user passes Y as a [1 x n] row (or [frames x n]) vector, line 84 fails with a dimension mismatch before the transpose can correct it.
- **Category:** `indexing/dimension`

#### 212. `limo_AIC_BIC.m:124` — ⚪ LOW · CONFIRMED

**The 'family' option is never parsed from key/value inputs, so it is always 'gaussian', and the poisson/binomial branches reference undefined variables (beta_hat, y) making them dead-but-broken code.**

- **Why:** The documentation (lines 19, 128) advertises passing 'family' as 'gaussian'/'poisson'/'binomial'/'none', but the key/value parser (lines 60-73) only recognizes Y/Yr, B/Betas, X/Design, and k. There is no branch that sets `family` from varargin, so `family` remains its default 'gaussian' for every call path. Consequently the 'poisson' (line 127) and 'binomial' (line 125) branches are unreachable, and even if reached they use undefined variables `beta_hat` and `y` (the code uses `Betas`, `Yr` elsewhere), so they would error. A user who passes family='poisson' gets a silently ignored request and a Gaussian likelihood instead.
- **Category:** `control flow`

#### 213. `limo_BrownForsythe.m:31` — ⚪ LOW · CONFIRMED · R2-new

**Input dimension check uses && instead of ||, so a malformed input where only one array is non-3D is not rejected.**

- **Why:** Line 31 `if ndims(Y1r)~=3 && ndims(Y2r) ~=3` errors only when BOTH inputs fail the 3D requirement. If one input is a valid 3D matrix and the other is 2D (or otherwise not 3D), the condition is false and no error is raised; execution continues into the channel loop where `squeeze(Y1r(channel,:,:))` / `squeeze(Y2r(channel,:,:))` produce mismatched shapes and the GLM concatenation `[Z1 Z2]'` or covariance step misbehaves or crashes with an opaque error. The validating intent (both must be 3D) requires ||.
- **Category:** `logic-operator`

#### 214. `limo_batch_design_matrix.m:270` — ⚪ LOW · CONFIRMED · R2-new

**TF branch builds `subject_name` from all of `current_subject` rather than `current_subject(1)` as the Time and Frequency branches do, producing a multi-element cell that breaks the subsequent cellfun/strcmp when more than one dataset matches the data dir.**

- **Why:** Line 270: `subject_name = {STUDY.datasetinfo(current_subject).subject};`. The Time (line 69) and Frequency (line 167) branches use `current_subject(1)` to guarantee a single subject name. If `current_subject` (from the `find` at line 269) returns more than one index, `subject_name` becomes a 1xM cell, and line 274 `repmat(subject_name,n,1)` then produces an n x M cell that mismatches the n x 1 `Cluster_matrix.clust(c).subj'` in the cellfun(@strcmp,...) call, causing a size error.
- **Category:** `indexing`

#### 215. `limo_central_tendency_and_ci.m:412` — ⚪ LOW · CONFIRMED · R2-new

**The 'parameter not computed' warnings have format-string / argument mismatches and use the wrong variable, producing garbled messages.**

- **Why:** Line 412: `warning('subject %g, parameter %g not computed: \n the design only includes %g regressors plus the constant', Paths{i}, size(LIMO.design.X,2))` has three %g conversions but only two arguments, and Paths{i} (a char path) is fed to a %g numeric conversion (printed as character codes). The parameter value is never printed. The mirrored warnings at lines 781 and 783 additionally use the loop counter `j` instead of `parameters(j)` (line 780/783), so they report the wrong parameter index. These are message-only defects (no wrong result) but emit misleading/incorrect diagnostics.
- **Category:** `format-mismatch`

#### 216. `limo_check_neighbourghs.m:41` — ⚪ LOW · CONFIRMED

**The binary-matrix check `unique(x) == [0 1]'` errors or misfires when the neighbour matrix does not contain exactly the two values {0,1}.**

- **Why:** unique(channeighbstructmat) returns a sorted column of the distinct values. If the matrix is all zeros (unique=[0]) or all ones (unique=[1]), the comparison [0]==[0;1] broadcasts to [1;0] and ~all -> true, wrongly reporting 'not binary'. If the matrix somehow contains a third value, unique has 3 rows and == [0;1] throws a dimension-mismatch error rather than the intended message.
- **Category:** `numerics`

#### 217. `limo_check_weight.m:78` — ⚪ LOW · CONFIRMED

**Comparing analysis-type strings with `~=` errors on unequal-length char arrays instead of producing the intended clean 'mixed analyses' dialog.**

- **Why:** `limo.Analysis` and `LIMO_sub.Analysis` are char arrays such as 'Time', 'Frequency', 'Time-Frequency'. `if limo.Analysis ~= LIMO_sub.Analysis` does element-wise char comparison, which throws 'Matrix dimensions must agree' whenever the two strings differ in length. The same pattern at line 83 for `.Type` ('Channels' vs 'Components') also errors. The purpose is to warn about mixed analysis types, but instead the function crashes with an opaque dimension error.
- **Category:** `data-handling`

#### 218. `limo_clusterica.m:82` — ⚪ LOW · CONFIRMED

**For ERSP (and identically for ITC at lines 98-99) the code averages the similarity matrices of the 5 frequency bands with the lowest cross-correlation score, i.e. the noisiest/least-informative bands, whereas the comment states it keeps the best 5 and explicitly discards bands with noise.**

- **Why:** score(f) is the mean upper-triangular cross-correlation at frequency band f (higher = components more consistently related at that band). sort(score) is ascending, so ranking(1:5) are the 5 smallest scores - the bands with the weakest structure/most noise. The inline comment 'note the matrix M is the average of the best 5 frequency bands / no point looking at frequency bands with noise' indicates the intent was the opposite selection (the 5 highest-score bands). This flips which frequency information drives the ERSP/ITC similarity used in the mean similarity matrix MM (lines 153-161) and thus the clustering. Additionally, if a component set has fewer than 5 frequency bands, ranking(1:5) indexes out of bounds and errors.
- **Category:** `logic`

#### 219. `limo_clustering.m:112` — ⚪ LOW · CONFIRMED

**When called without the optional fig argument (nargin==7, the documented default), fig is [] and the guard `... && fig == 1` errors because `[]==1` yields an empty array that && cannot convert to a logical scalar.**

- **Why:** Lines 38-42 set fig=[] when nargin==7. At line 112, if no result is significant then `sum(mask(:))==0` is true and MATLAB evaluates the right operand `fig==1`, which is `[]==1` = 0x0 empty logical; `true && []` raises 'Operands to the || and && operators must be convertible to logical scalar values.' This fires exactly in the no-significant-results case the plotting block was written to handle. The primary caller (limo_stat_values) always passes plotFlag=true so it is shielded, but the documented 7-argument API crashes.
- **Category:** `control-flow`

#### 220. `limo_combine_catvalues.m:40` — ⚪ LOW · CONFIRMED

**In the interactive (nargin==0) branch, `load(filename)` uses the bare file name rather than the full path, so loading fails when the chosen file is not in the current directory.**

- **Why:** `uigetfile` returns `filename` and `pathname` separately. The code correctly stores `varargin{1} = fullfile(pathname, filename)` for later use, but then loads with `load(filename)` (line 40), ignoring `pathname`. If the user selects a file outside the MATLAB current folder/path, `load` errors or, worse, silently loads a same-named file from elsewhere on the path.
- **Category:** `data handling`

#### 221. `limo_contrast.m:162` — ⚪ LOW · CONFIRMED

**When no stored contrast matches the input (type 2 explicit contrast), find() returns empty, so the `contrast_nb == 0` guard evaluates to [] (false) and the code proceeds to index LIMO.contrast{[]}, crashing instead of returning gracefully.**

- **Why:** If none of the stored contrasts match varargin{6}, `test` is all zeros and `find(test)` returns []. `contrast_nb = []`. The subsequent guard `if contrast_nb == 0` computes `[] == 0` = `[]`, which `if` treats as false, so the warning/return at lines 165-168 is skipped. Execution reaches line 177 `C = LIMO.contrast{contrast_nb}.C` with an empty index, throwing an error rather than the intended graceful abort.
- **Category:** `control flow`

#### 222. `limo_contrast.m:165` — ⚪ LOW · CONFIRMED

**When no stored contrast matches the requested one, find returns [] not 0, so the empty-guard is skipped and the code crashes on LIMO.contrast{[]}.**

- **Why:** For analysis_type=2 with nargin==6, lines 155-162 build a logical vector test and do [~,contrast_nb]=find(test). If nothing matches, test is all zeros and find returns empty, so contrast_nb=[]. Line 165's if contrast_nb==0 evaluates []==0 -> [] -> false, so the intended warning+return is skipped and execution reaches line 177 C=LIMO.contrast{contrast_nb}.C, i.e. LIMO.contrast{[]}, which errors.
- **Category:** `logic`

#### 223. `limo_contrast.m:595` — ⚪ LOW · CONFIRMED

**The bootstrap F-contrast p-value uses rank(c)-1 as numerator df while the F statistic is scaled by a clamped df, so a rank-1 contrast yields a df of 0 and NaN p-values inconsistent with the computed F.**

- **Why:** Lines 590-595 set df = rank(c)-1 then clamp df=1 when df==0, and compute the F value with the clamped df. But the p-value at line 595 calls fcdf(F, rank(c)-1, dfe(channel)) with the UNCLAMPED rank(c)-1. When the F-contrast has rank 1 (a single-parameter contrast entered as F), rank(c)-1=0, so fcdf uses 0 numerator df and returns NaN, while the F value itself was computed with numerator df 1. The IRLS branch at line 655 has the same inconsistency (df clamped for F, rank(c)-1 for the p-value). The observed-data path (lines 304-320) consistently uses the clamped df for both F and p.
- **Category:** `wrong-df/error-term`

#### 224. `limo_contrast.m:679` — ⚪ LOW · CONFIRMED · R2-new

**The multivariate bootstrap loop iterates `for e = 1:size(Y,1)` but indexes `channel = array(e)`, where array (line 529) only holds the non-NaN channels; when any channel is empty, array is shorter than size(Y,1) and array(e) indexes out of bounds.**

- **Why:** array = find(~isnan(Y(:,1,1))) at line 529 excludes all-NaN channels. The mass-univariate loop correctly uses `for e = 1:length(array)` (line 535), but the multivariate loop at line 679 uses `for e = 1:size(Y,1)` while still doing channel = array(e) at line 680. If length(array) < size(Y,1) (any empty channel), array(e) throws 'Index exceeds the number of array elements' once e passes length(array).
- **Category:** `indexing-error`

#### 225. `limo_contrast.m:868` — ⚪ LOW · CONFIRMED · R2-new

**Case 3 saves the observed ess file with a subname prefix (`save([subname filename], ...)`, line 853) but the TFCE calls at lines 867-868 (and 871-872) pass filename WITHOUT the subname, so when subname is non-empty limo_tfce_handling receives a path to a file that does not exist.**

- **Why:** Line 849 builds filename = 'ess_%g.mat' (no subname) and line 853 saves it as [subname filename]. The TFCE block at 867-868 checks fullfile(LIMO.dir,['tfce' filesep 'tfce_' filename]) and calls limo_tfce_handling(fullfile(LIMO.dir,filename)) — both omit subname. The same mismatch applies to filename2 at 871-872. With a non-empty subname the saved file is subname+ess_N.mat while TFCE is asked to process ess_N.mat, so the file is missing.
- **Category:** `save-load-mismatch`

#### 226. `limo_contrast_checking.m:92` — ⚪ LOW · CONFIRMED

**After `LIMO = LIMO.LIMO`, the code writes `LIMO.LIMO.contrast{end}.C`, creating a bogus nested field and never updating the real contrast before saving LIMO.mat.**

- **Why:** In the nargin==1 branch: line 44 loads into `LIMO` (a struct whose only field is `LIMO`). Line 91 reassigns `LIMO = LIMO.LIMO`, so `LIMO` is now the actual design struct with fields design/contrast/dir. Line 92 then assigns `LIMO.LIMO.contrast{end}.C = C`, which creates a NEW spurious nested field `LIMO.LIMO` instead of updating `LIMO.contrast{end}.C`. Line 93 saves variable 'LIMO'. The result: the genuine `LIMO.contrast{end}.C` still holds the OLD (unpadded) contrast, and a garbage `LIMO.LIMO.contrast` field is written. The whole point of this branch (padding the last contrast with zeros for the constant term and persisting it) silently fails, and the saved LIMO.mat is polluted with a nested LIMO field.
- **Category:** `data handling`

#### 227. `limo_create_files.m:20` — ⚪ LOW · CONFIRMED · R2-new

**The GUI branch ignores the user-selected file and hard-codes `load LIMO.mat`, so a differently named selection loads the wrong file or errors.**

- **Why:** uigetfile at line 19 returns the chosen filename in `file` and its folder in `dir`. Line 20 then does `cd(dir); load LIMO.mat;` which literally loads a file named 'LIMO.mat' from the directory, completely disregarding the `file` variable the user picked. If the user selects any .mat file not named exactly 'LIMO.mat' (the dialog filter permits navigating/selecting other names), the code either loads a stale LIMO.mat that happens to be in that folder or throws 'Unable to read file LIMO.mat'. The `file` output is never used.
- **Category:** `wrong-filename`

#### 228. `limo_create_files.m:49` — ⚪ LOW · CONFIRMED · R2-new

**In the programmatic (varargin) calling path, X is never defined, so the raw branch (line 49) and modeled branch (line 63) reference an undefined X.**

- **Why:** X is only assigned in the GUI branch at line 20 (`X = LIMO.design.X`). The else branch (line 32-39) does `load(varargin{1})` which loads the LIMO struct but never creates X. Later, raw processing at line 49 uses `squeeze(X(:,i))` and modeled processing at line 63 uses `size(X,2)` — both would error 'Undefined variable X' when the function is invoked programmatically as documented (`limo_creates_files(File,parameters,type)`). This is currently masked by the already-reported tautology at line 36 (which always throws first), but it is a distinct latent defect: fixing the tautology exposes the crash.
- **Category:** `used-before-defined`

#### 229. `limo_create_single_trials.m:78` — ⚪ LOW · CONFIRMED

**`isfield(options,'itc')` / `isfield(options,'ersp')` are tested on `options`, which is the raw `varargin` cell array, so they are always false and the itc/ersp consistency logic never runs.**

- **Why:** `options = varargin` (line 55) is a cell array, not a struct. `isfield` on a non-struct returns false, so the conditions on lines 78 and 82 are never true. The intent was to inspect the parsed `opt` struct (checking whether the caller passed 'itc' and/or 'ersp' as key/value pairs). Because the checks always fail, the block that forces `opt.itc = opt.ersp` for consistency, and the block that sets `opt.itc = 'off'` when ersp is given without itc, are both dead code. Consequently `opt.itc` keeps its default of 'on' (line 70) regardless of the caller's ersp settings, so ITC is computed even when it should be suppressed.
- **Category:** `logic`

#### 230. `limo_create_single_trials.m:189` — ⚪ LOW · CONFIRMED

**For ICA data in matrix format the datafiles pointer is stored under `datafiles.daterp` (and `datafiles.datitc` at line 231) instead of the component field names used in the non-matrix branches.**

- **Why:** In the ICA/components block, the matrix-format branches write `ALLEEG.etc.datafiles.daterp` (line 189) and `ALLEEG.etc.datafiles.datitc` (line 231), while the corresponding non-matrix branches use `datafiles.icaerp` (line 192) and `datafiles.icaitc` (line 234). Downstream code that looks up the ICA data file under `etc.datafiles.icaerp`/`icaitc` will not find it (or will collide with channel-data field names) when matrix format is used for components. This is a copy-paste inconsistency between the channels and ica code paths.
- **Category:** `wrong-field`

#### 231. `limo_design_matrix_tf.m:158` — ⚪ LOW · CONFIRMED · R2-new

**The TF NaN-trial removal marks a trial for removal if ANY categorical column is NaN, whereas the non-TF limo_design_matrix removes a trial only when ALL columns are NaN, silently dropping trials in multi-factor TF designs.**

- **Why:** Line 158: `check = find(sum(isnan(Cat),2));` flags any row whose columns sum to a nonzero NaN count, i.e. any row with at least one NaN. The equivalent line in limo_design_matrix.m (line 129) is `check = find(sum(isnan(Cat),2)==size(Cat,2));`, which flags only rows where every column is NaN (the documented 'mark a trial for removal' convention). For a multi-column (N-way factorial) Cat where a single factor column is NaN on a valid trial, the TF path removes that trial from both Cat and Y while the standard path keeps it, producing a different (smaller) design than the time/frequency pipeline for identical inputs.
- **Category:** `nan-handling`

#### 232. `limo_display_image.m:106` — ⚪ LOW · CONFIRMED

**Frame spacing is computed with the number of samples instead of the number of intervals (N-1), biasing the click-to-frame mapping used for the interactive topoplot.**

- **Why:** The per-frame step should be range/(length-1), not range/length. Because frame = frame_zeros + round(x/ratio) uses this ratio, the selected frame drifts increasingly from the true frame as x grows, and frame_zeros itself (round(|start|/ratio)+1) is biased. The bounds clamp (line 371) prevents a crash here, but the wrong frame's topography/stat can be displayed near the ends. The same pattern recurs at lines 154 (TF) and 130 (Frequency).
- **Category:** `numerics-off-by-one`

#### 233. `limo_display_results.m:1975` — ⚪ LOW · CONFIRMED

**In the Frequency branch of the repeated-measures x-axis setup, the code checks for the field 'timevect' but then assigns from LIMO.data.freqlist, so a stored timevect with no freqlist raises an error.**

- **Why:** Lines 1974-1980 handle LIMO.Analysis=='Frequency' but guard with `isfield(LIMO.data,'timevect')` (copied from the Time branch at 1968) while the body reads `xvect = LIMO.data.freqlist`. If LIMO.data has a timevect field but no freqlist field, the true-branch executes and `LIMO.data.freqlist` errors; conversely the else-branch (which builds freqlist) is only taken when timevect is absent, which is the wrong condition.
- **Category:** `data-handling`

#### 234. `limo_ecluster_make.m:92` — ⚪ LOW · CONFIRMED

**The 2D branch calls bwlabeln unconditionally with no spm_bwlabel fallback, so single-channel clustering crashes for users who have SPM but not the Image Processing Toolbox, even though the 3D branch (and the function's own errordlg text) support SPM.**

- **Why:** The 3D branch (lines 57-64) checks `exist('spm_bwlabel','file')` first and falls back to bwlabeln, erroring only if neither exists. The 2D branch (line 92) skips that logic and calls bwlabeln directly. LIMO commonly runs alongside SPM without the IPT; for such installs, multi-channel/time-frequency clustering works but single-channel (2D) clustering throws 'Undefined function bwlabeln'.
- **Category:** `control-flow/robustness`

#### 235. `limo_ecluster_test.m:108` — ⚪ LOW · CONFIRMED · R2-new

**When boot_maxclustersum is empty (the documented 4-argument call), the elec-branch p-value computation divides by length([])==0, yielding NaN p-values for significant clusters instead of a real p-value.**

- **Why:** boot_maxclustersum defaults to [] at lines 45-47 when the function is called with 4 args (as done in limo_mstat_values.m:313 and :321). In the elec branch, for a significant cluster line 108 computes p = 1 - sum(maxval(C) >= boot_maxclustersum)./length(boot_maxclustersum). With boot_maxclustersum==[], sum(scalar>=[]) is 0 and length([]) is 0, so 0/0 = NaN and p = NaN. The guard `if p==0` at line 109 is false for NaN, so pval(channel,L==C) is set to NaN. The returned per-cluster p-values are therefore NaN whenever the null distribution was not supplied, rather than a defined value or an error. Current callers that omit boot_maxclustersum happen to discard pval, which is why this is low severity, but any caller that requests pval on the 4-arg path receives silent NaNs.
- **Category:** `empty-mishandling`

#### 236. `limo_eeg.m:405` — ⚪ LOW · CONFIRMED

**The interactive LIMO.mat selection in case 4 compares the returned filename to 'LIMO' (no extension), so a valid selection is rejected.**

- **Why:** uigetfile returns the filename with its extension, so selecting the file yields file='LIMO.mat'. strcmpi('LIMO.mat','LIMO') is false, so the code takes the else branch and calls error('not a LIMO.mat file') even though the user selected a valid file.
- **Category:** `control-flow`

#### 237. `limo_eeg.m:722` — ⚪ LOW · CONFIRMED

**Loop bound uses size(...,2) on a dir() column struct array, so only the first semi-partial-coef file is ever displayed.**

- **Why:** dir() returns an N-by-1 struct array, so size(check_semi,2) is always 1 regardless of how many files matched. The analogous loop at line 742 correctly uses size(check_test,1). As written, when multiple semi_partial_coef_*.mat files exist, only semi_partial_coef_1.mat is processed.
- **Category:** `indexing`

#### 238. `limo_eeg.m:833` — ⚪ LOW · CONFIRMED

**Multivariate contrast result is stored at index i instead of previous_con+i, overwriting an earlier contrast slot.**

- **Why:** Line 820 correctly stores the contrast at LIMO.contrast{previous_con+i}, but line 833 writes the multivariate result to LIMO.contrast{i}. When previous_con > 0 these indices disagree, so the multivariate field is attached to the wrong (already-existing) contrast entry rather than the one just created.
- **Category:** `indexing`

#### 239. `limo_eeg_tf.m:300` — ⚪ LOW · CONFIRMED

**H0 conditions array is preallocated using length(nb_continuous) for its factor dimension instead of length(nb_conditions).**

- **Why:** Inside `if LIMO.design.nb_conditions ~= 0`, tmp_H0_Conditions is preallocated at line 300 with dim3 = length(LIMO.design.nb_continuous), but this array holds condition effects and should use length(LIMO.design.nb_conditions) (as the observed-data counterpart does at line 83). Because nb_continuous is a scalar count, length()==1, so dim3 is preallocated as 1; the later assignment loop (lines 342-345) that indexes i=1:length(nb_conditions) auto-grows the array, so the final result is usually numerically correct but the preallocation is wrong and fragile.
- **Category:** `indexing/copy-paste`

#### 240. `limo_expected_chanlocs.m:145` — ⚪ LOW · CONFIRMED

**The 'file not found' error message dereferences FileName{f}, but FileName is empty ([]) in this branch, causing a cell-index crash instead of the intended message.**

- **Why:** In the Set branch (reached with nargin==0), FileName was set to [] at line 50. The loop at line 143 validates files via ~exist(name{f},'file'); on a missing file it calls errordlg(sprintf('%s \n file not found',FileName{f})). FileName is a double ([]), so FileName{f} raises 'Cell contents reference from a non-cell array object' rather than displaying the intended dialog.
- **Category:** `data-handling`

#### 241. `limo_glm.m:599` — ⚪ LOW · CONFIRMED

**The WLS-TF HC4 betas_se line contains invalid syntax/wrong indexing and crashes whenever the HC4 variance option is used.**

- **Why:** Line 599 reads model.betas_se(:,freq,t) = diag((pinv(WX{freq}'*WX{freq}))*WX'*diag(HC4(:,t))*WX{freq}*(pinv({freq}'*{freq})));. Here WX is a cell array in the WLS-TF branch, so 'WX''' transposes a cell (error), and '{freq}''*{freq}' is not valid MATLAB (a brace-index expression with no variable), which is either a parse-time or run-time error. It should reference WX{freq} in all positions, e.g. pinv(WX{freq}'*WX{freq}). Any call using the undocumented HC4 variance estimator with Time-Frequency WLS crashes.
- **Category:** `syntax-crash`

#### 242. `limo_glm_boot.m:706` — ⚪ LOW · CONFIRMED

**In the IRLS 2-factor interaction quick-path the interaction df uses prod(df_conditions(frame)) which linear-indexes a single element instead of multiplying the two factors' df at that frame.**

- **Why:** df_conditions in glm_iterate is a [nb_factors x frames] matrix (filled at line 686 as df_conditions(f,frame)). Line 706 computes df_interactions(frame) = prod(df_conditions(frame)); using linear indexing, so df_conditions(frame) returns a single element (column-major position `frame`), and prod of a scalar is that scalar rather than df1*df2. The intended value is prod(df_conditions(:,frame)). For any design where a factor has more than two levels (df>1) this mis-scales the interaction F (line 707) and gives a wrong parametric df to fcdf (line 708). Note the same defect exists in limo_glm.m line 1110, so the bootstrap max-stat threshold is partially self-consistent, but the reported F magnitude, df, and any parametric/FDR output are wrong.
- **Category:** `wrong-df`

#### 243. `limo_glm_handling.m:449` — ⚪ LOW · CONFIRMED

**H0 conditions array is preallocated using length(nb_continuous) instead of length(nb_conditions), mis-sizing the factor dimension.**

- **Why:** Both `tmp_H0_Conditions` preallocations use `length(LIMO.design.nb_continuous)` for the factor dimension (line 449 non-TF, line 437 Time-Frequency), but the loops that fill them (lines 551-553 and 595-597) index that dimension up to `length(LIMO.design.nb_conditions)`. nb_continuous is a scalar count so its length is always 1, whereas nb_conditions is a vector of factor levels whose length is the number of categorical factors. The correct sizing is clearly `length(LIMO.design.nb_conditions)` (as used at line 448 for the observed effects and at lines 452/440 for interactions). MATLAB auto-grows the array on assignment so processed channels end up correct, but auto-grown planes are zero-filled rather than NaN, so bad/skipped channels (which are never assigned) get F=0/p=0 in factor slices >=2 instead of NaN for multi-factor designs.
- **Category:** `indexing/preallocation-copy-paste`

#### 244. `limo_glm_handling.m:796` — ⚪ LOW · CONFIRMED · R2-new

**limo_error() is called but no such function exists in the toolbox, so the intended 'no neighbouring matrix' error path throws an 'Undefined function' error instead.**

- **Why:** Line 796 calls limo_error('no neighbouring matrix returned, ...') when limo_expected_chanlocs returns an empty neighbouring matrix. There is no limo_error.m anywhere in the toolbox (only limo_errordlg.m, limo_warndlg.m, limo_questdlg.m exist), and no local/nested definition; grep for 'function ... limo_error' finds none. The same non-existent limo_error is also referenced in limo_central_tendency_and_ci.m, limo_display_results.m and limo_random_select.m, confirming it is genuinely missing rather than a local helper. When reached, MATLAB raises 'Undefined function or variable limo_error' rather than the intended descriptive error, and the descriptive message is lost.
- **Category:** `undefined-function`

#### 245. `limo_gui.m:61` — ⚪ LOW · CONFIRMED

**analyse_Callback opens a redundant first file dialog whose result (dir_path) is later used in cd(dir_path); cancelling it makes dir_path=0 and cd(0) crashes.**

- **Why:** Line 61 pops a uigetfile whose outputs `file` is unused and `dir_path` is only consumed at line 82 (cd(dir_path)). The actual file selection is done by the separate limo_get_files call on line 62. If the user cancels the first (vestigial) dialog, uigetfile returns 0 for both outputs; after processing, line 82 executes cd(dir_path) with dir_path==0, which errors. The first dialog is also confusing/redundant UX that can point cd at a different folder than the selected LIMO files.
- **Category:** `control-flow`

#### 246. `limo_ipsi_contra.m:32` — ⚪ LOW · CONFIRMED

**data_dir for the second con list is written into index {1}, overwriting the first list's dir and leaving data_dir{2} unset.**

- **Why:** Line 30 sets `LIMO.data.data_dir{1} = Paths{1}` and line 31 loads the second file list into `LIMO.data.data{2}`, but line 32 assigns `LIMO.data.data_dir{1} = Paths{2}` (index 1 again) instead of `{2}`. This clobbers the first condition's directory record and never records the second's. Any consumer that relies on LIMO.data.data_dir to locate the two condition file sets (provenance, re-loading) gets the wrong/incomplete mapping.
- **Category:** `data-handling/copy-paste`

#### 247. `limo_ipsi_contra.m:88` — ⚪ LOW · CONFIRMED

**Char arrays are compared with ~= (elementwise) instead of strcmp, which errors on differing-length Type strings and never aborts on a real mismatch.**

- **Why:** `tmp.LIMO.Type` and `LIMO.Type` are character arrays ('Channels', 'Components', etc.). `~=` does elementwise comparison requiring equal length; if a subject's Type has a different length (e.g. 'Components' vs 'Channels') MATLAB throws 'Matrix dimensions must agree'. Even when lengths match, the intended guard shows `limo_errordlg` but does not `return`/abort, so processing continues with mismatched data. Should use `~strcmpi(tmp.LIMO.Type,LIMO.Type)` plus a return.
- **Category:** `control-flow/char-compare`

#### 248. `limo_match_frames.m:108` — ⚪ LOW · CONFIRMED

**max/min over first_frame/last_frame omit an explicit dimension, so a single-subject Time-Frequency run reduces across the wrong axis and crashes.**

- **Why:** For Time-Frequency analysis first_frame and last_frame are built as n-by-2 matrices (column 1 = time trim, column 2 = frequency trim). `[v,c] = max(first_frame)` (line 108) and `[v,c] = min(last_frame)` (line 133) rely on the default reduction being along dim 1 (over subjects), which holds only while n>1. If n==1 the matrix is 1-by-2 and MATLAB's default first-non-singleton reduction collapses across the two columns instead, returning scalars v and c. The subsequent references v(2), start(c(2),2) (lines 113) and v(2), stop(c(2),2) (line 138) then index past the end of a scalar and error, and even before erroring the time-vs-frequency separation is lost. The code silently depends on n>1 rather than pinning the axis.
- **Category:** `indexing-dimension`

#### 249. `limo_max_correction.m:73` — ⚪ LOW · CONFIRMED

**When called with 2 or 3 arguments fig defaults to [], and if there are no significant results the '&& fig == 1' evaluates '[]==1' as a non-scalar operand to &&, throwing an error.**

- **Why:** For nargin==2 or nargin==3, fig is set to []. At line 73, if sum(mask(:))==0 is true (no significant cells), MATLAB then evaluates the right operand fig==1, which is []==1 = [] (empty). The && operator requires a scalar-logical operand and errors: 'Operands to the || and && operators must be convertible to logical scalar values.' So a legitimate 3-argument call that yields no significant results crashes instead of returning cleanly. (Internal caller limo_stat_values always passes 4 args, so this bites direct API users per the documented 3-arg FORMAT.)
- **Category:** `control flow/crash`

#### 250. `limo_mglm.m:112` — ⚪ LOW · CONFIRMED

**User-supplied weights are captured with () instead of {}, wrapping W in a 1x1 cell so it is never usable as a numeric matrix.**

- **Why:** `W = varargin(7);` returns a 1x1 cell containing the weight matrix, not the matrix itself (should be `varargin{7}`). Downstream, isempty(W) is false so the WLS path takes the provided-weights branch (which is itself broken via WX/WY), and any numeric use of W would fail or misbehave because W is a cell.
- **Category:** `cell-indexing`

#### 251. `limo_mglm.m:267` — ⚪ LOW · CONFIRMED

**The discriminant-feasibility guard uses length(Y) (max dimension) instead of the number of observations size(Y,1), misfiring when there are more electrodes than trials.**

- **Why:** Line 267 `if length(Y)-nb_conditions <= nb_conditions` is meant to test whether there are enough observations relative to conditions. `length(Y)` returns max(size(Y)); for Y = trials x electrodes it equals the number of electrodes when electrodes > trials, so the guard checks the wrong count and can either wrongly allow or wrongly block the discriminant analysis.
- **Category:** `dimension`

#### 252. `limo_mglm.m:847` — ⚪ LOW · CONFIRMED · R2-new

**Continuous-covariate loop indexes Eigen_values_continuous by covariate number (:,n), but each iteration holds only one decomposition**

- **Why:** Inside the per-covariate loop (827-856), `Eigen_values_continuous` is recomputed each iteration for covariate n's rank-1 hypothesis (line 835). The code then reads `Eigen_values_continuous(:,n)` at lines 847, 848 and 852, i.e. it indexes the n-th COLUMN as though the variable held one column per covariate. It never does: it is a single decomposition. Currently this is masked only because limo_decomp's first (mis-captured) output is a p-by-p eigenvector matrix, so column n happens to exist for n<=p — but then max(...) is taken over an eigenvector component, which is statistically meaningless. If the eigenvalue-capture bug were fixed to return the p-by-1 eigenvalue vector, `(:,n)` would throw an index-out-of-bounds error for the 2nd and later covariates.
- **Category:** `indexing-dimension`

#### 253. `limo_mstat_values.m:120` — ⚪ LOW · CONFIRMED

**For multivariate results, all correction branches (cluster/max/TFCE) are empty, so the function returns M as raw F-values (not p-values) with an empty mask and no title instead of a corrected result.**

- **Why:** In every FileName branch (R2 lines 120-131, Condition_effect lines 194-205, Covariate_effect lines 265-276) the MCC==2/3, MCC==4 and MCC==5 cases contain only comments and no code. M was set to F-values at the top of the branch (e.g. line 69/71) and is never converted to p-values, mask stays [] (initialised line 50) and mytitle stays []. The subfunctions local_clustering and max_correction defined at lines 284/327 are never called (dead code). limo_display_results calls this with MCC>1 (lines 385/424/544), so any request for clustering/max/TFCE on a multivariate effect silently returns unthresholded F-values labelled as the statistic map with an empty mask, rather than a corrected result or an error.
- **Category:** `logic`

#### 254. `limo_pair_channels.m:47` — ⚪ LOW · CONFIRMED

**The input-shape guard `if size(inputlabels) ~= [1 2]` fails to reject many malformed shapes because `if` requires all elements true.**

- **Why:** size(inputlabels) returns a 1x2 vector; comparing element-wise with [1 2] yields a 1x2 logical, and `if` fires only when BOTH elements are non-zero. For an input of size [1 3] the comparison is [0 1] (not all true) so no error is raised, and for [n 2] it is [1 0] -> no error. Malformed inputs slip through and downstream inputlabels{1}/inputlabels{2} misbehave silently.
- **Category:** `control-flow`

#### 255. `limo_prederror.m:63` — ⚪ LOW · CONFIRMED · R2-new

**The first (shuffled) observation is never placed in any test fold, so k-fold CV never evaluates prediction error on all data.**

- **Why:** foldindex = 1:Nfold:N with foldindex(1)=1, and testindex for each fold is `foldindex(fold)+1:foldindex(fold+1)` (line 63). The union of test indices over folds 1..k is therefore foldindex(1)+1 : foldindex(k+1) = 2:N. Observation 1 is excluded from every test set and always sits in the training set, biasing the cross-validation slightly and making it not a true partition of the data. The fold boundaries should start at 0 (e.g. foldindex = 0:Nfold:N) so the first fold's test set is 1:foldindex(2).
- **Category:** `indexing/off-by-one`

#### 256. `limo_random_effect.m:139` — ⚪ LOW · CONFIRMED · R2-new

**bootstrap_Callback checks isempty(handles.b) after str2double, but str2double never returns empty (it returns NaN), so bad/blank input propagates NaN as the bootstrap count.**

- **Why:** Line 138 sets handles.b = str2double(get(hObject,'String')). str2double returns a scalar NaN for an empty or non-numeric string, never []. Thus `if isempty(handles.b)` at line 139 is always false and can never reset handles.b to 0. The elseif `handles.b == 0` is also false for NaN (NaN==0 is false), and the guard at line 146 `if handles.b > 0 && handles.b < 1000` is false for NaN, so a blank/invalid entry leaves handles.b = NaN, which is then passed as 'nboot' to limo_random_select.
- **Category:** `nan-empty-mishandling`

#### 257. `limo_random_effect.m:148` — ⚪ LOW · CONFIRMED

**bootstrap_Callback calls num2bouble(handles.b), an undefined function (typo for num2str), crashing whenever the user enters a bootstrap count between 1 and 999 other than 101.**

- **Why:** Inside bootstrap_Callback, when 0 < handles.b < 1000 and handles.b ~= 101, the warning message concatenates `num2bouble(handles.b)`. There is no num2bouble function anywhere in the toolbox (verified). MATLAB will throw 'Undefined function num2bouble' and the callback aborts, so the intended warning never displays and the GUI errors on an otherwise valid (if discouraged) input.
- **Category:** `control-flow-typo`

#### 258. `limo_random_robust.m:1052` — ⚪ LOW · CONFIRMED · R2-new

**The 'already computed, skip recompute' guard tests a filename pattern that never matches the names the code actually writes, so the skip branch is dead and the analysis always recomputes and overwrites existing results.**

- **Why:** Line 1052 guards the whole rep-measures computation with `if isempty(dir('Rep_ANOVA_Factor*.mat'))`. But the files this branch actually saves are named 'Rep_ANOVA_Main_effect_%g...' and 'Rep_ANOVA_Interaction_Factors_%s...' (lines 1158-1165), never 'Rep_ANOVA_Factor*'. Therefore `dir('Rep_ANOVA_Factor*.mat')` is always empty and the guard is always true, so the intended 'skip if results already exist' behavior is silently disabled and every invocation recomputes and overwrites the previous results. (Note: because the guard never skips, `Rep_filenames`/`IRep_filenames` are always defined before the later bootstrap/TFCE loops, so it doesn't crash — but the intended skip semantics are dead.)
- **Category:** `dead-code / disabled-behavior`

#### 259. `limo_random_robust.m:1442` — ⚪ LOW · CONFIRMED

**In the repeated-measures TFCE branch, `save(fullfile(LIMO.dir,'LIMO.mat'))` with no variable list writes the entire workspace into LIMO.mat instead of just LIMO.**

- **Why:** Every other save of LIMO in this file specifies the variable: `save(...,'LIMO')`. Line 1442 omits it, so MATLAB serializes all in-scope workspace variables (including the large arrays `data`, `centered_data`, `tmp_boot_H0_Rep_ANOVA`, `boot_table`, etc.) into LIMO.mat. LIMO itself is still present so loads that pull the LIMO field keep working, but the file can balloon to many GB and carries stale variables, and only runs when tfce is enabled. This is a genuine defect (unintended file contents / size), though it does not by itself corrupt the statistics.
- **Category:** `data-handling`

#### 260. `limo_random_select.m:318` — ⚪ LOW · CONFIRMED

**`if ~skip_design_check` negates a char array, so the NaN-regressor warning branch is effectively dead.**

- **Why:** skip_design_check is a char string ('No' by default, or 'Yes'). `~'No'` evaluates element-wise on the character codes to [0 0], which `if` treats as false; `~'Yes'` is likewise all-false. So the intended 'not skipping the design check -> show a warndlg' path at lines 319-321 is never taken and the code always drops to the else (line 323). Only the user-facing message differs, but the guard does not express the intended condition.
- **Category:** `logic`

#### 261. `limo_random_select.m:1193` — ⚪ LOW · CONFIRMED

**The guard meant to reject groups with differing numbers of repeated-measures factors is logically broken and can never fire, silently accepting inconsistent parameter specifications across groups.**

- **Why:** Line 1193: `if ~cellfun(@(x) length(x)==length(LIMO.design.parameters{1}),LIMO.design.parameters)` applies elementwise `~` to a logical array and then relies on `if` treating the whole array as true only when ALL elements are nonzero. Since the first cell always equals itself (length==length -> 1 -> ~1 -> 0), the array always contains a 0, so `if` is always false and the intended `error('parameters input sizes different between groups...')` never executes. Mismatched factor counts across groups therefore pass through, and `factor_nb = factor_nb{1}` (line 1196) is used, which can mis-shape later reshaping. The intended test is `if ~all(cellfun(...))` (or `any(~cellfun(...))`).
- **Category:** `logic`

#### 262. `limo_random_select.m:2001` — ⚪ LOW · CONFIRMED · R2-new

**The Components dimension-mismatch handler references an undefined variable `expected_chanlocs` and compares an MException to a string, so the diagnostic path itself errors and never prints.**

- **Why:** Inside getdata's catch (lines 1998-2005): line 1999 `if strcmp(dim_error,'Subscripted assignment dimension mismatch.')` compares the MException object dim_error to a char (always false, so the message never shows); it should be `dim_error.message` or `dim_error.identifier`. Line 2001 `if isempty(expected_chanlocs)` references a variable that does not exist in getdata's scope (its args are stattest,analysis_type,first_frame,last_frame,subj_chanlocs,LIMO), so reaching it throws 'Undefined function or variable expected_chanlocs', masking the real component-size error.
- **Category:** `undefined-variable`

#### 263. `limo_read_events.m:51` — ⚪ LOW · CONFIRMED · R2-new

**The function never creates or saves the cat.mat file its documentation promises to write.**

- **Why:** The header states the OUTPUT '<empty> will create and save a cat.mat file that can be used at import'. The code builds the `cat` vector (lines 51-68) and returns it, but there is no `save('cat.mat','cat')` anywhere, and `storein` (the intended save location, computed at lines 30/33) is never used. So the documented side effect of writing cat.mat to the .set's directory never happens; only the return value is produced.
- **Category:** `missing-save`

#### 264. `limo_rep_anova_old.m:413` — ⚪ LOW · CONFIRMED · R2-new

**Between-group indicator matrix Gp assigns rows non-cumulatively, so for designs with 3 or more groups the group membership matrix is corrupted.**

- **Why:** In both case 3 (lines 407-415) and case 4 (lines 589-597) the loop building the group design matrix does `index2 = nb_items(index1) + 1;` after filling `Gp(index2:index2+nb_items(index1)-1,i)=1`. `index2` is reset to `nb_items(current_group)+1` rather than advanced cumulatively (should be `index2 = index2 + nb_items(index1)`). For group 1 and group 2 the offsets happen to be correct, but from group 3 onward the starting row is wrong: group 3's indicator is written into the same rows previously used by group 2, and the true group-3 subject rows are never marked. The corrupted Gp then propagates into X, the SS_Gp / SS_XGp / SS error terms, and every F/p in results. This only manifests with 3+ between-subject groups (2-group designs are unaffected because index2 for group 2 = nb_items(1)+1 is coincidentally correct).
- **Category:** `indexing-error`

#### 265. `limo_rep_anova_old.m:481` — ⚪ LOW · CONFIRMED

**The group x factor interaction p-value is computed with the factor's numerator df instead of the interaction df, giving wrong p-values whenever there are more than two groups.**

- **Why:** In case 3 (Gp * single repeated factor) the interaction F is correctly formed on line 480 using df_interaction = df*df_gp = (k-1)(g-1): `F_values(:,3) = (SS_XGp./(EpsHF{1}*df_interaction)) ./ (SS_E./(EpsHF{1}*dfe))`. But line 481 evaluates its tail probability with the WRONG numerator df: `1 - fcdf(F_values(:,3), EpsHF{1}*df, ...)`, where df = nb_conditions-1 = (k-1), not df_interaction. The numerator df of an F test must match the df used to scale its numerator sum of squares. This is confirmed as a genuine inconsistency by the analogous case 4 code (line 730), which correctly uses `EpsHF{frame}(e)*df*df_gp` for the Gp-interaction numerator df. When g=2 (df_gp=1) df_interaction==df so the bug is masked; with 3+ groups it produces incorrect p-values (the fcdf is evaluated against an F distribution with too few numerator df), silently mis-computing the significance of the group-by-condition interaction.
- **Category:** `wrong-df-pvalue`

#### 266. `limo_robust_ci.m:209` — ⚪ LOW · CONFIRMED

**Gathered data is indexed by the raw parameter value `j` rather than a sequential counter, so non-contiguous `parameters` leave all-NaN condition slices that are then estimated and saved.**

- **Why:** In the 6-arg/GUI path the loop `for j=parameters` stores results in `data(:,:,j,i)` using j (a condition number) as the 3rd-dimension index. If parameters is non-contiguous or does not start at 1 (e.g. [2 4]), the intermediate slices (index 1, 3) are never assigned and remain NaN (or 0), yet the Analysis section loops `k=1:size(data,3)` over all slices and computes/saves estimators for those empty slices, producing spurious NaN 'conditions' in TM/HD/Med outputs.
- **Category:** `indexing`

#### 267. `limo_stat_values.m:179` — ⚪ LOW · CONFIRMED · R2-new

**Time-Frequency titles use %g with a char effect number, printing ASCII codes instead of the effect index**

- **Why:** In the Time-Frequency branch, effect_nb comes from extractAfter(FileName,...) and is a char (e.g. '1'). Lines 169 (`Semi Partial Coef %g`), 179 (`Contrast %g T values`) and 197 (`Contrast %g F values`) pass this char to a %g conversion. sprintf('%g','1') prints the numeric char code (49), not '1', and for multi-digit ids (char '10' = [49 48]) sprintf recycles the format producing 'Contrast 49 ... Contrast 48 ...'. The non-Time-Frequency branch correctly uses %s at the analogous lines 249/259/277, confirming %g is a mistake.
- **Category:** `format-string`

#### 268. `limo_stat_values.m:185` — ⚪ LOW · CONFIRMED · R2-new

**t-test title name extraction uses lowercase 'ttest' in strfind, which never matches capital 'Ttest' filenames, yielding an empty title prefix**

- **Why:** Lines 185 and 265 build the display name with `name = FileName(1:strfind(FileName,'ttest')+4)`. Real t-test filenames contain capital 'Ttest' (limo_random_robust.m), so the case-sensitive strfind returns [], making `1:([]+4)` an empty range and `name` an empty char. The resulting title is just ' t-test T values' with the test description dropped (and LI_Map files, which contain no 'ttest' at all, are likewise left blank).
- **Category:** `string-handling`

#### 269. `limo_tfce.m:66` — ⚪ LOW · CONFIRMED

**The nargin dispatch has no branch for nargin equal to 5, 6, or 8, leaving E, H, dh (and updatebar) undefined so the function errors on first use of those variables.**

- **Why:** The input-check block handles nargin<3 (error), nargin==3||4 (defaults), nargin==7 (full args), and nargin>8 (error). nargin of 5, 6, or exactly 8 fall through all branches, so updatebar/E/H/dh are never assigned. The first later reference (e.g. updatebar at line 118, or E at line 131) then errors with 'Undefined function or variable'. The intended contract from the header is either 3-4 args or 7 args, so 5/6/8 should be rejected with a clear message rather than failing deep inside the algorithm.
- **Category:** `control flow`

#### 270. `limo_tfce.m:638` — ⚪ LOW · CONFIRMED

**The catch-block fallback in the 3D branch calls bwlabel on a 3-D binary volume, but bwlabel only accepts 2-D input, so if limo_findcluster ever throws the intended fallback also throws instead of producing a clustering.**

- **Why:** In case 3 the clustering is wrapped in try/catch: try limo_findcluster((data>h),channeighbstructmat,2) catch [clustered_map,num]=bwlabel((data>h)) (lines 635-639, and identically at 678-682, 700-704, 762-766, 816-820, 836-840). The comment says the fallback 'allow[s] continuous mapping', but (data>h) is a 3-D array [x,y,z] and MATLAB's bwlabel requires a 2-D binary image (bwlabeln is the N-D version). So on any failure of limo_findcluster the catch immediately errors ('BW must be a 2-D binary image'), defeating the fallback. Additionally, even if it did run, bwlabel/bwlabeln would treat the channel dimension as a regular spatial grid, which is statistically wrong for EEG channel adjacency and would silently corrupt the extent map.
- **Category:** `data handling`

#### 271. `limo_yuen_ttest.m:1` — ⚪ LOW · CONFIRMED

**The NaN test `if isnan(a(:))` (and the b variant) is true only when EVERY element is NaN, so partially-missing data silently takes the no-NaN branch and returns NaN statistics instead of being handled.**

- **Why:** limo_yuen_ttest selects between a fast no-NaN path (option 1) and a per-electrode NaN-handling path (option 2) via `if isnan(a(:)) option = 2; elseif isnan(b(:)) option = 2; else option = 1; end`. isnan(a(:)) returns a logical column vector; a bare `if` on it is true only if all entries are nonzero, i.e. only when the ENTIRE array is NaN. With realistic partial NaNs (e.g. a missing channel/trial), the condition is false, option 1 runs, and sort(a,3)/var(...,3) propagate NaN, so every frame that has any NaN trial returns NaN for Ty, p, CI. The intended guard is any(isnan(a(:))). The option-2 branch it is supposed to fall into is itself broken (it does bsort=sort(b,3) on a 2D squeezed matrix -> a no-op that leaves b unsorted before winsorizing, and diff(electrode,:)=ma-mb assigns full matrices to a row), so NaN handling never actually works.
- **Category:** `control-flow`

#### 272. `limo_FDR.m:15` — ⚪ LOW · PLAUSIBLE

**NaN p-values are counted in V, inflating the BH/BY denominator and making the FDR threshold overly conservative (silent power loss).**

- **Why:** sort(p(:)) sends any NaN entries to the end of the vector, but V = length(p) still counts them. The Benjamini-Hochberg comparison p(i) <= (i/V)*alpha then uses a V that is larger than the number of valid tests, so every real p-value is judged against a smaller-than-correct threshold. NaN entries themselves never satisfy p<=... (NaN comparisons are false), so they are correctly excluded from the rejection set, but they still shrink the acceptance region for the valid tests. In a mass-univariate EEG toolbox where masked channels/frames are routinely NaN, this yields a statistically wrong (too conservative) FDR cutoff rather than the intended one, inflating Type-II error. The docstring advertises the function as a general 'vector of p-values' utility with no NaN precondition, so passing NaN-containing p is realistic.
- **Category:** `numerics/stats`

#### 273. `limo_batch_design_matrix.m:255` — ⚪ LOW · PLAUSIBLE

**Time-Frequency component fallback squares the data twice, yielding 4th-power values instead of power.**

- **Why:** In the TF-components no-datafiles fallback, line 253 computes `signal = abs(eeg_getdatact(EEGLIMO,'component',...).^2);` (already squared), and then line 255 computes `Y = abs(signal(:,trim_lowf:trim_highf,trim1:trim2,:)).^2;` squaring a second time, so this path produces amplitude to the 4th power rather than power. (Separately, `eeg_getdatact` returns time-domain component activations, not a freq x time cube, so the 4-subscript indexing on line 255 is itself dimensionally inconsistent for this fallback.) The datafiles-driven paths (icatimef/icaersp) apply `.^2` only once on line 255, so this fallback is inconsistent with them.
- **Category:** `numerics-stats`

#### 274. `limo_batch_import_data.m:89` — ⚪ LOW · PLAUSIBLE

**In the Time-analysis end branch, the nearest-sample position is computed from `EEGLIMO.times` but then used to index `timevect` (which is `EEGLIMO.etc.timeerp`), risking a value mismatch or out-of-range index.**

- **Why:** The start branch (lines 75-81) consistently uses `timevect` for both the comparison and the indexing. The end branch instead compares against and searches `EEGLIMO.times` (lines 85, 89) but assigns `LIMO.data.end = timevect(position)` and `trim2 = position`, then slices `timevect(trim1:trim2)` at line 94. If `timevect` (the ERP time vector, timeerp) and `EEGLIMO.times` (raw epoch times) differ in length or sampling — which is not guaranteed to be identical — `position` can index the wrong element of timevect or exceed its length, producing an incorrect end value or an index-out-of-bounds error. The analogous Time-Frequency block (lines 149-155) correctly uses `timevect` throughout, confirming this is an oversight.
- **Category:** `indexing`

#### 275. `limo_chancluster_test.m:98` — ⚪ LOW · PLAUSIBLE

**The observed-data clustering indexes ori_p/ori_f with the leftover bootstrap loop counter kk, using only one column instead of the full observed matrix.**

- **Why:** After the bootstrap loop (for kk=1:b), kk retains its last value b. The observed-data section then computes clusters on squeeze(ori_p(:,kk)) (line 98) and squeeze(ori_p(:,:,kk)) (line 104), i.e. it slices the observed data at bootstrap index b, which is meaningless for the observed data (ori_p is 1D/2D, so (:,:,kk) with kk=b either errors when b>1 or silently takes the wrong slice). L/NUM from this wrong clustering then drive the corrected_p/mask computation at lines 113-118, corrupting the result.
- **Category:** `indexing/copy-paste`

#### 276. `limo_contrast.m:553` — ⚪ LOW · PLAUSIBLE

**The OLS/WLS bootstrap re-zscore of covariates is gated on a NaN test performed after NaN rows were already removed, so the block is dead and covariates are never re-standardized.**

- **Why:** Lines 549-550 set trials_to_keep=~isnan(Y(:,1)) and Y=Y(trials_to_keep,:), removing all NaN rows. Line 553 then guards the covariate re-zscore with any(isnan(Y(:,1))) && ..., which is always false because Y(:,1) no longer contains NaN. The intended behavior (as done correctly in the IRLS branch at line 603, which tests isnan before removal) is to re-standardize the covariate columns after dropping trials.
- **Category:** `control flow`

#### 277. `limo_contrast_checking.m:124` — ⚪ LOW · PLAUSIBLE

**For a multi-row (F) contrast, the validity flag `go` is overwritten each loop iteration, so only the LAST row's validity is returned; invalid earlier rows are accepted.**

- **Why:** In the nargin==2 branch the loop `for s=1:size(varargin{1},1)` checks each contrast row and sets `go` (0 or 1) but never aggregates across rows and never breaks on failure. Thus the returned `go` reflects only the final row. If an F-contrast matrix has an invalid row followed by a valid row, the function returns go=1. Callers that pass multi-row contrasts to the 2-arg validity check — e.g. limo_contrast.m:172 `limo_contrast_checking(LIMO.contrast{contrast_nb}.C,LIMO.design.X)` and limo_contrast_manager.m:325/332/342 with handles.C — will accept an invalid contrast and proceed to compute statistics on it.
- **Category:** `control flow`

#### 278. `limo_display_image_callback.m:81` — ⚪ LOW · PLAUSIBLE

**In the Time-Frequency branch the code references a bare variable freqvect that is never defined in this function (it lives in udat.freqvect), so the branch crashes.**

- **Why:** Everywhere else this callback accesses the frequency axis as udat.freqvect (e.g. lines 67-68). Lines 81, 84 and 87 use a bare freqvect, which is undefined in the function scope, so any Time-Frequency invocation errors with 'Undefined function or variable freqvect' before the try/catch on line 235. Line 238-239 then compound the issue by using yframe/frame that were never validly computed.
- **Category:** `control-flow-logic`

#### 279. `limo_display_image_callback.m:100` — ⚪ LOW · PLAUSIBLE

**frame is clamped only on the low side (<=0 -> 1) with no upper clamp, so a click near the maximum time indexes past the last column of toplot and crashes topoplot.**

- **Why:** The sibling routine limo_display_image.m clamps both ends (lines 370-371: `if frame<=0; frame=1; end` and `if frame>=size(toplot,2); frame=size(toplot,2); end`). Here only the lower clamp exists. Because udat.ratio is computed as range/length rather than range/(length-1), floor(x/ratio) can reach length at the far edge, making frame = frame_zeros + length exceed size(toplot,2). frame then indexes udat.toplot(:,frame) at line 119/130 out of bounds.
- **Category:** `indexing-dimension`

#### 280. `limo_display_image_tf.m:102` — ⚪ LOW · PLAUSIBLE

**dim comes from inputdlg as a cell array of char and is used directly as a numeric subscript, which crashes.**

- **Why:** inputdlg returns a cell array of strings, e.g. {'2'}. Using that cell as an array subscript (handles.data3d(:,:,:,dim)) is illegal in MATLAB ('Function subsindex is not defined for values of class cell'). The value must be converted with str2double before indexing. The same applies to line 103.
- **Category:** `data-handling`

#### 281. `limo_display_image_tf.m:308` — ⚪ LOW · PLAUSIBLE

**In the case-2 (Electrodes x Times) all-NaN branch the placeholder is sized with size(D,3), which is 1 for the 2D D, producing a single-column image instead of channels x times.**

- **Why:** In the popup case 2 slider path, D = squeeze(handles.scale(:,slider_sel,:)) is a 2D [channels x times] matrix, so size(D,3) == 1. The all-NaN fallback builds zeros(nchan,1) and passes it to plot_main/plot_chanfreq which imagesc it against handles.times_here (length ntime), giving a degenerate single-column image / axis-data length mismatch. It should be size(D,2). (Same on line 311.)
- **Category:** `indexing-dimension`

#### 282. `limo_eeg_tf.m:539` — ⚪ LOW · PLAUSIBLE

**Single-channel H0 interaction TFCE assigns a 3D [freq x time x nboot] result into a 3-subscript target (1,:,:), which is one subscript short and mismatches sizes.**

- **Why:** In the non-parallel single-channel branch, `tfce_H0_score(1,:,:) = limo_tfce(2,squeeze(H0_Interaction_effect(:,:,:,1,:)),[])`. The squeezed argument is [freq x time x nboot] and limo_tfce(type 2) returns [freq x time x nboot], but the LHS `(1,:,:)` denotes a [1 x freq x time] slice, dropping the bootstrap dimension. The analogous R2 (line 459) and covariate (line 581) branches correctly use four subscripts `(1,:,:,:)`.
- **Category:** `indexing/dimension`

#### 283. `limo_expected_chanlocs.m:67` — ⚪ LOW · PLAUSIBLE

**Typo 'fielsep' (instead of filesep) throws an undefined-function error when building the file list from multiple filenames.**

- **Why:** In the nargin>=2 branch where FileName is a cell of several names (size(FileName,1) > 1), line 67 builds Files{n} = [Paths{n} fielsep Names{n}]. 'fielsep' is not a defined function or variable in MATLAB, so this line raises 'Undefined function or variable fielsep' the first time it executes.
- **Category:** `data-handling`

#### 284. `limo_itc_gui.m:655` — ⚪ LOW · PLAUSIBLE

**Both branches of the z-score decision set handles.zscore=1, so the detection of already-standardized regressors has no effect.**

- **Why:** After computing whether the continuous regressors are centered and reduced, the if/else at lines 655-660 sets handles.zscore=1 in the true branch and also handles.zscore=1 in the false branch. The computed 'centered'/'reducted' flags therefore never change the outcome; the branch is dead logic. If the intent was to skip z-scoring when data are already standardized, that never happens here (z-scoring is always left enabled unless the separate z_score checkbox is toggled).
- **Category:** `logic`

#### 285. `limo_median.m:58` — ⚪ LOW · PLAUSIBLE

**limo_median and limo_harrell_davis store the UPPER bound in CI column 1 and the LOWER bound in column 3, opposite to their own documentation and opposite to limo_trimmed_mean, so any consumer indexing columns uniformly gets swapped bounds.**

- **Why:** The header of limo_median (and limo_harrell_davis) says the 3-slice output is 'the lower CI, the median and the high CI' (index 1 = lower). But line 58 sets M(i,j,1)=M(i,j,2)+c.*xd_bse (c>0, xd_bse>0 => this is the UPPER bound) and line 59 sets M(i,j,3)=M(i,j,2)-c.*xd_bse (LOWER). limo_harrell_davis does the same (lines 98-99). In contrast, limo_trimmed_mean line 75 puts the LOWER bound in index 1 (TM(:,:,1)=TM(:,:,2)+tinv(alpha/2,df)*se, where tinv(alpha/2,.) is negative). So the three estimator functions are mutually inconsistent about which column is the lower vs upper CI. Code in limo_robust_ci.m stores these 3-slice outputs (lines 261/277/293) into TM/HD/Med and saves them; any downstream code that assumes a fixed (lower-in-1) convention across estimators will plot/report HD and Median intervals inverted.
- **Category:** `data handling`

#### 286. `limo_warndlg.m:11` — ⚪ LOW · PLAUSIBLE

**Fallback path passes the user warning message straight into warning() where it is interpreted as a printf-style format string and as (message,title) format+args.**

- **Why:** When EEGLAB's warndlg2 is absent, the code calls warning(varargin{:}). warndlg is normally invoked as warndlg(message, title); warning(message, title) treats the first arg as a sprintf format string and the second as a substitution value. Any message containing '%' (e.g. progress text like '50% complete') or a backslash gets mangled or throws an 'Invalid format' / 'too many/few arguments' error, and a two-argument call feeds the title in as a format argument. This diverges from the intended plain-message display and can crash where a simple warning was wanted.
- **Category:** `data-handling`

#### 287. `limo_yuen_ttest.m:143` — ⚪ LOW · PLAUSIBLE

**In the NaN branch, `a = squeeze(tmpa(electrode,:,:)); a = a(~isnan(a))` collapses the [frames x trials] slice into a single column vector, destroying the frames dimension so na=size(a,2)=1 and all per-frame statistics are corrupted.**

- **Why:** `squeeze(tmpa(electrode,:,:))` yields a [frames x trials] matrix. `a = a(~isnan(a))` logical-indexes it, which flattens to a single column vector of the non-NaN elements across ALL frames and trials. Then `na=size(a,2)` becomes 1 (column vector), `ga=floor(percent*1/100)=0`, and every subsequent per-frame computation is meaningless: the frames dimension is gone, so the loop cannot produce one Yuen test per frame as intended. This branch cannot recover the intended [channels x frames] output. Combined with the guard bug (line 70) this branch is only reachable on all-NaN input, but any attempt to make case 2 work is fundamentally broken by this flatten.
- **Category:** `indexing/dimension`
