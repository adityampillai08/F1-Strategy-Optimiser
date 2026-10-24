function combMat = compound_combinations(compounds, nStints)
% Every sequence of length nStints over the compound list (repetition allowed),
% in lexicographic order. Result size: numel(compounds)^nStints  x  nStints.
  nC    = numel(compounds);
  nRows = nC ^ nStints;
  rowId = (0 : nRows - 1).';
  idx   = zeros(nRows, nStints);
  for col = 1:nStints
    % Digit 'col' of rowId written in base nC (most significant digit first).
    idx(:, col) = mod(floor(rowId / nC^(nStints - col)), nC) + 1;
  end
  combMat = compounds(idx);
end
