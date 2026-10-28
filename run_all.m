% CTREND_REVISIT_FILE_PURPOSE: Provide a MATLAB wrapper around the portable run_all.sh command-line entry point.
function status = run_all(command,arg1,arg2)
% MATLAB convenience wrapper for the Linux shell entrypoint.
arguments
    command (1,1) string = "preflight"
    arg1 (1,1) string = ""
    arg2 (1,1) string = ""
end
assert(~ispc,'The production runner requires Linux setsid/flock; use Linux or WSL on Windows hosts.');
allowed = ["preflight","test","plan","status","verify-all", ...
    "b19","b20","experiment","launch","assignment","all","all-fresh"];
assert(ismember(command,allowed),'Unsupported command.');
if ismember(command,["experiment","launch"])
    assert(~isempty(regexp(char(arg1),'^(P[01]_)?M[012]_D[012]$','once')), ...
        'Invalid experiment ID.');
end
if command == "assignment"
    assert(strlength(arg1) > 0 && strlength(arg2) > 0, ...
        'assignment requires a host label and CSV path.');
end
if command == "b19"
    assert(strlength(arg1)>0 && startsWith(arg1,"/"), ...
        'b19 requires a fresh absolute output directory.');
end
if strlength(arg2) > 0 && command ~= "assignment"
    assert(arg2 == "production",'Only production mode is supported.');
end
root = fileparts(mfilename('fullpath'));
parts = ["bash",string(fullfile(root,'run_all.sh')),command,arg1,arg2];
parts(strlength(parts)==0) = [];
assert(~any(contains(parts,"'")),'Paths and arguments must not contain single quotes.');
quoted = "'" + parts + "'";
[status,output] = system(strjoin(quoted," "));
fprintf('%s',output);
assert(status == 0,'run_all.sh failed with exit code %d.',status);
end
