reset

set ylabel 'time(ns)'
set xlabel 'fib number'
set xtics 0,10
set title 'Fibonacci Execution Time'
set term png enhanced font 'Verdana,10'
set output 'client_time.png'

plot [:][:]'client_time' \
using 2:xtic(10) with linespoints linewidth 2 title 'user space', \
'' using 3:xtic(10) with linespoints linewidth 2 title 'kernel space'
