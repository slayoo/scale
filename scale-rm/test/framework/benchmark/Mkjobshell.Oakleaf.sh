#! /bin/bash -x

# Arguments
BINDIR=${1}
PPNAME=${2}
INITNAME=${3}
BINNAME=${4}
PPCONF=${5}
INITCONF=${6}
RUNCONF=${7}
TPROC=${8}
DATDIR=${9}
DATPARAM=(`echo ${10} | tr -s ',' ' '`)
DATDISTS=(`echo ${11} | tr -s ',' ' '`)

# System specific
MPIEXEC="mpiexec"

if [ ! ${PPCONF} = "NONE" ]; then
  RUN_PP="${MPIEXEC} ${BINDIR}/${PPNAME} ${PPCONF} || exit"
fi

if [ ! ${INITCONF} = "NONE" ]; then
  RUN_INIT="${MPIEXEC} ${BINDIR}/${INITNAME} ${INITCONF} || exit"
fi

if [ ! ${RUNCONF} = "NONE" ]; then
  RUN_BIN="fipp -C -Srange -Ihwm -d prof ${MPIEXEC} ${BINDIR}/${BINNAME} ${RUNCONF} || exit"
fi

array=( `echo ${TPROC} | tr -s 'x' ' '`)
x=${array[0]}
y=${array[1]:-1}
let xy="${x} * ${y}"

# for Oakleaf-FX
# if [ ${xy} -gt 480 ]; then
#    rscgrp="x-large"
# elif [ ${xy} -gt 372 ]; then
#    rscgrp="large"
# elif [ ${xy} -gt 216 ]; then
#    rscgrp="medium"
# elif [ ${xy} -gt 12 ]; then
#    rscgrp="small"
# else
#    rscgrp="short"
# fi
rscgrp="debug"





cat << EOF1 > ./run.sh
#! /bin/bash -x
################################################################################
#
# ------ For Oakleaf-FX -----
#
################################################################################
#PJM --rsc-list "rscgrp=${rscgrp}"
#PJM --rsc-list "node=${TPROC}"
#PJM --rsc-list "elapse=00:20:00"
#PJM -j
#PJM -s
#
module load netCDF
module load netCDF-fortran
module load HDF5/1.8.9
module list
#
export PARALLEL=8
export OMP_NUM_THREADS=8

EOF1

if [ ! ${DATPARAM[0]} = "" ]; then
   for f in ${DATPARAM[@]}
   do
         if [ -f ${DATDIR}/${f} ]; then
            echo "ln -svf ${DATDIR}/${f} ." >> ./run.sh
         elif [ -d ${DATDIR}/${f} ]; then
            echo "rm -f                  ./input" >> ./run.sh
            echo "ln -svf ${DATDIR}/${f} ./input" >> ./run.sh
         else
            echo "datafile does not found! : ${DATDIR}/${f}"
            exit 1
         fi
   done
fi

if [ ! ${DATDISTS[0]} = "" ]; then
   for prc in `seq 1 ${TPROC}`
   do
      let "prcm1 = ${prc} - 1"
      PE=`printf %06d ${prcm1}`
      for f in ${DATDISTS[@]}
      do
         if [ -f ${f}.pe${PE}.nc ]; then
            echo "ln -svf ${f}.pe${PE}.nc ." >> ./run.sh
         else
            echo "datafile does not found! : ${f}.pe${PE}.nc"
            exit 1
         fi
      done
   done
fi

cat << EOF2 >> ./run.sh

rm -rf ./prof
mkdir -p ./prof

# run
${RUN_PP}
${RUN_INIT}
${RUN_BIN}

################################################################################
EOF2
