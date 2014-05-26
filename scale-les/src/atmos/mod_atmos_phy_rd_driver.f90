!-------------------------------------------------------------------------------
!> module ATMOSPHERE / Physics Radiation
!!
!! @par Description
!!          Atmospheric radiation transfer process driver
!!
!! @author Team SCALE
!!
!! @par History
!! @li      2013-12-06 (S.Nishizawa)  [new]
!<
!-------------------------------------------------------------------------------
#include "inc_openmp.h"
module mod_atmos_phy_rd_driver
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
  public :: ATMOS_PHY_RD_driver_setup
  public :: ATMOS_PHY_RD_driver

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
  subroutine ATMOS_PHY_RD_driver_setup
    use scale_atmos_phy_rd, only: &
       ATMOS_PHY_RD_setup
    use mod_atmos_admin, only: &
       ATMOS_PHY_RD_TYPE, &
       ATMOS_sw_phy_rd
    use mod_atmos_phy_rd_vars, only: &
       SFLX_LW_up   => ATMOS_PHY_RD_SFLX_LW_up,   &
       SFLX_LW_dn   => ATMOS_PHY_RD_SFLX_LW_dn,   &
       SFLX_SW_up   => ATMOS_PHY_RD_SFLX_SW_up,   &
       SFLX_SW_dn   => ATMOS_PHY_RD_SFLX_SW_dn,   &
       TOAFLX_LW_up => ATMOS_PHY_RD_TOAFLX_LW_up, &
       TOAFLX_LW_dn => ATMOS_PHY_RD_TOAFLX_LW_dn, &
       TOAFLX_SW_up => ATMOS_PHY_RD_TOAFLX_SW_up, &
       TOAFLX_SW_dn => ATMOS_PHY_RD_TOAFLX_SW_dn
    implicit none
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '++++++ Module[DRIVER] / Categ[ATMOS PHY_RD] / Origin[SCALE-LES]'

    if ( ATMOS_sw_phy_rd ) then

       ! setup library component
       call ATMOS_PHY_RD_setup( ATMOS_PHY_RD_TYPE )

       ! run once (only for the diagnostic value)
       call ATMOS_PHY_RD_driver( .true., .false. )

    else

       if( IO_L ) write(IO_FID_LOG,*) '*** ATMOS_PHY_RD is disabled.'
       if( IO_L ) write(IO_FID_LOG,*) '*** radiation fluxes are set to zero.'
       SFLX_LW_up  (:,:) = 0.0_RP
       SFLX_LW_dn  (:,:) = 0.0_RP
       SFLX_SW_up  (:,:) = 0.0_RP
       SFLX_SW_dn  (:,:) = 0.0_RP
       TOAFLX_LW_up(:,:) = 0.0_RP
       TOAFLX_LW_dn(:,:) = 0.0_RP
       TOAFLX_SW_up(:,:) = 0.0_RP
       TOAFLX_SW_dn(:,:) = 0.0_RP

    endif

    return
  end subroutine ATMOS_PHY_RD_driver_setup

  !-----------------------------------------------------------------------------
  !> Driver
  subroutine ATMOS_PHY_RD_driver( update_flag, history_flag )
    use scale_grid_real, only: &
       REAL_CZ,  &
       REAL_FZ,  &
       REAL_LON, &
       REAL_LAT
    use scale_landuse, only: &
       LANDUSE_frac_land
    use scale_time, only: &
       dt_RD => TIME_DTSEC_ATMOS_PHY_RD, &
       TIME_NOWDATE
    use scale_stats, only: &
       STAT_checktotal, &
       STAT_total
    use scale_history, only: &
       HIST_in
    use scale_atmos_solarins, only: &
       SOLARINS_insolation => ATMOS_SOLARINS_insolation
    use scale_atmos_phy_rd, only: &
       ATMOS_PHY_RD
    use scale_atmos_phy_rd_common, only: &
       RD_heating => ATMOS_PHY_RD_heating, &
       I_SW, &
       I_LW, &
       I_dn, &
       I_up
    use mod_atmos_vars, only: &
       DENS,              &
       RHOT,              &
       QTRC,              &
       RHOT_t => RHOT_tp
    use mod_atmos_phy_sf_vars, only: &
       SFC_TEMP        => ATMOS_PHY_SF_SFC_TEMP,  &
       SFC_albedo_land => ATMOS_PHY_SF_SFC_albedo_land
    use mod_atmos_phy_rd_vars, only: &
       RHOT_t_RD    => ATMOS_PHY_RD_RHOT_t,       &
       SFLX_LW_up   => ATMOS_PHY_RD_SFLX_LW_up,   &
       SFLX_LW_dn   => ATMOS_PHY_RD_SFLX_LW_dn,   &
       SFLX_SW_up   => ATMOS_PHY_RD_SFLX_SW_up,   &
       SFLX_SW_dn   => ATMOS_PHY_RD_SFLX_SW_dn,   &
       TOAFLX_LW_up => ATMOS_PHY_RD_TOAFLX_LW_up, &
       TOAFLX_LW_dn => ATMOS_PHY_RD_TOAFLX_LW_dn, &
       TOAFLX_SW_up => ATMOS_PHY_RD_TOAFLX_SW_up, &
       TOAFLX_SW_dn => ATMOS_PHY_RD_TOAFLX_SW_dn
    use mod_cpl_vars, only: &
       sw_CPL => CPL_sw_ALL, &
       CPL_getATM_RD
    implicit none

    logical, intent(in) :: update_flag
    logical, intent(in) :: history_flag

    real(RP) :: TEMP_t(KA,IA,JA,3)

    real(RP) :: flux_rad(KA,IA,JA,2,2)
    real(RP) :: flux_net(KA,IA,JA,2)
    real(RP) :: flux_up (KA,IA,JA,2)
    real(RP) :: flux_dn (KA,IA,JA,2)

    real(RP) :: flux_rad_top(IA,JA,2)
    real(RP) :: flux_rad_sfc(IA,JA,2)

    real(RP) :: solins(IA,JA)
    real(RP) :: cosSZA(IA,JA)

    real(RP) :: total ! dummy

    integer :: k, i, j
    !---------------------------------------------------------------------------

    if ( update_flag ) then

       if( IO_L ) write(IO_FID_LOG,*) '*** Physics step, radiation'

       if ( sw_CPL ) then
          call CPL_getATM_RD( SFC_TEMP       (:,:),  & ! [OUT]
                              SFC_albedo_land(:,:,:) ) ! [OUT]
       endif

       ! calc solar insolation
       call SOLARINS_insolation( solins  (:,:),  & ! [OUT]
                                 cosSZA  (:,:),  & ! [OUT]
                                 REAL_LON(:,:),  & ! [IN]
                                 REAL_LAT(:,:),  & ! [IN]
                                 TIME_NOWDATE(:) ) ! [IN]

       call ATMOS_PHY_RD( DENS, RHOT, QTRC,  & ! [IN]
                          REAL_CZ, REAL_FZ,  & ! [IN]
                          LANDUSE_frac_land, & ! [IN]
                          SFC_TEMP,          & ! [IN]
                          SFC_albedo_land,   & ! [IN]
                          solins, cosSZA,    & ! [IN]
                          flux_rad,          & ! [OUT]
                          flux_rad_top       ) ! [OUT]

       ! apply radiative flux convergence -> heating rate
       call RD_heating( flux_rad (:,:,:,:,:), & ! [IN]
                        RHOT     (:,:,:),     & ! [IN]
                        QTRC     (:,:,:,:),   & ! [IN]
                        REAL_FZ  (:,:,:),     & ! [IN]
                        dt_RD,                & ! [IN]
                        TEMP_t   (:,:,:,:),   & ! [OUT]
                        RHOT_t_RD(:,:,:)      ) ! [OUT]

       do j = JS, JE
       do i = IS, IE
          SFLX_LW_up(i,j) = flux_rad(KS-1,i,j,I_LW,I_up)
          SFLX_LW_dn(i,j) = flux_rad(KS-1,i,j,I_LW,I_dn)
          SFLX_SW_up(i,j) = flux_rad(KS-1,i,j,I_SW,I_up)
          SFLX_SW_dn(i,j) = flux_rad(KS-1,i,j,I_SW,I_dn)

          TOAFLX_LW_up(i,j) = flux_rad(KE,i,j,I_LW,I_up)
          TOAFLX_LW_dn(i,j) = flux_rad(KE,i,j,I_LW,I_dn)
          TOAFLX_SW_up(i,j) = flux_rad(KE,i,j,I_SW,I_up)
          TOAFLX_SW_dn(i,j) = flux_rad(KE,i,j,I_SW,I_dn)
       enddo
       enddo

       if ( history_flag ) then

          call HIST_in( solins(:,:), 'SOLINS', 'solar insolation',        'W/m2', dt_RD )
          call HIST_in( cosSZA(:,:), 'COSZ',   'cos(solar zenith angle)', '0-1',  dt_RD )

          do j = JS, JE
          do i = IS, IE
          do k = KS, KE
             flux_net(k,i,j,I_LW) = 0.5_RP * ( ( flux_rad(k-1,i,j,I_LW,I_up) - flux_rad(k-1,i,j,I_LW,I_dn) ) &
                                             + ( flux_rad(k  ,i,j,I_LW,I_up) - flux_rad(k  ,i,j,I_LW,I_dn) ) )
             flux_net(k,i,j,I_SW) = 0.5_RP * ( ( flux_rad(k-1,i,j,I_SW,I_up) - flux_rad(k-1,i,j,I_SW,I_dn) ) &
                                             + ( flux_rad(k  ,i,j,I_SW,I_up) - flux_rad(k  ,i,j,I_SW,I_dn) ) )

             flux_up (k,i,j,I_LW) = 0.5_RP * ( flux_rad(k-1,i,j,I_LW,I_up) + flux_rad(k,i,j,I_LW,I_up) )
             flux_up (k,i,j,I_SW) = 0.5_RP * ( flux_rad(k-1,i,j,I_SW,I_up) + flux_rad(k,i,j,I_SW,I_up) )
             flux_dn (k,i,j,I_LW) = 0.5_RP * ( flux_rad(k-1,i,j,I_LW,I_dn) + flux_rad(k,i,j,I_LW,I_dn) )
             flux_dn (k,i,j,I_SW) = 0.5_RP * ( flux_rad(k-1,i,j,I_SW,I_dn) + flux_rad(k,i,j,I_SW,I_dn) )
          enddo
          enddo
          enddo
          call HIST_in( flux_net(:,:,:,I_LW), 'RADFLUX_LW',  'net radiation flux(LW)', 'W/m2', dt_RD )
          call HIST_in( flux_net(:,:,:,I_SW), 'RADFLUX_SW',  'net radiation flux(SW)', 'W/m2', dt_RD )
          call HIST_in( flux_up (:,:,:,I_LW), 'RADFLUX_LWUP', 'up radiation flux(LW)', 'W/m2', dt_RD )
          call HIST_in( flux_up (:,:,:,I_SW), 'RADFLUX_SWUP', 'up radiation flux(SW)', 'W/m2', dt_RD )
          call HIST_in( flux_dn (:,:,:,I_LW), 'RADFLUX_LWDN', 'dn radiation flux(LW)', 'W/m2', dt_RD )
          call HIST_in( flux_dn (:,:,:,I_SW), 'RADFLUX_SWDN', 'dn radiation flux(SW)', 'W/m2', dt_RD )

          call HIST_in( flux_rad_top(:,:,I_LW), 'OLR', 'TOA     longwave  radiation', 'W/m2', dt_RD )
          call HIST_in( flux_rad_top(:,:,I_SW), 'OSR', 'TOA     shortwave radiation', 'W/m2', dt_RD )
          do j = JS, JE
          do i = IS, IE
             flux_rad_sfc(i,j,I_LW) = flux_rad(KS-1,i,j,I_LW,I_up)-flux_rad(KS-1,i,j,I_LW,I_dn)
             flux_rad_sfc(i,j,I_SW) = flux_rad(KS-1,i,j,I_SW,I_up)-flux_rad(KS-1,i,j,I_SW,I_dn)
          enddo
          enddo
          call HIST_in( flux_rad_sfc(:,:,I_LW), 'SLR', 'Surface longwave  radiation', 'W/m2', dt_RD )
          call HIST_in( flux_rad_sfc(:,:,I_SW), 'SSR', 'Surface shortwave radiation', 'W/m2', dt_RD )

          call HIST_in( TEMP_t(:,:,:,I_LW), 'TEMP_t_rd_LW', 'tendency of temp in rd(LW)', 'K/day', dt_RD )
          call HIST_in( TEMP_t(:,:,:,I_SW), 'TEMP_t_rd_SW', 'tendency of temp in rd(SW)', 'K/day', dt_RD )
          call HIST_in( TEMP_t(:,:,:,3   ), 'TEMP_t_rd',    'tendency of temp in rd',     'K/day', dt_RD )
       endif
    endif

    do j = JS, JE
    do i = IS, IE
    do k = KS, KE
       RHOT_t(k,i,j) = RHOT_t(k,i,j) + RHOT_t_RD(k,i,j)
    enddo
    enddo
    enddo

    if ( STAT_checktotal ) then
       call STAT_total( total, RHOT_t_RD(:,:,:), 'RHOT_t_RD' )
    endif

    return
  end subroutine ATMOS_PHY_RD_driver

end module mod_atmos_phy_rd_driver
