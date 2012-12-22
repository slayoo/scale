!-------------------------------------------------------------------------------
!> module Thermodynamics
!!
!! @par Description
!!          Thermodynamics module
!!
!! @author H.Tomita and SCALE developpers
!!
!! @par History
!! @li      2011-10-24 (T.Seiki)     [new] Import from NICAM
!! @li      2012-02-10 (H.Yashiro)   [mod] Reconstruction
!! @li      2012-03-23 (H.Yashiro)   [mod] Explicit index parameter inclusion
!! @li      2012-12-22 (S.Nishizawa) [mod] Use thermodyn macro set
!!
!<
!-------------------------------------------------------------------------------
#include "macro_thermodyn.h"
module mod_atmos_thermodyn
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mod_stdio, only: &
     IO_FID_LOG, &
     IO_L
  use mod_const, only : &
     Rdry  => CONST_Rdry,  &
     CPdry => CONST_CPdry, &
     CVdry => CONST_CVdry, &
     RovCP => CONST_RovCP, &
     PRE00 => CONST_PRE00, &
     Rvap  => CONST_Rvap,  &
     CPvap => CONST_CPvap, &
     CVvap => CONST_CVvap, &
     CL    => CONST_CL,    &
     CI    => CONST_CI
  use mod_time, only: &
     TIME_rapstart, &
     TIME_rapend
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: ATMOS_THERMODYN_setup
  public :: ATMOS_THERMODYN_qd
  public :: ATMOS_THERMODYN_cv
  public :: ATMOS_THERMODYN_cp
  public :: ATMOS_THERMODYN_tempre
  public :: ATMOS_THERMODYN_tempre2
  !-----------------------------------------------------------------------------
  !
  !++ included parameters
  !
  include "inc_precision.h"
  include 'inc_index.h'
  include 'inc_tracer.h'

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  real(RP), public,      save :: AQ_CP(QQA) ! CP for each hydrometeors
  real(RP), public,      save :: AQ_CV(QQA) ! CV for each hydrometeors

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  subroutine ATMOS_THERMODYN_setup
    implicit none
  
    integer :: n
    !---------------------------------------------------------------------------

    AQ_CP(I_QV) = CPvap
    AQ_CV(I_QV) = CVvap

    if( QWS /= 0 ) then
     do n = QWS, QWE
       AQ_CP(n) = CL
       AQ_CV(n) = CL
     enddo
    endif

    if( QIS /= 0 ) then
     do n = QIS, QIE
       AQ_CP(n) = CI
       AQ_CV(n) = CI
     enddo
    endif

    return
  end subroutine ATMOS_THERMODYN_setup

  !-----------------------------------------------------------------------------
  subroutine ATMOS_THERMODYN_qd( qdry, q )
    implicit none

    real(RP), intent(out) :: qdry(KA,IA,JA)    ! dry mass concentration
    real(RP), intent(in)  :: q   (KA,IA,JA,QA) ! mass concentration

    integer :: i,j, k, iqw
    !-----------------------------------------------------------------------------

    call TIME_rapstart('SUB_thermodyn')
#ifdef _FPCOLL_
call START_COLLECTION('SUB_thermodyn')
#endif

    do j = 1, JA
    do i = 1, IA
    do k  = 1, KA

       CALC_QDRY( qdry(k,i,j), q, k, i, j, iqw )

    enddo
    enddo
    enddo

#ifdef _FPCOLL_
call STOP_COLLECTION('SUB_thermodyn')
#endif
    call TIME_rapend  ('SUB_thermodyn')

    return
  end subroutine ATMOS_THERMODYN_qd
  !-----------------------------------------------------------------------------
  subroutine ATMOS_THERMODYN_cp( cptot, q, qdry )
    implicit none

    real(RP), intent(out) :: cptot(KA,IA,JA)    ! total specific heat
    real(RP), intent(in)  :: q    (KA,IA,JA,QA) ! mass concentration
    real(RP), intent(in)  :: qdry (KA,IA,JA)    ! dry mass concentration

    integer :: i, j, k, iqw
    !---------------------------------------------------------------------------

    call TIME_rapstart('SUB_thermodyn')
#ifdef _FPCOLL_
call START_COLLECTION('SUB_thermodyn')
#endif

    do j = 1, JA
    do i = 1, IA
    do k = 1, KA

       CALC_CP(cptot(k,i,j), qdry(k,i,j), q, k, i, j, iqw, CPdry, AQ_CP)

    enddo
    enddo
    enddo

#ifdef _FPCOLL_
call STOP_COLLECTION('SUB_thermodyn')
#endif
    call TIME_rapend  ('SUB_thermodyn')

    return
  end subroutine ATMOS_THERMODYN_cp
  !-----------------------------------------------------------------------------
  subroutine ATMOS_THERMODYN_cv( cvtot, q, qdry )
    implicit none

    real(RP), intent(out) :: cvtot(KA,IA,JA)    ! total specific heat
    real(RP), intent(in)  :: q    (KA,IA,JA,QA) ! mass concentration
    real(RP), intent(in)  :: qdry (KA,IA,JA)    ! dry mass concentration

    integer :: i, j, k, iqw
    !---------------------------------------------------------------------------

    call TIME_rapstart('SUB_thermodyn')
#ifdef _FPCOLL_
call START_COLLECTION('SUB_thermodyn')
#endif

    do j = 1, JA
    do i = 1, IA
    do k = 1, KA

       CALC_CV(cvtot(k,i,j), qdry(k,i,j), q, k, i, j, iqw, CVdry, AQ_CV)

    enddo
    enddo
    enddo

#ifdef _FPCOLL_
call STOP_COLLECTION('SUB_thermodyn')
#endif
    call TIME_rapend  ('SUB_thermodyn')

    return
  end subroutine ATMOS_THERMODYN_cv
  !-----------------------------------------------------------------------------
  subroutine ATMOS_THERMODYN_tempre( &
      temp, pres,         &
      Ein,  dens, qdry, q )
    implicit none

    real(RP), intent(out) :: temp(KA,IA,JA)    ! temperature
    real(RP), intent(out) :: pres(KA,IA,JA)    ! pressure
    real(RP), intent(in)  :: Ein (KA,IA,JA)    ! internal energy
    real(RP), intent(in)  :: dens(KA,IA,JA)    ! density
    real(RP), intent(in)  :: qdry(KA,IA,JA)    ! dry concentration
    real(RP), intent(in)  :: q   (KA,IA,JA,QA) ! water concentration 

    real(RP) :: cv, Rmoist

    integer :: i, j, k, iqw
    !---------------------------------------------------------------------------

    call TIME_rapstart('SUB_thermodyn')
#ifdef _FPCOLL_
call START_COLLECTION('SUB_thermodyn')
#endif

    do j = 1, JA
    do i = 1, IA
    do k = 1, KA

       CALC_CV(cv, qdry(k,i,j), q, k, i, j, iqw, CVdry, AQ_CV)
       CALC_R(Rmoist, q(k,i,j,I_QV), qdry(k,i,j), Rdry, Rvap)

       temp(k,i,j) = Ein(k,i,j) / cv

       pres(k,i,j) = dens(k,i,j) * Rmoist * temp(k,i,j)

    enddo
    enddo
    enddo

#ifdef _FPCOLL_
call STOP_COLLECTION('SUB_thermodyn')
#endif
    call TIME_rapend  ('SUB_thermodyn')

    return
  end subroutine ATMOS_THERMODYN_tempre
  !-----------------------------------------------------------------------------
  subroutine ATMOS_THERMODYN_tempre2( &
      temp, pres,         &
      dens, pott, qdry, q )
    implicit none

    real(RP), intent(out) :: temp(KA,IA,JA)    ! temperature
    real(RP), intent(out) :: pres(KA,IA,JA)    ! pressure
    real(RP), intent(in)  :: dens(KA,IA,JA)    ! density
    real(RP), intent(in)  :: pott(KA,IA,JA)    ! potential temperature
    real(RP), intent(in)  :: qdry(KA,IA,JA)    ! dry concentration
    real(RP), intent(in)  :: q   (KA,IA,JA,QA) ! water concentration 

    real(RP) :: Rmoist, cp

    integer :: i, j, k, iqw
    !---------------------------------------------------------------------------

    call TIME_rapstart('SUB_thermodyn')
#ifdef _FPCOLL_
call START_COLLECTION('SUB_thermodyn')
#endif

    do j = 1, JA
    do i = 1, IA
    do k = 1, KA
       CALC_CP(cp, qdry(k,i,j), q, k, i, j, iqw, CPdry, AQ_CP)
       CALC_R(Rmoist, q(k,i,j,I_QV), qdry(k,i,j), Rdry, Rvap)
       CALC_PRE(pres(k,i,j), dens(k,i,j), pott(k,i,j), Rmoist, cp, PRE00)
       temp(k,i,j) = pres(k,i,j) / ( dens(k,i,j) * Rmoist )
    enddo
    enddo
    enddo

#ifdef _FPCOLL_
call STOP_COLLECTION('SUB_thermodyn')
#endif
    call TIME_rapend  ('SUB_thermodyn')

    return
  end subroutine ATMOS_THERMODYN_tempre2
  !-----------------------------------------------------------------------------
end module mod_atmos_thermodyn
