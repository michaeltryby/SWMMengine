!*---------------------------------------------------------------------------*!
!    |
!    | SWMM Engine: Storm Water Management Model
!    | Website:  https://ehsanmadadi.com
!    | Copyright (C) 2018-2020 Ehsan Madadi-Kandjani
!-------------------------------------------------------------------------------
!License
!    This file is part of SWMM Engine.
!    SWMM Engine is free software: you can redistribute it and/or modify it
!    under the terms of the GNU General Public License as published by
!    the Free Software Foundation, either version 3 of the License, or
!    (at your option) any later version.
!    SWMM Engine is distributed in the hope that it will be useful, but WITHOUT
!    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
!    FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
!    for more details.
!    You should have received a copy of the GNU General Public License
!    along with SWMM Engine.  If not, see <http://www.gnu.org/licenses/>.
!*---------------------------------------------------------------------------*!
!
! module case_simple_channel
!
! Custom test case for a simple channel created with one link and two nodes
! Used in conjunction with test_cases module for custom setup.
!
!==========================================================================
!
 module case_simple_channel
! 
    use allocate_storage
    use array_index
    use bc
    use data_keys
    use globals
    use setting_definition

    implicit none
    
    private
    
    public :: case_simple_channel_initialize

    integer :: debuglevel = 0
    
 contains
!
!========================================================================== 
!==========================================================================
!
 subroutine case_simple_channel_initialize &
    (channel_length, channel_breadth, channel_topwidth, subdivide_length, &
    lowerZ, upperZ, initial_flowrate, init_depth, depth_upstream, &
    depth_dnstream, ManningsN, roughness_type, idepth_type,             &
    linkR, nodeR, linkI, nodeI, linkYN, nodeYN, linkName, nodeName,     &
    bcdataDn, bcdataUp)
!
! initialize the link-node system and boundary conditions for a simple channel
! 
 character(64) :: subroutine_name = 'case_simple_channel_initialize'
 
 real,  intent(in)  :: channel_length, channel_breadth
 real,  intent(in)  :: channel_topwidth, subdivide_length
 real,  intent(in)  :: lowerZ, upperZ, ManningsN, initial_flowrate
 real,  intent(in)  :: depth_upstream, depth_dnstream, init_depth
 
 integer, intent(in):: roughness_type, idepth_type
 
 integer,   dimension(:,:), allocatable, target, intent(out)    :: linkI 
 integer,   dimension(:,:), allocatable, target, intent(out)    :: nodeI
 
 real,      dimension(:,:), allocatable, target, intent(out)    :: linkR 
 real,      dimension(:,:), allocatable, target, intent(out)    :: nodeR 
 
 logical,   dimension(:,:), allocatable, target, intent(out)    :: linkYN
 logical,   dimension(:,:), allocatable, target, intent(out)    :: nodeYN
 
 type(string), dimension(:), allocatable, target, intent(out)   :: linkName 
 type(string), dimension(:), allocatable, target, intent(out)   :: nodeName
 
 type(bcType), dimension(:), allocatable, intent(out) :: bcdataUp, bcdataDn

 integer    :: ntimepoint, ndnstreamBC, nupstreamBC
 
 
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name 
 
! Boundary conditions
 ntimepoint = 2
 nupstreamBC = 1
 ndnstreamBC = 1
 
! check if  
 
 call bc_allocate &
    (bcdataDn, bcdataUp, ndnstreamBC, nupstreamBC, ntimepoint) 

! assign values
! downstream is default to elevation
 bcdataDn(1)%NodeID = 2
 bcdataDn(1)%TimeArray(1)     = setting%Time%StartTime 
 bcdataDn(1)%TimeArray(2)     = setting%Time%EndTime + 100.0 !s
 bcdataDn(1)%ValueArray(1)    = lowerZ +  depth_dnstream  ! m
 bcdataDn(1)%ValueArray(2)    = lowerZ +  depth_dnstream ! m

! upstream is default to flowrate
 bcdataUp(1)%NodeID = 1
 bcdataUp(1)%TimeArray(1)  = setting%Time%StartTime
 bcdataUp(1)%TimeArray(2)  = setting%Time%EndTime + 100.0 !s
 bcdataUp(1)%ValueArray(1) = initial_flowrate  ! m^3/s
 bcdataUp(1)%ValueArray(2) = initial_flowrate  ! m^3/2
    
 call case_simple_channel_links_and_nodes &
    (channel_length, channel_breadth, channel_topwidth, subdivide_length, &
    lowerZ, upperZ, initial_flowrate, init_depth, depth_upstream, &
    depth_dnstream, ManningsN, roughness_type,  idepth_type, &
    linkR, nodeR, linkI, nodeI, linkYN, nodeYN, linkName, nodeName)

 if ((debuglevel > 0) .or. (debuglevelall > 0))  print *, '*** leave ',subroutine_name
 end subroutine case_simple_channel_initialize
!
!========================================================================== 
!
! PRIVATE BELOW HERE
!
!==========================================================================
!
 subroutine case_simple_channel_links_and_nodes &
    (channel_length, channel_breadth, channel_topwidth, subdivide_length, &
     lowerZ, upperZ, initial_flowrate, init_depth, depth_upstream, & 
     depth_dnstream, ManningsN, roughness_type, idepth_type, &
     linkR, nodeR, linkI, nodeI, linkYN, nodeYN, linkName, nodeName)
!
! creates a simple rectangular channel with 1 link and 2 nodes
! 
 character(64) :: subroutine_name = 'case_simple_channel_links_and_nodes'
 
 real,  intent(in)  :: channel_length, channel_breadth
 real,  intent(in)  :: channel_topwidth, subdivide_length
 real,  intent(in)  :: lowerZ, upperZ, ManningsN, initial_flowrate
 real,  intent(in)  :: depth_upstream, depth_dnstream, init_depth
 
 integer, intent(in):: roughness_type, idepth_type
 
 integer,   dimension(:,:), allocatable, target, intent(out)    :: linkI 
 integer,   dimension(:,:), allocatable, target, intent(out)    :: nodeI
 
 real,      dimension(:,:), allocatable, target, intent(out)    :: linkR 
 real,      dimension(:,:), allocatable, target, intent(out)    :: nodeR 
 
 logical,   dimension(:,:), allocatable, target, intent(out)    :: linkYN
 logical,   dimension(:,:), allocatable, target, intent(out)    :: nodeYN
 
 type(string), dimension(:), allocatable, target, intent(out)   :: linkName 
 type(string), dimension(:), allocatable, target, intent(out)   :: nodeName
 
 integer :: ii
  
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name 
 
 N_link = 1
 N_node = 2
 
 call allocate_linknode_storage &
    (linkR, nodeR, linkI, nodeI, linkYN, nodeYN, linkName, nodeName)
 
! assign the indexes
 linkI(:,li_idx) = (/ (ii, ii=1,N_link) /)
 nodeI(:,ni_idx) = (/ (ii, ii=1,N_node) /)
 
! assign no names for links
 do ii=1,N_link
    linkName(ii)%str = "Channel" 
 end do
    
! assign zeros for accumulators
 nodeI(:,ni_N_link_d) = 0    
 nodeI(:,ni_N_link_u) = 0   
 
! assign uniform physical data 
 linkI(:,li_roughness_type)  = roughness_type
 linkR(:,lr_Roughness)       = ManningsN
 
! designate the upstream nodes
 nodeI(1,ni_node_type) = nBCup

 nodeR(1,nr_Zbottom) = upperZ
 
 nodeName(1)%str = 'UpstreamBC'
    
! designate the downstream node
 nodeI(2,ni_node_type) = nBCdn

 nodeR(2,nr_Zbottom) = lowerZ
 
 nodeName(2)%str = 'DownstreamBC'

! assign the link types
 linkI(:,li_link_type) = lChannel

! assign all as rectangular channels
 linkI(:,li_geometry) = lRectangular

! assign the link position and mappings

 linkI(1,li_Mnode_u) = 1 ! map to upstream node
 linkI(1,li_Mnode_d) = 2 ! map to downstream node

 linkR(1,lr_Length)          = channel_length
 linkR(1,lr_BreadthScale)    = channel_breadth 
 linkR(1,lr_TopWidth)        = channel_topwidth 
 linkR(1,lr_ElementLength)   = subdivide_length
 linkR(1,lr_InitialFlowrate) = initial_flowrate
 linkR(1,lr_InitialDepth)    = init_depth
 linkR(1,lr_InitialUpstreamDepth)    = depth_upstream
 linkR(1,lr_InitialDnstreamDepth)    = depth_dnstream
 linkI(1,li_InitialDepthType)        = idepth_type
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) then
    print *
    print *, subroutine_name,'-----------------------------------'
    print *, 'link info'
    print *, linkI(:,li_idx), ' idx'
    print *, linkI(:,li_link_type), ' type'
    print *, linkI(:,li_Mnode_u) , ' upstream node'
    print *, linkI(:,li_Mnode_d) , ' downstream node'
    print *, ''
    print *, 'node info'
    print *, nodeI(:,ni_idx), ' idx'
    print *, nodeI(:,ni_node_type), ' type'
    print *, nodeI(:,ni_N_link_d), 'number of downstream links'
    !print *, nodeI(:,ni_Mlink_d1), 'downstream1 link'
    print *, nodeI(:,ni_N_link_u), 'number of upstream links'
    !print *, nodeI(:,ni_Mlink_u1), 'upstream1 link'
 endif
 
 if ((debuglevel > 0) .or. (debuglevelall > 0))  print *, '*** leave ',subroutine_name
 end subroutine case_simple_channel_links_and_nodes
!
!========================================================================== 
! END OF MODULE case_simple_channel
!==========================================================================
 end module case_simple_channel
