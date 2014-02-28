!-------------------------------------------------------------------------------
!> module LAND / Physics Bucket
!!
!! @par Description
!!          bucket-type land physics module
!!
!! @author Team SCALE
!! @li      2013-08-31 (T.Yamaura)  [new]
!<
!-------------------------------------------------------------------------------
module mod_land_phy_bucket
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mod_precision
  use mod_stdio
  use mod_prof
  use mod_grid_index
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: LAND_PHY_driver_setup
  public :: LAND_PHY_driver_first
  public :: LAND_PHY_driver_final

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
  real(RP), allocatable :: GHFLX  (:,:)
  real(RP), allocatable :: PRECFLX(:,:)
  real(RP), allocatable :: QVFLX  (:,:)

  ! limiter
  real(RP), private, parameter :: BETA_MAX = 1.0_RP

contains
  !-----------------------------------------------------------------------------
  !> Setup
  subroutine LAND_PHY_driver_setup
    use mod_process, only: &
       PRC_MPIstop
    use mod_land_vars, only: &
       LAND_TYPE_PHY
    implicit none

    logical  :: dummy

    NAMELIST / PARAM_LAND_BUCKET / &
       dummy

    integer :: ierr
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '+++ Module[BUCKET]/Categ[LAND]'

    allocate( GHFLX  (IA,JA) )
    allocate( PRECFLX(IA,JA) )
    allocate( QVFLX  (IA,JA) )

    if ( LAND_TYPE_PHY /= 'BUCKET' ) then
       if( IO_L ) write(IO_FID_LOG,*) 'xxx LAND_TYPE_PHY is not BUCKET. Check!'
       call PRC_MPIstop
    endif

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_LAND_BUCKET,iostat=ierr)

    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_LAND_BUCKET. Check!'
       call PRC_MPIstop
    endif
    if( IO_L ) write(IO_FID_LOG,nml=PARAM_LAND_BUCKET)

    return
  end subroutine LAND_PHY_driver_setup

  !-----------------------------------------------------------------------------
  !> Physical processes for land submodel
  subroutine LAND_PHY_driver_first
    use mod_const, only: &
       DWATR => CONST_DWATR, &
       CL    => CONST_CL
    use mod_time, only: &
       dt => TIME_DTSEC_LAND
    use mod_land_vars, only: &
       TG,                 &
       QVEF,               &
       ROFF,               &
       STRG,               &
       I_STRGMAX,          &
       I_STRGCRT,          &
       I_HCS,              &
       I_DZG,              &
       P => LAND_PROPERTY, &
       LAND_vars_fillhalo
    use mod_cpl_vars, only: &
       CPL_getCPL2Lnd
    implicit none

    integer :: i,j
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*) '*** Land step: Bucket'

    call CPL_getCPL2Lnd( GHFLX  (:,:), & ! [OUT]
                         PRECFLX(:,:), & ! [OUT]
                         QVFLX  (:,:)  ) ! [OUT]

    do j = JS, JE
    do i = IS, IE

      ! update water storage
      STRG(i,j) = STRG(i,j) + ( PRECFLX(i,j) + QVFLX(i,j) ) * dt

      if ( STRG(i,j) > P(i,j,I_STRGMAX) ) then
         ROFF(i,j) = ROFF(i,j) + STRG(i,j) - P(i,j,I_STRGMAX)
         STRG(i,j) = P(i,j,I_STRGMAX)
      endif

      ! update moisture efficiency
      QVEF(i,j) = min( STRG(i,j)/P(i,j,I_STRGCRT), BETA_MAX )

      ! update ground temperature
      TG(i,j) = TG(i,j) - 2.0_RP * GHFLX(i,j) &
              / ( ( 1.0_RP - P(i,j,I_STRGMAX) * 1.E-3_RP ) * P(i,j,I_HCS) + STRG(i,j) * 1.E-3_RP * DWATR * CL ) &
              / P(i,j,I_DZG) * dt

    end do
    end do

    call LAND_vars_fillhalo

    return
  end subroutine LAND_PHY_driver_first

  subroutine LAND_PHY_driver_final
    use mod_land_vars, only: &
       TG,                 &
       QVEF,               &
       I_EMIT,             &
       I_ALBG,             &
       I_TCS,              &
       I_DZG,              &
       I_Z0M,              &
       I_Z0H,              &
       I_Z0E,              &
       P => LAND_PROPERTY
    use mod_cpl_vars, only: &
       CPL_putLnd
    implicit none
    !---------------------------------------------------------------------------

    call CPL_putLnd( TG  (:,:),        & ! [IN]
                     QVEF(:,:),        & ! [IN]
                     P   (:,:,I_EMIT), & ! [IN]
                     P   (:,:,I_ALBG), & ! [IN]
                     P   (:,:,I_TCS),  & ! [IN]
                     P   (:,:,I_DZG),  & ! [IN]
                     P   (:,:,I_Z0M),  & ! [IN]
                     P   (:,:,I_Z0H),  & ! [IN]
                     P   (:,:,I_Z0E)   ) ! [IN]

    return
  end subroutine LAND_PHY_driver_final

end module mod_land_phy_bucket
