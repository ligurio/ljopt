CODE='local t={ka=0} local s=0 for i=1,400 do for j=1,5 do s=bit.band(t.ka,65535) t.ka=i end end print(s)'

luajit -joff -e "$CODE"
luajit -O3   -e "$CODE"
