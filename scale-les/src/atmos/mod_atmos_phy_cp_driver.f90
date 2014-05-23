!-------------------------------------------------------------------------------
!> module ATMOSPHERE / Physics Cumulus
!!
!! @par Description
!!          Cumulus parameterization driver
!!
!! @author Team SCALE
!!
!! @par History
!! @li      2014-05-04 (H.Yashiro)    [new]
!<
!-------------------------------------------------------------------------------
#include "inc_openmp.h"
module mod_atmos_phy_cp_driver
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use scale_precision
  use scale_stdio
  use scale_prof
  use scale_grid_index
  use scale_tracer
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: ATMOS_PHY_CP_driver_setup
  public :: ATMOS_PHY_CP_driver

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
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
  !> Setup
  subroutine ATMOS_PHY_CP_driver_setup
!    use scale_atmos_phy_cp, only: &
!       ATMOS_PHY_CP_setup
    use mod_atmos_admin, only: &
       ATMOS_PHY_CP_TYPE, &
       ATMOS_sw_phy_cp
    implicit none
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '++++++ Module[DRIVER] / Categ[ATMOS PHY_CP] / Origin[SCALE-LES]'

    if ( ATMOS_sw_phy_cp ) then

       ! setup library component
       !call ATMOS_PHY_CP_setup( ATMOS_PHY_CP_TYPE )

       ! run once (only for the diagnostic value)
       call ATMOS_PHY_CP_driver( .true., .false. )

    endif

    return
  end subroutine ATMOS_PHY_CP_driver_setup

  !-----------------------------------------------------------------------------
  !> Driver
  subroutine ATMOS_PHY_CP_driver( update_flag, history_flag )
    use scale_time, only: &
       dt_CP => TIME_DTSEC_ATMOS_PHY_CP
    use scale_stats, only: &
       STAT_checktotal, &
       STAT_total
    use scale_history, only: &
       HIST_in
!    use scale_atmos_phy_cp, only: &
!       ATMOS_PHY_CP
    use mod_atmos_vars, only: &
       DENS,              &
       MOMZ,              &
       MOMX,              &
       MOMY,              &
       RHOT,              &
       QTRC,              &
       MOMZ_t => MOMZ_tp, &
       MOMX_t => MOMX_tp, &
       MOMY_t => MOMY_tp, &
       RHOT_t => RHOT_tp, &
       QTRC_t => QTRC_tp
    use mod_atmos_phy_cp_vars, only: &
       MOMZ_t_CP      => ATMOS_PHY_CP_MOMZ_t,        &
       MOMX_t_CP      => ATMOS_PHY_CP_MOMX_t,        &
       MOMY_t_CP      => ATMOS_PHY_CP_MOMY_t,        &
       RHOT_t_CP      => ATMOS_PHY_CP_RHOT_t,        &
       QTRC_t_CP      => ATMOS_PHY_CP_QTRC_t,        &
       MFLX_cloudbase => ATMOS_PHY_CP_MFLX_cloudbase
    implicit none

    logical, intent(in) :: update_flag
    logical, intent(in) :: history_flag

    real(RP) :: RHOQ(KA,IA,JA)
    real(RP) :: total ! dummy

    integer  :: k, i, j, iq
    !---------------------------------------------------------------------------

    if ( update_flag ) then

       if( IO_L ) write(IO_FID_LOG,*) '*** Physics step, cumulus'

!       call ATMOS_PHY_CP( DENS,          & ! [IN]
!                          MOMZ,          & ! [IN]
!                          MOMX,          & ! [IN]
!                          MOMY,          & ! [IN]
!                          RHOT,          & ! [IN]
!                          QTRC,          & ! [IN]
!                          MOMZ_t_CP,     & ! [INOUT]
!                          MOMX_t_CP,     & ! [INOUT]
!                          MOMY_t_CP,     & ! [INOUT]
!                          RHOT_t_CP,     & ! [INOUT]
!                          QTRC_t_CP,     & ! [INOUT]
!                          MFLX_cloudbase ) ! [INOUT]

       ! tentative!
       MOMZ_t_CP(:,:,:)    = 0.0_RP
       MOMX_t_CP(:,:,:)    = 0.0_RP
       MOMY_t_CP(:,:,:)    = 0.0_RP
       RHOT_t_CP(:,:,:)    = 0.0_RP
       QTRC_t_CP(:,:,:,:)  = 0.0_RP
       MFLX_cloudbase(:,:) = 0.0_RP

       if ( history_flag ) then
          call HIST_in( MFLX_cloudbase(:,:), 'CBMFX', 'cloud base mass flux', 'kg/m2/s', dt_CP )
       endif
    endif

    !$omp parallel do private(i,j,k) OMP_SCHEDULE_ collapse(2)
    do j  = JS, JE
    do i  = IS, IE
    do k  = KS, KE
       MOMZ_t(k,i,j) = MOMZ_t(k,i,j) + MOMZ_t_CP(k,i,j)
       MOMX_t(k,i,j) = MOMX_t(k,i,j) + MOMX_t_CP(k,i,j)
       MOMY_t(k,i,j) = MOMY_t(k,i,j) + MOMY_t_CP(k,i,j)
       RHOT_t(k,i,j) = RHOT_t(k,i,j) + RHOT_t_CP(k,i,j)
    enddo
    enddo
    enddo

    !$omp parallel do private(i,j,k) OMP_SCHEDULE_ collapse(3)
    do iq = 1, QA
    do j  = JS, JE
    do i  = IS, IE
    do k  = KS, KE
       QTRC_t(k,i,j,iq) = QTRC_t(k,i,j,iq) + QTRC_t_CP(k,i,j,iq)
    enddo
    enddo
    enddo
    enddo

    if ( STAT_checktotal ) then
       call STAT_total( total, MOMZ_t_CP(:,:,:), 'MOMZ_t_CP' )
       call STAT_total( total, MOMX_t_CP(:,:,:), 'MOMX_t_CP' )
       call STAT_total( total, MOMY_t_CP(:,:,:), 'MOMY_t_CP' )
       call STAT_total( total, RHOT_t_CP(:,:,:), 'RHOT_t_CP' )

       do iq = 1, QA
          RHOQ(:,:,:) = DENS(:,:,:) * QTRC_t_CP(:,:,:,iq)

          call STAT_total( total, RHOQ(:,:,:), trim(AQ_NAME(iq))//'_t_CP' )
       enddo
    endif

    return
  end subroutine ATMOS_PHY_CP_driver

end module mod_atmos_phy_cp_driver
