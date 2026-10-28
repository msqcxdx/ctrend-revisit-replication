function fDensityPlot(X, options)
% Function for creating a density plot

arguments
    X (:,:) {mustBeNumeric}
    options.FaceColor = 'black'
end

% Make X to vector
X = X(:);

X(isnan(X)) = [];

% Estimate density 
[f,xi] = ksdensity(X); 
histogram(X,xi,'Normalization','pdf','EdgeAlpha',0.3,'EdgeColor','black','FaceColor','black',...
    'FaceAlpha',0.3);
hold on
plot(xi, f, 'LineWidth',2,'Color','black')
hold off
box off

% [f,x] = ecdf(X);
% ecdfhist(f,x)
% hold on
% plot(x, f, 'LineWidth',2,'Color','black')

% q2 = ylim;
% L = true(1,length(xi));
% patch([xi(L) fliplr(xi(L))], [f(L), ones(1,nnz(L))*min(ylim)],options.FaceColor,'FaceAlpha',1);
end