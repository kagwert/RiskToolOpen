function vals = resampleMonthly(srcTime, srcVals, monthGrid)
% resampleMonthly  Resample a signal vector to a monthly end-of-month grid.
%
%   vals = resampleMonthly(srcTime, srcVals, monthGrid)
%
%   Returns the last non-NaN observation within each calendar month.
%   Uses year×100+month integer key to avoid timezone issues.
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   srcTime    (:,1) datetime  – timestamps of the source series
%   srcVals    (:,1) double    – values of the source series
%   monthGrid  (:,1) datetime  – monthly end-of-month target dates
%
% -------------------------------------------------------------------------
%  OUTPUT
% -------------------------------------------------------------------------
%   vals       (:,1) double    – resampled values (NaN where no data)

    n     = numel(monthGrid);
    vals  = nan(n, 1);
    srcYM = year(srcTime) * 100 + month(srcTime);

    for k = 1 : n
        ym   = year(monthGrid(k)) * 100 + month(monthGrid(k));
        mask = srcYM == ym;
        v    = srcVals(mask);
        v    = v(~isnan(v));
        if ~isempty(v)
            vals(k) = v(end);   % last non-NaN observation in the month
        end
    end
end
