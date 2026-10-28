function mustBeNumericOrDatetime(A)
%MUSTBENUMERICORLOGICAL Validate that value is numeric or datetime
%   MUSTBENUMERICORDATETIME(A) throws an error if A contains values that are
%   not numeric or datetime. MATLAB calls isnumeric to determine if A is
%   numeric and calls isdatetime to determine if A is logical.
%
%   See also: ISNUMERIC, ISDATETIME.

if ~isnumeric(A) && ~isdatetime(A)
    throwAsCaller(createValidatorException('MATLAB:validators:mustBeNumericOrLogical'));
end
