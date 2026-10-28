function [cTable, mResultsNodes, cResultsNodesNames, cNodesNames] = ...
    fEvaluateResearchDesigns(tCombos, mResults, sObjFun, iNumDigits)
% Function for evaluating the importance of a decision node on model
% performance
%
% Input:
%   tCombos:        C x K table of combinations
%                   C: number of combos
%                   K: number of decision nodes
%   mResults:       C x K matrix of the performance metrics to analyze
%                   C: number of combos
%                   K: number of decision nodes
%   sObjFun:        String/char, specifies the objective function
%                   (default = median)
%   iNumDigits:     Scalar, integer, number of digits in table
%                   (default = 2)
%
% Output:
%   cTable:         N x (K+2) table of results
%                   N: number of decisions
%                   K: number of decision nodes

% Check arguments
arguments
    tCombos table
    mResults (:,:) {mustBeNumeric}
    sObjFun char = 'median'
    iNumDigits (1,1) {mustBeNumeric, mustBeNonnegative} = 2
end

% Get variable names
cDecisionNodes = tCombos.Properties.VariableNames;

% Determine dimensions
[iNumCombos, iNumNodes]     = size(tCombos);
[iNumCombosR, iNumModels]   = size(mResults);

% Check dimensions
assert(iNumCombos == iNumCombosR, 'Number of combinations must agree');

% Define objective function
switch upper(sObjFun)
    case 'MEDIAN'
        hObjFun = @(x)median(x,1,'omitmissing');
    case 'MEAN'
        hObjFun = @(x)mean(x,1,'omitmissing');
    case 'STD'
       hObjFun = @(x)std(x,[],1,'omitmissing'); 
    case 'NAN'
        hObjFun = @(x)sum(isnan(x),1,'omitmissing');
    otherwise
        error('Unknown objective function');
end

% Create a cell-array for all variables
cResultsNodes = cell(iNumNodes,1);
mResultsNodes = [];
cResultsNodesNames = [];
cNodesNames = [];
% Loop over each decision node
for iIdxN = 1:iNumNodes
    % Get data
    vColumn = tCombos.(cDecisionNodes{iIdxN});

    % Get unique values
    vUnique     = unique(vColumn);
    iNumUnique  = length(vUnique);

    % Initialize memory
    mResultsTemp = NaN(iNumUnique, iNumModels);
    cDecision    = cell(iNumUnique,1);
    cNodes       = repmat(cDecisionNodes(iIdxN), iNumUnique, 1);

    % Loop over unique values
    for iIdxI = 1:iNumUnique
        if isnumeric(vColumn) | islogical(vColumn)
            % Numeric or logical
            dValTemp = vUnique(iIdxI);

            % Save value
            if isnumeric(vColumn)
                cDecision{iIdxI} = num2str(dValTemp);
            else
                if dValTemp
                    cDecision{iIdxI} = 'yes';
                else
                    cDecision{iIdxI} = 'no';
                end
            end

            % Get all results for that value
            mResTemp = mResults(vColumn == dValTemp,:);

        elseif iscell(vColumn)
            % Cell-array with strings
            sValTemp = vUnique(iIdxI);

            % Save value
            cDecision{iIdxI} = sValTemp{1};

            % Get all results for that value
            mResTemp = mResults(strcmp(vColumn, sValTemp),:);
        end

        % Evaluate results
        mResultsTemp(iIdxI,:) = hObjFun(mResTemp);
    end
    % Save in cell array
    cResultsNodes{iIdxN} = mResultsTemp;

    % Put also into matrix format
    mResultsNodes       = [mResultsNodes; mResultsTemp];
    cResultsNodesNames  = [cResultsNodesNames; cDecision];
    cNodesNames         = [cNodesNames; cNodes];
end

% Create table
cTable = [cNodesNames, cResultsNodesNames, sprintfc(['%.',num2str(iNumDigits),'f'], round(mResultsNodes,iNumDigits))];
end