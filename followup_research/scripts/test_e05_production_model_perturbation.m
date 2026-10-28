function test_e05_production_model_perturbation(sSource,sAcceptedResult,sOutput,iCutWeek)
% Refit the exact production b05 model body after FUTURE weekly-input shocks.
% All accepted files remain read-only. Injection is in memory after normal
% input/provenance loading; only the result-saving/portfolio tail is omitted.
% This tests the actual ranking/label/estimation/selection path, not b01/b02
% reconstruction or the real-world availability of a mechanical exit date.
% The report never certifies a complete raw-input-to-trade causal pipeline.
arguments
    sSource char
    sAcceptedResult char
    sOutput char
    iCutWeek double = 202016
end
old=pwd;cleanup=onCleanup(@()cd(old));cd(sSource);
source=fileread(fullfile(sSource,'b05CreateCTREND.m'));
source=strrep(source,sprintf('\r\n'),sprintf('\n'));
assert(contains(source,'clear; clc; close all;'));
source=strrep(source,'clear; clc; close all;','clc; close all;');
isM1=contains(source,'fRankPredictorsOwnSupport');
if isM1
    stop=strfind(source,sprintf('\n%% Sort\n'));
else
    stop=strfind(source,'% Training labels above remain');
end
assert(isscalar(stop),'Expected unique b05 model/accounting boundary');
body=source(1:stop-1);
% Match an executable assignment rather than assuming both model families
% share an introductory comment. M2 has dedicated raw causal return fields.
start=regexp(body,'(?m)^mReturns\s*=\s*rData\.','start');
assert(isscalar(start),'Expected unique initial weekly-return extraction');
A=load(sAcceptedResult,'mYhat','mBeta','mSelected','vDates');
names={'control','future_values','future_missingness'};
R=cell(numel(names),1);
for k=1:numel(names)
    if k==1
        modified=body;
    else
        % Scheduled week >= cutoff is not observed at its formation. All
        % lagged predictor/cap rows needed to predict the cutoff remain intact.
        inject=sprintf(['\nlFutureE05=rData.yrmoda>=%d;\n' ...
            'cFieldsE05={''mReturns'',''mRetLead'',''mReturnsM2Raw'',''mRetLeadM2Raw'',''mPnlReturns'',''mPnlRetLead'',''mPnlReturnsM2'',''mPnlRetLeadM2'',''mME'',''mClose'',''mVolume''};\n' ...
            'for jE05=1:numel(cFieldsE05)\n' ...
            ' if ~isfield(rData,cFieldsE05{jE05}),continue,end\n' ...
            ' zE05=rData.(cFieldsE05{jE05});\n' ...
            ' if size(zE05,1)~=numel(lFutureE05),error(''E05 field axis''),end\n'],iCutWeek);
        if k==2
            inject=[inject,sprintf(' zE05(lFutureE05,:)=1.7*zE05(lFutureE05,:)+0.123;\n')];
        else
            inject=[inject,sprintf(' zE05(lFutureE05,1:2:end)=NaN;\n')];
        end
        inject=[inject,sprintf([' rData.(cFieldsE05{jE05})=zE05;\nend\n' ...
            'cXE05=fieldnames(rChars);\nfor jE05=1:numel(cXE05)\n' ...
            ' zE05=rChars.(cXE05{jE05});\n' ...
            ' if size(zE05,1)~=numel(lFutureE05),error(''E05 X axis''),end\n'])];
        if k==2
            inject=[inject,sprintf(' zE05(lFutureE05,:)=-2.3*zE05(lFutureE05,:)+0.456;\n')];
        else
            inject=[inject,sprintf(' zE05(lFutureE05,1:2:end)=NaN;\n')];
        end
        inject=[inject,sprintf(' rChars.(cXE05{jE05})=zE05;\nend\n')];
        modified=[body(1:start-1),inject,body(start:end)];
    end
    B=iFit(modified);
    assert(isequal(B.vDates(:),A.vDates(:)),'E05 model calendar changed');
    prefix=A.vDates(:)<=iCutWeek;
    first=size(A.mYhat,2)-size(A.mBeta,1)+1;
    modelDates=A.vDates(first:end);prefixBeta=modelDates<=iCutWeek;
    q=struct('variant',names{k},'cutoff_week',iCutWeek, ...
        'checked_prediction_cells',numel(A.mYhat(:,prefix)), ...
        'changed_past_predictions',iChanged(A.mYhat(:,prefix),B.mYhat(:,prefix)), ...
        'changed_past_beta_cells',iChanged(A.mBeta(prefixBeta,:,:),B.mBeta(prefixBeta,:,:)), ...
        'changed_past_selection_cells',iChanged(A.mSelected(prefixBeta,:),B.mSelected(prefixBeta,:)), ...
        'changed_later_predictions',iChanged(A.mYhat(:,~prefix),B.mYhat(:,~prefix)), ...
        'scope','production_b05_only_frozen_weekly_inputs_exit_calendar_not_a_raw_pipeline_certificate');
    if k==1
        assert(isequaln(B.mYhat,A.mYhat) && isequaln(B.mBeta,A.mBeta) && ...
            isequaln(B.mSelected,A.mSelected),'E05 control must be bitwise identical');
    end
    assert(q.changed_past_predictions==0 && q.changed_past_beta_cells==0 && ...
        q.changed_past_selection_cells==0,'E05 production model depends on future input');
    if k>1,assert(q.changed_later_predictions>0,'E05 intervention had no later effect');end
    R{k}=q;fprintf('E05_REFIT variant=%s past_changes=%d later_changes=%d\n', ...
        names{k},q.changed_past_predictions,q.changed_later_predictions);
end
writetable(struct2table(vertcat(R{:})),sOutput);
fprintf('E05_PRODUCTION_MODEL_PERTURBATION_OK\n');
end

function B=iFit(script)
% Separate workspace for every fit; there are no cached predictions.
eval(script);
B=struct('mYhat',mYhat,'mBeta',mBeta,'mSelected',mSelected,'vDates',vDates);
end

function n=iChanged(a,b)
assert(isequal(size(a),size(b)),'E05 shape mismatch');
n=nnz(~((a==b)|(isnan(a)&isnan(b))));
end
