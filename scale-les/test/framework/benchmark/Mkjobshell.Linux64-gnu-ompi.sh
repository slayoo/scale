#! /bin/bash -x

# Arguments
BINDIR=${1}
INITNAME=${2}
BINNAME=${3}
INITCONF=${4}
RUNCONF=${5}
TPROC=${6}

# System specific
MPIEXEC="mpirun -np ${TPROC}"

# Generate run.sh

cat << EOF1 > ./run.sh
#! /bin/bash -x
################################################################################
#
# ------ FOR Linux64 & gnu C&fortran & openmpi -----
#
################################################################################
export FORT_FMT_RECL=400
!export GFORTRAN_UNBUFFERED_ALL=Y

# run
${MPIEXEC} ${BINDIR}/${INITNAME} ${INITCONF} || exit
${MPIEXEC} ${BINDIR}/${BINNAME}  ${RUNCONF}  || exit

################################################################################
EOF1
