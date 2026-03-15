function m = evalPortfolio(allocVec, equityRet, bondRet)
% evalPortfolio  Compute portfolio return series and scalar performance metrics.
%
%   m = evalPortfolio(allocVec, equityRet, bondRet)
%
%   Portfolio return each month:
%       portRet = allocVec .* equityRet + (1 - allocVec) .* bondRet
%
%   NaN months (warm-up period) are treated as zero return.
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   allocVec   (:,1) double  – monthly equity allocation (e.g. 0.50)
%   equityRet  (:,1) double  – monthly equity return (may contain NaN)
%   bondRet    (1,1) double  – scalar monthly bond/cash return
%
% -------------------------------------------------------------------------
%  OUTPUT STRUCT FIELDS
% -------------------------------------------------------------------------
%   m.TotalReturn    – cumulative total return over period
%   m.AnnReturn      – annualised geometric return
%   m.SharpeRatio    – annualised Sharpe ratio (sqrt(12) scaling)
%   m.MaxDrawdown    – maximum peak-to-trough drawdown (negative)
%   m.AvgEquityAlloc – time-average equity allocation

    portRet = allocVec .* equityRet + (1 - allocVec) .* bondRet;
    portRet(isnan(portRet)) = 0;   % NaN months (warm-up) → 0

    equity = cumprod(1 + portRet);
    T      = numel(portRet);
    years  = T / 12;

    m.TotalReturn    = equity(end) - 1;
    m.AnnReturn      = (equity(end))^(1/years) - 1;
    m.AnnVol         = std(portRet, 'omitnan') * sqrt(12);
    m.SharpeRatio    = mean(portRet, 'omitnan') / ...
                       max(std(portRet, 'omitnan'), eps) * sqrt(12);
    running          = cummax(equity);
    m.MaxDrawdown    = min((equity - running) ./ running);
    m.AvgEquityAlloc = mean(allocVec, 'omitnan');
end
