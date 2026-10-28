function fSaveOpenFigures(sStepName)
% Save any figures left open by a pipeline step.

if nargin < 1 || isempty(sStepName)
    sStepName = 'step';
end

sOutDir = fullfile('.', 'Results', 'Figures');
if ~exist(sOutDir, 'dir')
    mkdir(sOutDir);
end

vFigures = findall(0, 'Type', 'figure');
if isempty(vFigures)
    return
end

[~, vOrder] = sort(arrayfun(@(h) h.Number, vFigures));
vFigures = vFigures(vOrder);

for iIdxFig = 1:numel(vFigures)
    hFig = vFigures(iIdxFig);
    iFigNum = hFig.Number;
    sBase = sprintf('%s_figure%02d', sStepName, iFigNum);
    sBase = regexprep(sBase, '[^A-Za-z0-9_\\-]', '_');
    sFigFile = fullfile(sOutDir, [sBase, '.fig']);
    sPngFile = fullfile(sOutDir, [sBase, '.png']);

    savefig(hFig, sFigFile);
    try
        exportgraphics(hFig, sPngFile, 'Resolution', 200);
    catch
        print(hFig, sPngFile, '-dpng', '-r200');
    end
end

close(vFigures);
end
