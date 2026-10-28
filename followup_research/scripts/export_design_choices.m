function export_design_choices(sInput,sOutput)
% Read-only conversion of the original MATLAB design table to CSV for E11.
% The exact input file remains in its accepted immutable production run.
arguments
    sInput (1,:) char
    sOutput (1,:) char
end
assert(isfile(sInput),'Missing DesignChoices input');
S = load(sInput,'tCombos');
assert(istable(S.tCombos) && height(S.tCombos)==3072, ...
    'Expected complete original 3,072-row design table');
T = S.tCombos;
T.b09_combo_id = (1:height(T))';
writetable(T,sOutput);
fprintf('FOLLOWUP_DESIGN_EXPORT_OK rows=%d path=%s\n',height(T),sOutput);
end
