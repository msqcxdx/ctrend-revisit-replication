function latex = fCreateLatexTable(rInput)
% Function for creating code for a latex table
%
% Input:
%   rInput:     Struct, mit folgenden (optionalen) Feldern
%       .table:             Z x S Cell-Array, Tabelle, zwingend erforderlich
%       .fontsize:          String, spezifiziert Schriftgroesse
%                           tiny, small, normalsize (default), huge ...
%       .tablePlacement:    String, spezifiziert Position der Tabelle
%                           (default = 'H', fix)
%       .tableCaption:      String, Beschreibung der Tabelle
%       .tableLabel:        String, Label der Tabelle
%       .lCheckMulticolumn: Logical, gibt an, ob auf multicolumn geprueft
%                           werden soll
%       .tableColumnAlignment: String, gibt an, wie der Text positioniert
%                           werden soll (default = 'c'; ['l','r','c']) 
%       .tableMulticolumnAlignment: String, gibt an, wie der Text in
%                           multicolumn positioniert werden soll (default =
%                           'l',['l','r','c'])
%       .rInput.outputDir;  String, output directory

%% Eingaben pruefen
assert(isfield(rInput,'table'), 'Table required');

% Defaults setzen
if ~isfield(rInput,'fontsize')
    rInput.fontsize = 'normalsize';
end
if ~isfield(rInput,'tablePlacement')
    rInput.tablePlacement = 'H';
end 
if ~isfield(rInput,'tableCaption')
    rInput.tableCaption = 'MyTableCaption';
end 
if ~isfield(rInput,'tableLabel')
    rInput.tableLabel = 'tableLabel';
end 
if ~isfield(rInput,'lCheckMulticolumn')
    rInput.lCheckMulticolumn = true;
end
if ~isfield(rInput,'tableColumnAlignment')
    rInput.tableColumnAlignment = 'c';
end
if ~isfield(rInput,'tableMulticolumnAlignment')
    rInput.tableMulticolumnAlignment = 'l';
end
if ~isfield(rInput,'outputDir')
    rInput.outputDir = [];
end
if ~isfield(rInput,'lWriteToFile')
    rInput.lWriteToFile = true;
end
% if ~isfield(rInput,'tableCaption')
%     rInput.tableCaption = '';
% end
% if ~isfield(rInput,'tableLabel')
%     rInput.tableLabel = '';
% end

%% Felder vorverarveiten
if ~strcmp(rInput.tablePlacement,'')
    rInput.tablePlacement = ['[',rInput.tablePlacement,']'];
end

if rInput.lWriteToFile && isempty(rInput.outputDir)
    sDefaultOutputDir = fullfile(pwd, 'Results', 'Tables');
    if ~exist(sDefaultOutputDir, 'dir')
        mkdir(sDefaultOutputDir);
    end
    rInput.outputDir = fullfile(sDefaultOutputDir, [fSanitizeFilename(rInput.tableCaption), '.tex']);
elseif ~rInput.lWriteToFile
    rInput.outputDir = [];
end

% === Hier einige Kontrollen 
% NaN finden
lIsNaN = cellfun(@(x)any(isnan(x)),rInput.table,'un',1);
rInput.table(lIsNaN) = {''};

% Leere Felder in '' umwandeln
lIsEmpty = cellfun(@isempty,rInput.table,'un',1);
rInput.table(lIsEmpty) = {''};

% Zahlen finden und in Strings umwandeln
lIsNumeric = cellfun(@isnumeric,rInput.table,'un',1);
rInput.table(lIsNumeric) = cellfun(@num2str,rInput.table(lIsNumeric),'un',0);


%% Tabelle erstellen
% Dimensionen bestimmen
[iNumRows, iNumCols] = size(rInput.table);

% Start mit \begin{table}
latex = {['\begin{table}',rInput.tablePlacement];'\centering';...
    ['\',rInput.fontsize]; ['\begin{tabular}','{',...
    repmat(rInput.tableColumnAlignment,1,iNumCols),'}'];'\toprule'};

% Ueber jede Zeile iterieren
for iIdxR = 1:iNumRows
    if iIdxR == 2
        % \midrule ergaenzen
        latex(end+1) = {'\midrule'};
    end
    
    % String fuer jede einzelne Zeile erstellen, hier Initialisierung
    rowStr = '';
    
    % Aktuelle Zeile auslesen
    cCurrentRow = rInput.table(iIdxR,:);
    
    % Auf multicolumn pruefen
    if rInput.lCheckMulticolumn && any(contains(cCurrentRow,'multicolumn'))
        % Position finden
        vIdxMC = find(contains(cCurrentRow,'multicolumn'));
   
        % Ueber jede Spalte iterieren
        iNumMulticolumns = 0;
%         iCounter = 0;
        for iIdxC = 1:iNumCols 
            if iNumMulticolumns > 0
                iNumMulticolumns = iNumMulticolumns - 1;
                continue
            end
            % Wenn in aktueller Zelle multicolumn ist ...
            if any(iIdxC == vIdxMC)
                % ... Anzahl der Multicolumn Spalten auslesen
                % 1. Schritt: erste offene und geschlossene geschweifte 
                % Klammerm finden
                iIdxFirstBracketOpen = strfind(cCurrentRow{iIdxC},'{');
                iIdxFirstBracketClosed = strfind(cCurrentRow{iIdxC},'}');
                iIdxFirstBracketOpen = iIdxFirstBracketOpen(1);
                iIdxFirstBracketClosed = iIdxFirstBracketClosed(1);
                
                % 2. Schritt: Zahl innerhalb der Klammern 
                iNumMulticolumns = str2num(cCurrentRow{iIdxC}(iIdxFirstBracketOpen+1:...
                    iIdxFirstBracketClosed-1));
                
                % Fuer die naechsten iNumMulticolumns - 1 wird kein &
                % ergaenzt
                iNumMulticolumns = iNumMulticolumns - 1;
                
%                 % & hinzufuegen
%                 if ~((iIdxC + iCounter - 1) >= iNumCols)
%                     cCurrentRow{iIdxC} = [cCurrentRow{iIdxC},' & '];
%                 end
%                 
%                 % die naechsten iCounter Zellen wird kein & hinzugefuegt
%                 iCounter = iCounter - 1;
            else
                % Wenn in aktueller Zelle kein multicolumn ist
                if iNumMulticolumns == 0 
                    % Und die Zelle nicht Part von multicolumn ist, dann &
                    % ergaenzen
                    cCurrentRow{iIdxC} = [cCurrentRow{iIdxC},' & '];
                else
                    % Sonst ueberspringen
                    iCounter = iCounter - 1;
                end        
            end

            
            
        end
    else
        % & hinzufuegen
        cCurrentRow(1:end-1) = cellfun(@(x)horzcat(x,' & '),cCurrentRow(1:end-1),'un',0);
    end
        
    % Zu einem String
    latex(end+1) = {[char(horzcat(cCurrentRow{:})),'\\']};
end

latex(end+1) = {'\bottomrule'};
latex(end+1) = {'\end{tabular}'};
latex(end+1) = {['\caption{', rInput.tableCaption,'}']};
latex(end+1) = {['\label{table:', rInput.tableLabel,'}']};
latex(end+1) = {'\end{table}'};

%% Auf multicolumn pruefen

% Tabelle auf Konsole anzeigen
disp(char(latex))

%% Write to document
if ~isempty(rInput.outputDir)
    % Open file
    fid = fopen(rInput.outputDir, 'w');
    % Write rows
    for iIdxRow = 1:length(latex)
        fprintf(fid, '%s\n', latex{iIdxRow});     
    end
    % Close file
    fclose(fid);
end
end

function sOut = fSanitizeFilename(sIn)
sOut = lower(regexprep(sIn, '[^A-Za-z0-9]+', '_'));
sOut = regexprep(sOut, '(^_+|_+$)', '');
if isempty(sOut)
    sOut = 'table';
end
end
