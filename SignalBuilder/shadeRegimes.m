function shadeRegimes(ax, T, label, cNeutral, cMild, cSevere)
% shadeRegimes  Shade plot background by regime label.
%
%   shadeRegimes(ax, T, label, cNeutral, cMild, cSevere)
%
%   Draws coloured patch backgrounds on axes ax to indicate regime periods.
%   Call this BEFORE plotting lines so shading appears behind data.
%   Works with both standard axes and UIAxes.
%
% -------------------------------------------------------------------------
%  PARAMETERS
% -------------------------------------------------------------------------
%   ax       matlab.graphics.axis.Axes or matlab.ui.control.UIAxes
%   T        (:,1) datetime  – monthly time vector
%   label    (:,1) double    – 0=Neutral, 1=MildUW, 2=SevereUW
%   cNeutral (1,3) double    – RGB colour for Neutral
%   cMild    (1,3) double    – RGB colour for MildUW
%   cSevere  (1,3) double    – RGB colour for SevereUW

    hold(ax, 'on');
    xl = [T(1), T(end)];

    for k = 1 : numel(T)
        if label(k) == 2
            clr = cSevere;
        elseif label(k) == 1
            clr = cMild;
        else
            clr = cNeutral;
        end
        if k < numel(T)
            xpatch = [T(k), T(k+1), T(k+1), T(k)];
        else
            xpatch = [T(k), T(k)+calmonths(1), T(k)+calmonths(1), T(k)];
        end
        patch(ax, xpatch, [-2 -2 2 2], clr, 'EdgeColor', 'none', ...
            'FaceAlpha', 0.6, 'HandleVisibility', 'off');
    end

    xlim(ax, xl);
end
