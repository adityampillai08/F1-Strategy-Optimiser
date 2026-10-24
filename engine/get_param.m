function value = get_param(params, name, defaultValue)
% Return params.(name) if present and non-empty, otherwise the default.
  if isfield(params, name) && ~isempty(params.(name))
    value = params.(name);
  else
    value = defaultValue;
  end
end
