set terminal png transparent nocrop enhanced font arial 8 size 800,600

set autoscale y
set autoscale y2

set key autotitle columnhead
plot "jobs_cpu.dat" using 2 with lines axes x1y1, "jobs_cpu.dat" using 3 with lines axes x2y2, "jobs_cpu.dat" using 4 with impulses axes x1y1, "jobs_cpu.dat" using 5 with impulses axes x1y1, "jobs_cpu.dat" using 6 with lines axes x1y1

