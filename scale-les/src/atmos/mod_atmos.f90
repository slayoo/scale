!-------------------------------------------------------------------------------
!> module ATMOSPHERE driver
!!
!! @par Description
!!          Atmosphere module
!!
!! @author Team SCALE
!!
!! @par History
!! @li      2011-11-11 (H.Yashiro) [new]
!! @li      2012-02-15 (H.Yashiro) [add] Microphysics
!! @li      2012-03-23 (H.Yashiro) [mod] Cleaning
!! @li      2013-08-31 (T.Yamaura) [add] Coupler
!!
!<
!-------------------------------------------------------------------------------
module mod_atmos
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mod_precision
  use mod_stdio, only: &
     IO_FID_LOG,  &
     IO_L
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
  public :: ATMOS_setup
  public :: ATMOS_step

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
  !> Setup atmosphere
  !-----------------------------------------------------------------------------
  subroutine ATMOS_setup
    use mod_atmos_hydrostatic, only: &
       ATMOS_HYDROSTATIC_setup
    use mod_atmos_thermodyn, only: &
       ATMOS_THERMODYN_setup
    use mod_atmos_saturation, only: &
       ATMOS_SATURATION_setup
    use mod_atmos_vars, only: &
       ATMOS_DYN_TYPE, &
       ATMOS_PHY_SF_TYPE, &
       ATMOS_PHY_TB_TYPE, &
       ATMOS_PHY_MP_TYPE, &
       ATMOS_PHY_RD_TYPE, &
       ATMOS_PHY_AE_TYPE, &
       ATMOS_PHY_CH_TYPE, &
       DENS, &
       MOMZ, &
       MOMX, &
       MOMY, &
       RHOT, &
       QTRC, &
       DENS_tp, &
       MOMZ_tp, &
       MOMX_tp, &
       MOMY_tp, &
       RHOT_tp, &
       QTRC_tp, &
       sw_dyn    => ATMOS_sw_dyn,    &
       sw_phy_sf => ATMOS_sw_phy_sf, &
       sw_phy_tb => ATMOS_sw_phy_tb, &
       sw_phy_mp => ATMOS_sw_phy_mp, &
       sw_phy_rd => ATMOS_sw_phy_rd, &
       sw_phy_ae => ATMOS_sw_phy_ae, &
       ATMOS_vars_setup,  &
       ATMOS_vars_restart_read
    use mod_atmos_vars_sf, only: &
       ATMOS_vars_sf_setup
    use mod_atmos_refstate, only: &
       ATMOS_REFSTATE_setup
    use mod_atmos_boundary, only: &
       ATMOS_BOUNDARY_setup
    use mod_atmos_dyn_wrap, only: &
       ATMOS_DYN_setup => ATMOS_DYN_wrap_setup
    use mod_atmos_phy_sf_wrap, only: &
       ATMOS_PHY_SF_setup => ATMOS_PHY_SF_wrap_setup
    use mod_atmos_phy_tb_wrap, only: &
       ATMOS_PHY_TB_setup => ATMOS_PHY_TB_wrap_setup
    use mod_atmos_phy_mp_wrap, only: &
       ATMOS_PHY_MP_setup => ATMOS_PHY_MP_wrap_setup
    use mod_atmos_phy_rd_wrap, only: &
       ATMOS_PHY_RD_setup => ATMOS_PHY_RD_wrap_setup
    use mod_atmos_phy_ae_wrap, only: &
       ATMOS_PHY_AE_setup => ATMOS_PHY_AE_wrap_setup
    implicit none
    !---------------------------------------------------------------------------

    ! setup common tools
    call ATMOS_HYDROSTATIC_setup
    call ATMOS_THERMODYN_setup
    call ATMOS_SATURATION_setup

    ! setup variable container
    call ATMOS_vars_setup

    call ATMOS_vars_sf_setup

    ! read restart
    call ATMOS_vars_restart_read

    call ATMOS_REFSTATE_setup( DENS, RHOT, QTRC ) ! (in)

    call ATMOS_BOUNDARY_setup( &
         DENS, MOMZ, MOMX, MOMY, RHOT, QTRC ) ! (in)

    ! setup each components
    if ( sw_dyn    ) call ATMOS_DYN_setup( ATMOS_DYN_TYPE )

    if ( sw_phy_sf ) call ATMOS_PHY_SF_setup( ATMOS_PHY_SF_TYPE )

    if ( sw_phy_tb ) call ATMOS_PHY_TB_setup( ATMOS_PHY_TB_TYPE )

    if ( sw_phy_mp ) call ATMOS_PHY_MP_setup( ATMOS_PHY_MP_TYPE )

    if ( sw_phy_rd .or. sw_phy_ae ) call ATMOS_PHY_AE_setup( ATMOS_PHY_AE_TYPE )

    if ( sw_phy_rd ) call ATMOS_PHY_RD_setup( ATMOS_PHY_RD_TYPE )

    !########## initialize tendencies ##########
!OCL XFILL
    DENS_tp(:,:,:) = 0.0_RP
!OCL XFILL
    MOMZ_tp(:,:,:) = 0.0_RP
!OCL XFILL
    MOMX_tp(:,:,:) = 0.0_RP
!OCL XFILL
    MOMY_tp(:,:,:) = 0.0_RP
!OCL XFILL
    RHOT_tp(:,:,:) = 0.0_RP
!OCL XFILL
    QTRC_tp(:,:,:,:) = 0.0_RP

    return

  end subroutine ATMOS_setup

  !-----------------------------------------------------------------------------
  !> advance atmospheric state
  !-----------------------------------------------------------------------------
  subroutine ATMOS_step
    use mod_time, only: &
       do_dyn        => TIME_DOATMOS_DYN,    &
       do_phy_sf     => TIME_DOATMOS_PHY_SF, &
       do_phy_tb     => TIME_DOATMOS_PHY_TB, &
       do_phy_mp     => TIME_DOATMOS_PHY_MP, &
       do_phy_rd     => TIME_DOATMOS_PHY_RD, &
       do_phy_ae     => TIME_DOATMOS_PHY_AE
    use mod_atmos_vars, only: &
       DENS,    &
       MOMX,    &
       MOMY,    &
       MOMZ,    &
       RHOT,    &
       QTRC,    &
       DENS_tp, &
       MOMZ_tp, &
       MOMX_tp, &
       MOMY_tp, &
       RHOT_tp, &
       QTRC_tp, &
       sw_dyn        => ATMOS_sw_dyn,        &
       sw_phy_sf     => ATMOS_sw_phy_sf,     &
       sw_phy_tb     => ATMOS_sw_phy_tb,     &
       sw_phy_mp     => ATMOS_sw_phy_mp,     &
       sw_phy_rd     => ATMOS_sw_phy_rd,     &
       sw_phy_ae     => ATMOS_sw_phy_ae,     &
       ATMOS_vars_history
    use mod_atmos_vars_sf, only: &
       PREC,       &
       SWD,        &
       LWD,        &
       SFLX_MOMX,  &
       SFLX_MOMY,  &
       SFLX_MOMZ,  &
       SFLX_SWU,   &
       SFLX_LWU,   &
       SFLX_SH,    &
       SFLX_LH,    &
       SFLX_QVAtm
    use mod_atmos_dyn_wrap, only: &
       ATMOS_DYN => ATMOS_DYN_wrap
    use mod_atmos_phy_sf_wrap, only: &
       ATMOS_PHY_SF => ATMOS_PHY_SF_wrap, &
       ATMOS_PHY_SF_CPL
    use mod_atmos_phy_tb_wrap, only: &
       ATMOS_PHY_TB => ATMOS_PHY_TB_wrap
    use mod_atmos_phy_mp_wrap, only: &
       ATMOS_PHY_MP => ATMOS_PHY_MP_wrap
    use mod_atmos_phy_rd_wrap, only: &
       ATMOS_PHY_RD => ATMOS_PHY_RD_wrap
    use mod_atmos_phy_ae_wrap, only: &
       ATMOS_PHY_AE => ATMOS_PHY_AE_wrap
    use mod_atmos_refstate, only: &
       ATMOS_REFSTATE_update, &
       ATMOS_REFSTATE_UPDATE_FLAG
    use mod_cpl_vars, only: &
       CPL_putAtm,     &
       CPL_getCPL2Atm, &
       sw_AtmLnd => CPL_sw_AtmLnd
    implicit none
    !---------------------------------------------------------------------------

    !########## Reference State ###########
    if ( ATMOS_REFSTATE_UPDATE_FLAG ) then
       call ATMOS_REFSTATE_update( DENS, RHOT, QTRC ) ! (in)
    endif

    !########## from Coupler ##########
    if ( sw_AtmLnd ) then
       call CPL_getCPL2Atm( &
          SFLX_MOMX, SFLX_MOMY, SFLX_MOMZ, SFLX_SWU, SFLX_LWU, &
          SFLX_SH, SFLX_LH, SFLX_QVAtm                         )
    endif

    !########## Surface Flux ##########
    if ( sw_phy_sf ) then
       call TIME_rapstart('ATM SurfaceFlux')
       if ( sw_AtmLnd ) then
          call ATMOS_PHY_SF_CPL
       else
          call ATMOS_PHY_SF( do_phy_sf, .true. )
       endif
       call TIME_rapend  ('ATM SurfaceFlux')
    endif

    !########## Turbulence ##########
    if ( sw_phy_tb ) then
       call TIME_rapstart('ATM Turbulence')
       call ATMOS_PHY_TB( do_phy_tb, .true. )
       call TIME_rapend  ('ATM Turbulence')
    endif

    !########## Microphysics ##########
    if ( sw_phy_mp ) then
       call TIME_rapstart('ATM Microphysics')
       call ATMOS_PHY_MP( do_phy_mp, .true. )
       call TIME_rapend  ('ATM Microphysics')
    endif

    !########## Aerosol ##########
    if ( sw_phy_ae ) then
       call TIME_rapstart('ATM Aerosol')
       call ATMOS_PHY_AE( do_phy_ae, .true. )
       call TIME_rapend  ('ATM Aerosol')
    endif

    !########## Radiation ##########
    if ( sw_phy_rd ) then
       call TIME_rapstart('ATM Radiation')
       call ATMOS_PHY_RD( do_phy_rd, .true. )
       call TIME_rapend  ('ATM Radiation')
    endif

    !########## Dynamics ##########
    if ( sw_dyn ) then
       call TIME_rapstart('ATM Dynamics')
       call ATMOS_DYN( do_dyn )
       call TIME_rapend  ('ATM Dynamics')
    endif

    !########## History & Monitor ##########
    call TIME_rapstart('ATM History Vars')
       call ATMOS_vars_history
    call TIME_rapend  ('ATM History Vars')

    !########## to Coupler ##########
    if ( sw_AtmLnd ) then
       call CPL_putATM( &
          DENS, MOMX, MOMY, MOMZ,    &
          RHOT, QTRC, PREC, SWD, LWD )
    endif

    !########## reset tendencies ##########
!OCL XFILL
    DENS_tp(:,:,:) = 0.0_RP
!OCL XFILL
    MOMZ_tp(:,:,:) = 0.0_RP
!OCL XFILL
    MOMX_tp(:,:,:) = 0.0_RP
!OCL XFILL
    MOMY_tp(:,:,:) = 0.0_RP
!OCL XFILL
    RHOT_tp(:,:,:) = 0.0_RP
!OCL XFILL
    QTRC_tp(:,:,:,:) = 0.0_RP

    return
  end subroutine ATMOS_step

end module mod_atmos