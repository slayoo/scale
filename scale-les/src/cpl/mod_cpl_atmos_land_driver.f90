!-------------------------------------------------------------------------------
!> module COUPLER / Atmosphere-Land Driver
!!
!! @par Description
!!          Coupler driver: atmosphere-land
!!
!! @author Team SCALE
!!
!! @par History
!! @li      2014-02-25 (T.Yamaura)  [new]
!<
!-------------------------------------------------------------------------------
module mod_cpl_atmos_land_driver
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mod_precision
  use mod_stdio
  use mod_grid_index
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: CPL_AtmLnd_driver_setup
  public :: CPL_AtmLnd_driver

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

  subroutine CPL_AtmLnd_driver_setup
    use mod_atmos_phy_sf_driver, only: &
       ATMOS_PHY_SF_driver_final
    use mod_land_phy_bucket, only: &
       LAND_PHY_driver_final
    use mod_cpl_atmos_land, only: &
       CPL_AtmLnd_setup
    use mod_cpl_vars, only: &
       CPL_TYPE_AtmLnd
    implicit none
    !---------------------------------------------------------------------------

    call ATMOS_PHY_SF_driver_final
    call LAND_PHY_driver_final

    call CPL_AtmLnd_setup( CPL_TYPE_AtmLnd )
    call CPL_AtmLnd_driver( .false. )

    return
  end subroutine CPL_AtmLnd_driver_setup

  subroutine CPL_AtmLnd_driver( update_flag )
    use mod_const, only: &
       LH0 => CONST_LH0
    use mod_grid_real, only: &
       CZ => REAL_CZ, &
       FZ => REAL_FZ
    use mod_cpl_atmos_land, only: &
       CPL_AtmLnd
    use mod_cpl_vars, only: &
       LST,              &
       DENS => CPL_DENS, &
       MOMX => CPL_MOMX, &
       MOMY => CPL_MOMY, &
       MOMZ => CPL_MOMZ, &
       RHOS => CPL_RHOS, &
       PRES => CPL_PRES, &
       ATMP => CPL_ATMP, &
       QV   => CPL_QV  , &
       PREC => CPL_PREC, &
       SWD  => CPL_SWD , &
       LWD  => CPL_LWD , &
       TG   => CPL_TG,   &
       QVEF => CPL_QVEF, &
       EMIT => CPL_EMIT, &
       ALBG => CPL_ALBG, &
       TCS  => CPL_TCS,  &
       DZG  => CPL_DZG,  &
       Z0M  => CPL_Z0M,  &
       Z0H  => CPL_Z0H,  &
       Z0E  => CPL_Z0E,  &
       AtmLnd_XMFLX,     &
       AtmLnd_YMFLX,     &
       AtmLnd_ZMFLX,     &
       AtmLnd_SWUFLX,    &
       AtmLnd_LWUFLX,    &
       AtmLnd_SHFLX,     &
       AtmLnd_LHFLX,     &
       AtmLnd_QVFLX,     &
       Lnd_GHFLX,        &
       Lnd_PRECFLX,      &
       Lnd_QVFLX,        &
       CNT_Atm_Lnd,      &
       CNT_Lnd
    implicit none

    ! argument
    logical, intent(in) :: update_flag

    ! work
    real(RP) :: XMFLX (IA,JA) ! x-momentum flux at the surface [kg/m2/s]
    real(RP) :: YMFLX (IA,JA) ! y-momentum flux at the surface [kg/m2/s]
    real(RP) :: ZMFLX (IA,JA) ! z-momentum flux at the surface [kg/m2/s]
    real(RP) :: SWUFLX(IA,JA) ! upward shortwave flux at the surface [W/m2]
    real(RP) :: LWUFLX(IA,JA) ! upward longwave flux at the surface [W/m2]
    real(RP) :: SHFLX (IA,JA) ! sensible heat flux at the surface [W/m2]
    real(RP) :: LHFLX (IA,JA) ! latent heat flux at the surface [W/m2]
    real(RP) :: GHFLX (IA,JA) ! ground heat flux at the surface [W/m2]

    real(RP) :: DZ    (IA,JA) ! height from the surface to the lowest atmospheric layer [m]
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*) '*** Coupler: Atmos-Land'

    DZ(:,:) = CZ(KS,:,:) - FZ(KS-1,:,:)

    call CPL_AtmLnd( &
      LST,                                 & ! (inout)
      update_flag,                         & ! (in)
      XMFLX, YMFLX, ZMFLX,                 & ! (out)
      SWUFLX, LWUFLX, SHFLX, LHFLX, GHFLX, & ! (out)
      DZ, DENS, MOMX, MOMY, MOMZ,          & ! (in)
      RHOS, PRES, ATMP, QV, SWD, LWD,      & ! (in)
      TG, QVEF, EMIT, ALBG,                & ! (in)
      TCS, DZG, Z0M, Z0H, Z0E              ) ! (in)

    ! average flux
    AtmLnd_XMFLX (:,:) = ( AtmLnd_XMFLX (:,:) * CNT_Atm_Lnd + XMFLX (:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    AtmLnd_YMFLX (:,:) = ( AtmLnd_YMFLX (:,:) * CNT_Atm_Lnd + YMFLX (:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    AtmLnd_ZMFLX (:,:) = ( AtmLnd_ZMFLX (:,:) * CNT_Atm_Lnd + ZMFLX (:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    AtmLnd_SWUFLX(:,:) = ( AtmLnd_SWUFLX(:,:) * CNT_Atm_Lnd + SWUFLX(:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    AtmLnd_LWUFLX(:,:) = ( AtmLnd_LWUFLX(:,:) * CNT_Atm_Lnd + LWUFLX(:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    AtmLnd_SHFLX (:,:) = ( AtmLnd_SHFLX (:,:) * CNT_Atm_Lnd + SHFLX (:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    AtmLnd_LHFLX (:,:) = ( AtmLnd_LHFLX (:,:) * CNT_Atm_Lnd + LHFLX (:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    AtmLnd_QVFLX (:,:) = ( AtmLnd_QVFLX (:,:) * CNT_Atm_Lnd + LHFLX (:,:)/LH0 ) / ( CNT_Atm_Lnd + 1.0_RP )

    Lnd_GHFLX  (:,:) = ( Lnd_GHFLX  (:,:) * CNT_Lnd + GHFLX(:,:)     ) / ( CNT_Lnd + 1.0_RP )
    Lnd_PRECFLX(:,:) = ( Lnd_PRECFLX(:,:) * CNT_Lnd + PREC (:,:)     ) / ( CNT_Lnd + 1.0_RP )
    Lnd_QVFLX  (:,:) = ( Lnd_QVFLX  (:,:) * CNT_Lnd - LHFLX(:,:)/LH0 ) / ( CNT_Lnd + 1.0_RP )

    CNT_Atm_Lnd = CNT_Atm_Lnd + 1.0_RP
    CNT_Lnd     = CNT_Lnd     + 1.0_RP

    return
  end subroutine CPL_AtmLnd_driver

end module mod_cpl_atmos_land_driver
