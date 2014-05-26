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
  use scale_precision
  use scale_stdio
  use scale_grid_index
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
    use mod_atmos_driver, only: &
       ATMOS_SURFACE_SET
    use mod_land_phy_bucket, only: &
       LAND_PHY_driver_final
    use scale_cpl_atmos_land, only: &
       CPL_AtmLnd_setup
    use mod_cpl_vars, only: &
       CPL_TYPE_AtmLnd
    implicit none
    !---------------------------------------------------------------------------

    call ATMOS_SURFACE_SET
    call LAND_PHY_driver_final

    call CPL_AtmLnd_setup( CPL_TYPE_AtmLnd )
    call CPL_AtmLnd_driver( .false. )

    return
  end subroutine CPL_AtmLnd_driver_setup

  subroutine CPL_AtmLnd_driver( update_flag )
    use scale_const, only: &
       LH0  => CONST_LH0,  &
       I_SW => CONST_I_SW, &
       I_LW => CONST_I_LW
    use scale_cpl_atmos_land, only: &
       CPL_AtmLnd
    use mod_cpl_vars, only: &
       LST,               &
       ALBG,              &
       DENS => CPL_DENS,  &
       MOMX => CPL_MOMX,  &
       MOMY => CPL_MOMY,  &
       MOMZ => CPL_MOMZ,  &
       RHOS => CPL_RHOS,  &
       PRES => CPL_PRES,  &
       TMPS => CPL_TMPS,  &
       QV   => CPL_QV  ,  &
       PREC => CPL_PREC,  &
       SWD  => CPL_SWD ,  &
       LWD  => CPL_LWD ,  &
       TG   => CPL_TG,    &
       QVEF => CPL_QVEF,  &
       TCS  => CPL_TCS,   &
       DZG  => CPL_DZG,   &
       Z0M  => CPL_Z0M,   &
       Z0H  => CPL_Z0H,   &
       Z0E  => CPL_Z0E,   &
       CPL_AtmLnd_XMFLX,  &
       CPL_AtmLnd_YMFLX,  &
       CPL_AtmLnd_ZMFLX,  &
       CPL_AtmLnd_SHFLX,  &
       CPL_AtmLnd_LHFLX,  &
       CPL_AtmLnd_QVFLX,  &
       Lnd_GHFLX,         &
       Lnd_PRECFLX,       &
       Lnd_QVFLX,         &
       CNT_Atm_Lnd,       &
       CNT_Lnd
    implicit none

    ! argument
    logical, intent(in) :: update_flag

    ! work
    integer :: i, j

    real(RP) :: XMFLX (IA,JA) ! x-momentum flux at the surface [kg/m2/s]
    real(RP) :: YMFLX (IA,JA) ! y-momentum flux at the surface [kg/m2/s]
    real(RP) :: ZMFLX (IA,JA) ! z-momentum flux at the surface [kg/m2/s]
    real(RP) :: SHFLX (IA,JA) ! sensible heat flux at the surface [W/m2]
    real(RP) :: LHFLX (IA,JA) ! latent heat flux at the surface [W/m2]
    real(RP) :: GHFLX (IA,JA) ! ground heat flux at the surface [W/m2]

    real(RP) :: tmpX(IA,JA) ! temporary XMFLX [kg/m2/s]
    real(RP) :: tmpY(IA,JA) ! temporary YMFLX [kg/m2/s]
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*) '*** Coupler: Atmos-Land'

    call CPL_AtmLnd( &
      LST  (:,:),      & ! (inout)
      XMFLX(:,:),      & ! (out)
      YMFLX(:,:),      & ! (out)
      ZMFLX(:,:),      & ! (out)
      SHFLX(:,:),      & ! (out)
      LHFLX(:,:),      & ! (out)
      GHFLX(:,:),      & ! (out)
      update_flag,     & ! (in)
      DENS (:,:),      & ! (in)
      MOMX (:,:),      & ! (in)
      MOMY (:,:),      & ! (in)
      MOMZ (:,:),      & ! (in)
      RHOS (:,:),      & ! (in)
      PRES (:,:),      & ! (in)
      TMPS (:,:),      & ! (in)
      QV   (:,:),      & ! (in)
      SWD  (:,:),      & ! (in)
      LWD  (:,:),      & ! (in)
      TG   (:,:),      & ! (in)
      QVEF (:,:),      & ! (in)
      ALBG (:,:,I_SW), & ! (in)
      ALBG (:,:,I_LW), & ! (in)
      TCS  (:,:),      & ! (in)
      DZG  (:,:),      & ! (in)
      Z0M  (:,:),      & ! (in)
      Z0H  (:,:),      & ! (in)
      Z0E  (:,:)       ) ! (in)

    ! interpolate momentum fluxes
    do j = JS, JE
    do i = IS, IE
      tmpX(i,j) = ( XMFLX(i,j) + XMFLX(i+1,j  ) ) * 0.5_RP ! at u/y-layer
      tmpY(i,j) = ( YMFLX(i,j) + YMFLX(i,  j+1) ) * 0.5_RP ! at x/v-layer
    enddo
    enddo

    do j = JS, JE
    do i = IS, IE
      XMFLX(i,j) = tmpX(i,j)
      YMFLX(i,j) = tmpY(i,j)
      ZMFLX(i,j) = ZMFLX(i,j) * 0.5_RP ! at w-layer
    enddo
    enddo

    ! temporal average flux
    CPL_AtmLnd_XMFLX(:,:) = ( CPL_AtmLnd_XMFLX(:,:) * CNT_Atm_Lnd + XMFLX(:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    CPL_AtmLnd_YMFLX(:,:) = ( CPL_AtmLnd_YMFLX(:,:) * CNT_Atm_Lnd + YMFLX(:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    CPL_AtmLnd_ZMFLX(:,:) = ( CPL_AtmLnd_ZMFLX(:,:) * CNT_Atm_Lnd + ZMFLX(:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    CPL_AtmLnd_SHFLX(:,:) = ( CPL_AtmLnd_SHFLX(:,:) * CNT_Atm_Lnd + SHFLX(:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    CPL_AtmLnd_LHFLX(:,:) = ( CPL_AtmLnd_LHFLX(:,:) * CNT_Atm_Lnd + LHFLX(:,:)     ) / ( CNT_Atm_Lnd + 1.0_RP )
    CPL_AtmLnd_QVFLX(:,:) = ( CPL_AtmLnd_QVFLX(:,:) * CNT_Atm_Lnd + LHFLX(:,:)/LH0 ) / ( CNT_Atm_Lnd + 1.0_RP )

    Lnd_GHFLX  (:,:) = ( Lnd_GHFLX  (:,:) * CNT_Lnd + GHFLX(:,:)     ) / ( CNT_Lnd + 1.0_RP )
    Lnd_PRECFLX(:,:) = ( Lnd_PRECFLX(:,:) * CNT_Lnd + PREC (:,:)     ) / ( CNT_Lnd + 1.0_RP )
    Lnd_QVFLX  (:,:) = ( Lnd_QVFLX  (:,:) * CNT_Lnd - LHFLX(:,:)/LH0 ) / ( CNT_Lnd + 1.0_RP )

    CNT_Atm_Lnd = CNT_Atm_Lnd + 1.0_RP
    CNT_Lnd     = CNT_Lnd     + 1.0_RP

    return
  end subroutine CPL_AtmLnd_driver

end module mod_cpl_atmos_land_driver
