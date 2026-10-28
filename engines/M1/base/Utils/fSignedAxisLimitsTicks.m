function [vLimits,vTicks] = fSignedAxisLimitsTicks(vValues,dStep)
% Deterministic signed y-axis limits/ticks for factor bar charts.

arguments
    vValues (:,1) {mustBeNumeric}
    dStep (1,1) {mustBeNumeric, mustBePositive}
end

vFinite = vValues(isfinite(vValues));
if isempty(vFinite)
    vLimits = [-dStep,dStep];
    vTicks = (-dStep:dStep:dStep)';
    return
end

dLowerTick = min(0,floor(min(vFinite)/dStep)*dStep);
dUpperTick = max(0,ceil(max(vFinite)/dStep)*dStep);
if dLowerTick == dUpperTick
    dLowerTick = dLowerTick-dStep;
    dUpperTick = dUpperTick+dStep;
end
vTicks = (dLowerTick:dStep:dUpperTick)';
% A small margin keeps a bar endpoint from touching the frame while all
% printed tick labels continue to denote their actual tick locations.
vLimits = [dLowerTick-0.1*dStep,dUpperTick+0.1*dStep];
end
