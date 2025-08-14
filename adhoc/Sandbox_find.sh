

# Attempt 1 (No Filtering, No Pruning)
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches && time `find /home/enrices/ -name '*.py' -printf '%T@ %p\n' > results.txt`
# real    3m17.865s
# real    4m27.427s
wc results.txt
# 2595   5211 272124 results.txt


# Attempt 2 (Filtering + Pruning)
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches && time `find /home/enrices/ -name ".*" -prune , -name '*.py' -printf '%T@ %p\n' > results_2.txt`
# real    3m4.596s
# real    4m25.872s
wc results_2.txt
#   14   28 1200 results_2.txt


# Attempt 3 (Filtering + Pruning) (v2)
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches && time `find /home/enrices/ -type d -path '*/.*' -prune -o -not -name '.*' -type f -name '*.py' -printf '%T@ %p\n' > results_3.txt`
# real    3m10.923s
wc results_3.txt
#   14   28 1200 results_3.txt


# Attempt 4 (Filtering, No Pruning)
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches && time `find /home/enrices/ -name '*.py' -not -path '*/.*' -printf '%T@ %p\n' > results_4.txt`
# real    4m27.001s
wc results_4.txt
#   14  14 308 results_4.txt


#################################################################
# Just to find more ideas for pruning :
find /home/enrices/ -not -path '*/.*' -not -path '*/data' -print | sort > test3.txt
more test3.txt
#################################################################

find /home/enrices/ -path '*/.*' -prune , -path '*/data*' -prune , -path '*/log*' -prune , -name '*.py' -print




