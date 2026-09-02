CODE='local t={} local y,n=0,0 for i=1,100 do for j=1,5 do y=#t*1 n=n+0 end n=n+1+y end print(n)'

luajit -joff    -e "$CODE"
luajit -O3,-dce -e "$CODE"
