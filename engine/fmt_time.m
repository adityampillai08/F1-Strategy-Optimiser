function txt = fmt_time(t)
% FMT_TIME  seconds -> 'm:ss.mmm'
  txt = sprintf('%d:%06.3f', floor(t / 60), mod(t, 60));
end
