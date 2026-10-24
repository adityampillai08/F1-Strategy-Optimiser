function value = ask_number(label, defaultValue, lo, hi, wholeOnly)
% ASK_NUMBER  Prompt until a valid number in [lo, hi] is typed (Enter = default).
  while true
    txt = input(sprintf('  %s [default %g, allowed %g-%g]: ', ...
                        label, defaultValue, lo, hi), 's');
    if isempty(strtrim(txt))
      value = defaultValue;
      return;
    end
    value = str2double(txt);
    ok = isscalar(value) && isfinite(value) && value >= lo && value <= hi;
    if wholeOnly
      ok = ok && (value == fix(value));
    end
    if ok
      return;
    end
    fprintf('  Invalid entry - please enter a number from %g to %g.\n', lo, hi);
  end
end
