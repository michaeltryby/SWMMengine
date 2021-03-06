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
!==========================================================================
!2019-11-11 ==> Contributed by Eddie Tiernan
 program main
 
 implicit none
 
 integer, parameter :: dp = selected_real_kind(15)
 
 integer, parameter :: node_id           = 1 ! node ID
 integer, parameter :: ni_idx            = 2 ! the node index (i.e. its position in the array)
 integer, parameter :: ni_node_type      = 3 ! int representation of the type of node
 integer, parameter :: ni_N_link_u       = 4 ! the number of links directly upstream of this node
 integer, parameter :: ni_N_link_d       = 5 ! the number of links directly downstream of this node
 integer, parameter :: ni_Mlink_u1       = 6 ! the index of the 1st link directly upstream
 integer, parameter :: ni_Mlink_u2       = 7 ! the index of the 2nd link directly upstream
 integer, parameter :: ni_Mlink_u3       = 8 ! the index of the 3rd link directly upstream
 integer, parameter :: ni_Mlink_d1       = 9 ! the index of the 1st link directly downstream
 integer, parameter :: ni_Mlink_d2       =10 ! the index of the 2nd link directly downstream
 integer, parameter :: ni_Mlink_d3       =11 ! the index of the 3rd link directly downstream
 integer, parameter :: nr_directweight_u =12 ! the cumulative weight of the links directly upstream
 integer, parameter :: nr_totalweight_u  =13 ! the cumulative weight of all links upstream
 
 
 integer, parameter :: link_id                 = 1 ! link ID
 integer, parameter :: li_idx                  = 2
 integer, parameter :: li_link_type            = 3 ! int representation of the type of link
 integer, parameter :: li_geometry             = 4 ! int representation of the type of link geometry
 integer, parameter :: li_Mnode_u              = 5 ! ID of upstream node
 integer, parameter :: li_Mnode_d              = 6 ! ID of downstream node
 integer, parameter :: lr_Length               = 7 ! length of the link (0 if type != CONDUIT)
 integer, parameter :: lr_Slope                = 8 ! average slope of the link, estimated with extreme points
 integer, parameter :: lr_Roughness            = 9 ! Manning coefficient of the link (0 if type != CONDUIT)
 integer, parameter :: lr_InitialFlowrate      =10 ! initial flow rate
 integer, parameter :: lr_InitialUpstreamDepth =11 ! initial upstream depth
 integer, parameter :: lr_InitialDnstreamDepth =12 ! initial downstream depth
 

 real(dp)    :: lr_target = 1.0							! for the time being, the target length of an element is a hardcoded parameter
 integer :: n_rows_in_file_node, n_rows_in_file_link	! counter for the number of rows in the node/link .csv files
 integer :: iunit = 10
 integer :: runit = 11
 integer :: lunit = 12
 integer :: header_row = 1
 integer :: n_rows_excluding_header_node, n_rows_excluding_header_link	! number of rows in the node/link .csv files excluding the header, used to determine the size of the arrays
 integer :: n_rows_plus_processors_node, n_rows_plus_processors_link	! the NodeMatrix and LinkMatrix arrays are of the size of the .csv file plus the number of processors, for phantom nodes/links
 integer :: istat
 integer,parameter          :: line_length=256
 character(line_length)     :: line
 character(len=line_length) :: word
 real(dp)    :: a(line_length/2+1)
 integer :: i,io,icount,rcount
 integer :: multiprocessors = 3							! for the OPTIMAL example, the number of processors is 3.  This is a project dependent parameter
 real(dp) :: phantom_index								! the node_idx for the phantom node that will be placed in the middle of a link
 integer :: weight_index = -998877						! the node_idx that is called in the nr_totalweight_assigner() that keeps track of which node's totalweight is being updated
 real(dp) :: partition_threshold						! the collective weight (i.e. length) being searched for
 real(dp) :: max_weight = 0.0							! the cumulative weight of the graph
 integer :: effective_root = -998877					! a dummy node that either has the partition_threshold as it's weight or is a near overestimate of the partition_threshold
 logical :: ideal_exists = .false.						! boolean to check whether the partition_threshold is found exactly at a node
 integer :: spanning_link = -998877						! link_idk for the link that "spans" (or abstractly contains the partition_threshold along its length)
 real(dp) :: start_point = 0.0							! distance from the upstream node that the phantom_node should be placed
 integer :: root										! node_idx for whichever node is currently being updated
 real(dp) :: upstream_link_length = 0.0					! used to determine the weight being added to the node in nr_totalweight_assigner()
 integer :: upstream_node = -998877						! dummy node_idx used to track which node is being jumped to next in nr_totalweight_assigner()
 real(dp) :: upstream_weight = 0.0						! sum of the upstream_link_lengths that are feeding into the current root node
 real(dp) :: total_clipped_weight = 0.0					! amount of weight that has been removed due to a pseudo-partition.  this only occurs in case 3 
 integer :: phantom_array_location						! the row number in the nodeMatrix that will be updated with the phantom_node information
 
 real(dp), dimension(:,:), allocatable :: nodeMatrix		! the nodeMatrix is the array from the nodes.csv file that is being reorganized by BIPquick
 real(dp), dimension(:,:), allocatable :: linkMatrix		! the linkMatrix is the array from the links.csv file that is being reorganized by BIPquick
 real(dp), dimension(:,:), allocatable :: weight_range		! this is an array of tuples that contains the max and min totalweights on each link, used to locate a spanning_link
 real(dp), dimension(:,:), allocatable :: nodes_container	! dummy array used in the BIPquick post-processing step 
 
 real(dp), dimension(:,:,:), allocatable :: subnetwork_container_nodes		! 3D array that stores the node info for each identified 'part', or partition component
 real(dp), dimension(:,:,:), allocatable :: subnetwork_container_links		! 3D array that stores the link info for each identified 'part'
 
 logical, allocatable, dimension(:) :: visited_flag_weight					! list of booleans that determines whether that node's directweight has already contributed to the weight_index node's totalweight
 logical, allocatable, dimension(:) :: visit_network_mask					! boolean list that tracks whether a node already belongs to a part
 logical, allocatable, dimension(:) :: partition_boolean					! boolean list that tracks whether a link already belongs to a part
 
 integer, allocatable, dimension(:) :: accounted_for_links					! post-processing list of links for reordering the linkMatrix
 
 integer:: ii, jj, kk, mp									! counters: ii - row in nodeMatrix, jj - row in linkMatrix, kk - secondary row counter for node/linkMatrix, mp - for each multiprocessor
 
 
 integer :: debuglevel = 0
 integer :: debuglevelall = 0
 
!-------------------------------------------------------------------------- 
 
 open(newunit=runit, file='nodes_info_EDGE2.csv', status='OLD')
 
! get number of lines in the file
 n_rows_in_file_node = number_of_lines_in_file(runit)
 
! exclude the header from the rows
 n_rows_excluding_header_node = n_rows_in_file_node - header_row
 n_rows_plus_processors_node = n_rows_excluding_header_node + multiprocessors -1
 
 allocate(nodeMatrix(n_rows_plus_processors_node, nr_totalweight_u))
 nodeMatrix(:,:)=-998877
 
 read(runit,*)
 rcount = 1
 do
    read(runit,'(a)',iostat=istat) line
    if (is_iostat_end(istat)) exit
    do i=1,len(line)     ! replace comma and semicolon delimiters with spaces
        select case(line(i:i))
        case(',',';'); line(i:i)=' '
        end select
    enddo
    
    icount = 0                         ! initialize count of values found on line
    do
        line=adjustl(line)             ! remove leading spaces
        read(line,*,iostat=istat)word  ! read next token from line
        if (istat .ne. 0) exit
        read(word,*,iostat=istat) a(icount + 1) ! convert token to a number
        if (istat .ne. 0) exit
        icount=icount + 1
        line=line(len_trim(word)+1:)   ! remove token just read
   enddo
   nodeMatrix(rcount,:) = a(2:icount)
   rcount = rcount + 1
   ! write(*,*)'   read ',icount,' values=', a(:icount)
 enddo
 
 open(newunit=lunit, file='links_info_EDGE2.csv', status='OLD')
 
! get number of lines in the file
 n_rows_in_file_link = number_of_lines_in_file(lunit)
 
! excluude the header from the rows
 n_rows_excluding_header_link = n_rows_in_file_link - header_row
 n_rows_plus_processors_link = n_rows_excluding_header_link + multiprocessors -1
 
 allocate(linkMatrix(n_rows_plus_processors_link, lr_InitialDnstreamDepth))
 linkMatrix(:,:)=-998877
 
 read(lunit,*)
 rcount = 1
 do
    read(lunit,'(a)',iostat=istat) line
    if (is_iostat_end(istat)) exit
    do i=1,len(line)     ! replace comma and semicolon delimiters with spaces
        select case(line(i:i))
        case(',',';'); line(i:i)=' '
        end select
    enddo
    
    icount = 0                         ! initialize count of values found on line
    do
        line=adjustl(line)             ! remove leading spaces
        read(line,*,iostat=istat)word  ! read next token from line
        if (istat .ne. 0) exit
        read(word,*,iostat=istat) a(icount + 1) ! convert token to a number
        if (istat .ne. 0) exit
        icount=icount + 1
        line=line(len_trim(word)+1:)   ! remove token just read
   enddo
   linkMatrix(rcount,:) = a(2:icount)
   rcount = rcount + 1
   ! write(*,*)'   read ',icount,' values=', a(:icount)
 enddo
 
 ! the idx of the phantom nodes are based on how many nodes exist, so this function determines the number of digits in the last node/link.  Then the phantom_index starts at 10^digits
 phantom_index = phantom_naming_convention(nodeMatrix, linkMatrix)
 
 ! the boolean lists need to be allocated and initialized as containing all .false. values
 allocate(visited_flag_weight(size(nodeMatrix,1)))
 visited_flag_weight(:) = .false.
 
 allocate(visit_network_mask(size(nodeMatrix,1)))
 visit_network_mask(:) = .false.
 
 allocate(partition_boolean(size(linkMatrix,1)))
 partition_boolean(:) = .false.
 
 ! allocate the tuple list to be the size of the linkMatrix
 allocate (weight_range(size(linkMatrix,1),2))
 
 ! determine the weight directly upstream of each node
 call local_node_weighting(lr_target, nodeMatrix, linkMatrix)
 
 ! allocate the container for the nodes in each part, initialize with NULL values
 allocate (subnetwork_container_nodes &
    (multiprocessors,size(nodeMatrix,1),size(nodeMatrix,2)))
 subnetwork_container_nodes(:,:,:)= -998877
    
 ! allocate the container for the links in each part, initialize with NULL values
 allocate (subnetwork_container_links &
    (multiprocessors,size(linkMatrix,1),size(linkMatrix,2)))
 subnetwork_container_links(:,:,:)= -998877
    
 ! this do loop is the BIPquick main process.  For each multiprocessor a subcontainer of nodes is populated.  The contents of this do loop determine which nodes are included.
 do mp = 1, multiprocessors
	! for the identification of each part, the totalweight of all nodes must be reset and reassigned
    nodeMatrix(:, nr_totalweight_u) = 0.0
    call nr_totalweight_assigner(nodeMatrix, weight_index, max_weight,&
                visited_flag_weight, visit_network_mask)
                
	! the partition_threshold for the next part is always equal to the size of the remaining graph divided by the number of processors remaining
    partition_threshold = max_weight/real(multiprocessors - mp + 1)
                
	! the effective_root is determined either as the node that exactly equals the partition_threshold, or rather the node that is the nearest overestimate of the partition_threshold
    effective_root = ideal_partition_check &
    (ideal_exists, max_weight, partition_threshold, nodeMatrix)
    
	! within the ideal_partition_check, a boolean ideal_exists becomes .true. if the effective_root exactly equals the partition_threshold
    if(ideal_exists .eqv. .true.) then
		! if an ideal node is found, the subnetwork_carving() function is called on that node to extract the upstream sub-graph as a complete part
        call subnetwork_carving &
            (effective_root, mp, subnetwork_container_nodes, visit_network_mask, & 
             nodeMatrix, linkMatrix)
    else
		! if an ideal node is NOT found, the network needs to be checked for a link that "spans" the partition_threshold.  
		! "Span" means that the partition_threshold exists in the range [upstream_node_weight, downstream_node_weight]
		! The weight_range tuple array is initialized as null rather than zeroes because zero is a potentially real value
        weight_range(:,:) = -998877
		! The spanning_check() function populates the weight_range array and then searches the array for any row (and corresponding link) that bounds the partition_threshold
        call spanning_check &
            (spanning_link, weight_range, linkMatrix, nodeMatrix, lr_target, &
             partition_threshold, partition_boolean)
		! If a spanning link is not found, that indicates no precise partition is attainable (Case 3)
		! This do while loop clips out the 
        do while (spanning_link == -998877)
            do ii= 1,size(nodeMatrix,1)
                if (nodeMatrix(ii, ni_idx) == effective_root) then
                    subnetwork_container_nodes(mp, ii, :) = nodeMatrix(ii, :)
                endif
                
                do jj=1,size(linkMatrix,1)
                    if (linkMatrix(jj, li_Mnode_d) == effective_root) then
                        upstream_link_length = linkMatrix(jj,lr_Length)
                        upstream_node = linkMatrix(jj,li_Mnode_u)
                        do kk=1, size(nodeMatrix,1)
                            if (nodeMatrix(kk, ni_idx) == upstream_node) then
                                upstream_weight &
                                    = nodeMatrix(kk,nr_totalweight_u)
                                total_clipped_weight = upstream_weight + &
                                    weighting_function(lr_target, upstream_link_length)
                                exit
                            endif
                        enddo
                        exit
                    endif
                enddo
                
                nodeMatrix(ii, nr_directweight_u) = &
                    nodeMatrix(ii, nr_directweight_u) - total_clipped_weight
                exit
            enddo
            
            partition_threshold = partition_threshold - total_clipped_weight
            
            call subnetwork_carving &
                (upstream_node, mp, subnetwork_container_nodes, &
                visit_network_mask, nodeMatrix, linkMatrix)
                
            call spanning_check &
                (spanning_link, weight_range, linkMatrix, nodeMatrix, &
                lr_target, partition_threshold, partition_boolean)
        enddo
        
        start_point = linear_interpolator(partition_threshold, &
        spanning_link, linkMatrix, weight_range, lr_target)
        call phantom_node_generator(spanning_link, start_point, mp, &
            partition_threshold, linkMatrix, nodeMatrix, &
            subnetwork_container_nodes, subnetwork_container_links, & 
            n_rows_excluding_header_node, n_rows_excluding_header_link, &
            phantom_array_location, phantom_index, lr_target)
        
        call subnetwork_carving &
            (int(nodeMatrix(phantom_array_location, ni_idx)), mp, &
            subnetwork_container_nodes, visit_network_mask, nodeMatrix, &
            linkMatrix)
    endif
    
    do ii=1, size(visit_network_mask,1)
        if (visit_network_mask(ii) .eqv. .true.) then
            nodeMatrix(ii, nr_directweight_u) = 0.0
        endif
    enddo
 enddo
 
 ! Allocates and initializes two arrays that are used in postprocessing
 allocate(accounted_for_links(size(linkMatrix,1)))
 accounted_for_links(:) = -998877
 
 allocate(nodes_container(size(nodeMatrix,1),size(nodeMatrix,2)))
 nodes_container(:,:) = -998877
 
 ! For each pre-defined part, populate a dummy variable with the nodes information for that part.
 ! Call the subnetwork_links() function which determines, on the basis of a parts nodes, which links are also on that part
 do mp = 1, size(subnetwork_container_nodes,1)
    nodes_container(:,:) = subnetwork_container_nodes(mp,:,:)
    call subnetworks_links (mp,nodes_container, subnetwork_container_links, &
        linkMatrix, accounted_for_links)
 enddo
 
 ! Calls a preprocessing function that collapses the separated graph parts back into a single array
 call reorganize_arrays(nodeMatrix, linkMatrix, multiprocessors, &
            subnetwork_container_nodes, subnetwork_container_links)
 
 open(unit=21, file='IdealNetworkNode.csv', status='unknown')
 open(unit=22, file='IdealNetworkLink.csv', status='unknown')

 do ii=1, n_rows_excluding_header_node
    write(21, '(*(I0 : ", "))') int(nodeMatrix(ii,:))
 enddo
 
 do ii=1, n_rows_excluding_header_link
    write(22, '(*(f10.5 : ", "))') linkMatrix(ii,:)
 enddo
 
 print*, "Ideal Network Node"
 do ii=1, size(nodeMatrix,1)
    print*, nodeMatrix(ii,:)
 enddo
 
 print*, "Ideal Network Link"
 do ii=1, size(linkMatrix,1)
    print*, linkMatrix(ii,:)
 enddo
 
 contains
!
!============================================================================ 
!============================================================================ 
! 
 function weighting_function(lr_target, link_length) result(weight)
!
! the weight attributed to each link (that will ultimately be assigned to the 
! downstream node) are normalized by lr_Target.  This gives an estimate of 
! computational complexity. In the future lr_Target can be customized for each 
! link.
 character(64)   :: function_name = 'weighting_function'
 
 real(dp),intent(in)  :: lr_target
 real(dp),intent(in)  :: link_length
 real(dp) :: weight
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',function_name
 
 weight = link_length/lr_target
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',function_name
 end function weighting_function
!
!============================================================================ 
!============================================================================ 
! 
 subroutine null_value_convert(array)
!
! this function is used to convert the null values that are defaulted in the 
! nr_directweight_u and nr_totalweight_u columns of the nodes array into float 
! zeros.
 character(64) :: subroutine_name = 'null_value_convert'
 
 real(dp), intent(in out) :: array(:)
 integer :: ii
 real(dp) :: nullValue = -998877
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name
 
 where (array(:) == nullValue)
     array(:) = 0.0
 endwhere
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',subroutine_name
 end subroutine null_value_convert
!
!============================================================================ 
!============================================================================ 
! 
 subroutine local_node_weighting(lr_target, nodeMatrix, linkMatrix)
!
! this function takes each node index (ni_idx) and finds that ni_idx in the 
! downstream node column of the links array (li_Mnode_d).  From this row in 
! links the link weight is grabbed and ascribed to the node-in-questions local 
! weight (nr_directweight_u).
 character(64) :: subroutine_name = 'local_node_weighting'
 
 real(dp),intent(in)  :: lr_target
 real(dp), intent(in out) :: nodeMatrix(:,:), linkMatrix(:,:)
 integer :: rootnode_index, links_row
 integer ii, jj
 
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name
 
 call null_value_convert(nodeMatrix(:,nr_directweight_u))
 call null_value_convert(nodeMatrix(:,nr_totalweight_u))
 
 do ii= 1,size(nodeMatrix,1) ! This weighting function occurs for each node
    rootnode_index = nodeMatrix(ii, ni_idx) ! Assign to variable the node index
    links_row = 1 ! Initialize the links_row which points to the index of the link
    do jj=1,size(linkMatrix(:, li_Mnode_d))
        if (linkMatrix(jj, li_Mnode_d) == rootnode_index) then
            nodeMatrix(ii, nr_directweight_u) &
                = nodeMatrix(ii, nr_directweight_u) &
                + weighting_function(lr_target, linkMatrix(links_row, lr_Length))
        endif
        links_row = links_row + 1
    enddo
 enddo
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',subroutine_name
 end subroutine local_node_weighting
!
!============================================================================ 
!============================================================================ 
! 
 function find_weight_index(root_idx, nodeMatrix) result(weight_index)
!
! this function identifies the row that is being updated.  It is used as a row 
! constant in the upstream_weight_calculation function.

 character(64)   :: function_name = 'find_weight_index'
 
 real(dp), intent(in out) :: nodeMatrix(:,:)
 integer,intent(in)  :: root_idx
 integer :: weight_index, root_identity
 integer :: ii
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',function_name
 
 do ii= 1,size(nodeMatrix,1)
    root_identity = nodeMatrix(ii, ni_idx)
    print*, "ii=",ii, "weight=", weight_index
    print*, "root_identity= ", root_identity
    if (root_idx == root_identity) then
        weight_index = int(ii)
    endif
 enddo
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',function_name
 end function find_weight_index
!
!============================================================================ 
!============================================================================ 
! 
 recursive subroutine upstream_weight_calculation(weight_index, root, &
                nodeMatrix, linkMatrix, visited_flag_weight, &
                visit_network_mask)

 character(64) :: subroutine_name = 'upstream_weight_calculation'
 
 real(dp), intent(in out) :: nodeMatrix(:,:), linkMatrix(:,:)
 integer, intent(in) :: weight_index
 integer :: root, node_row_contents, link_idx, new_root
 integer :: link_row_contents, node_upstream
 logical, intent(in out) :: visited_flag_weight(:)
 logical, intent(in) :: visit_network_mask(:)
 integer :: ii, jj, kk
 
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name
 
 do ii= 1,size(nodeMatrix,1)
    node_row_contents = int(nodeMatrix(ii, ni_idx))
    
    if ( &
            root == node_row_contents .and. (visited_flag_weight(ii) .eqv. .false.) &
            .and. (visit_network_mask(ii) .eqv. .false.) &
        ) then
        visited_flag_weight(ii) = .true.
        nodeMatrix(weight_index, nr_totalweight_u) &
            = nodeMatrix(weight_index, nr_totalweight_u) &
            + nodeMatrix(ii, nr_directweight_u)
        do jj= 1, size(linkMatrix,1)
            link_row_contents = linkMatrix(jj, li_Mnode_d)
            if(node_row_contents == link_row_contents) then
                link_idx = linkMatrix(jj, li_idx)
                node_upstream = linkMatrix(jj, li_Mnode_u)
                do kk = 1, size(nodeMatrix,1)
                    if(node_upstream == nodeMatrix(kk, ni_idx)) then
                        new_root = nodeMatrix(kk, ni_idx)
                        call upstream_weight_calculation(weight_index, &
                            new_root, nodeMatrix, linkMatrix, &
                            visited_flag_weight, visit_network_mask)
                    endif
                enddo
            endif
        enddo
    endif
 enddo
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',subroutine_name
 end subroutine upstream_weight_calculation
!
!============================================================================ 
!============================================================================ 
! 
 subroutine nr_totalweight_assigner(nodeMatrix, weight_index, max_weight, &
                visited_flag_weight, visit_network_mask)

 character(64) :: subroutine_name = 'nr_totalweight_assigner'
 
 real(dp), intent(in out) :: nodeMatrix(:,:)
 integer, intent(in out) :: weight_index 
 logical, intent(in out) :: visited_flag_weight(:)
 logical, intent(in out) :: visit_network_mask(:)
 real(dp), intent(in out) :: max_weight
 integer :: ii
 real(dp) :: nullValue = -998877
 
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name
 
 do ii=1, size(nodeMatrix,1)
    if (nodeMatrix(ii,ni_idx) /= nullValue ) then
        visited_flag_weight(:) = .false.
        weight_index = ii
        call upstream_weight_calculation(weight_index, & 
                int(nodeMatrix(ii, ni_idx)), nodeMatrix, linkMatrix, & 
                visited_flag_weight, visit_network_mask)
    endif
 enddo
 
 max_weight = maxval(nodeMatrix(:, nr_totalweight_u))
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',subroutine_name
 end subroutine nr_totalweight_assigner
!
!============================================================================ 
!============================================================================ 
! 
 recursive subroutine subnetwork_carving &
    (root, proc, subnetwork_container_nodes, visit_network_mask, &
     nodeMatrix, linkMatrix)

 character(64) :: subroutine_name = 'subnetwork_carving'
 
 logical, intent(in out) :: visit_network_mask(:)
 real(dp), intent (in out) :: subnetwork_container_nodes (:,:,:)
 real(dp), intent(in) :: nodeMatrix(:,:), linkMatrix(:,:)
 integer :: node_row_contents, link_row_contents, new_root, node_upstream
 integer, intent(in) :: root, proc
 integer :: ii, jj, kk
 
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name
 
 do ii=1, size(nodeMatrix,1)
    node_row_contents = nodeMatrix(ii, ni_idx)
    if  ( root == node_row_contents .and. (visit_network_mask(ii) .eqv. .false.)) then
        visit_network_mask(ii) = .true.
        subnetwork_container_nodes(proc, ii, :) = nodeMatrix(ii, :)
        do jj= 1, size(linkMatrix,1)
            link_row_contents = linkMatrix(jj, li_Mnode_d)
            if(node_row_contents == link_row_contents) then
                node_upstream = linkMatrix(jj, li_Mnode_u)
                do kk = 1, size(nodeMatrix,1)
                    if(node_upstream == nodeMatrix(kk, ni_idx)) then
                        new_root = nodeMatrix(kk, ni_idx)
                        call subnetwork_carving(new_root, proc, &
                            subnetwork_container_nodes, visit_network_mask, &
                            nodeMatrix, linkMatrix)
                    endif
                enddo
            endif
        enddo
    elseif( &
                root == node_row_contents .and. (visit_network_mask(ii) .eqv. .true.) &
          ) then
          subnetwork_container_nodes(proc, ii, :) = nodeMatrix(ii, :)
    endif
 enddo
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',subroutine_name
 end subroutine subnetwork_carving
!
!============================================================================ 
!============================================================================ 
! 
 subroutine subnetworks_links &
    (proc,nodes_container, subnetwork_container_links, linkMatrix, &
     accounted_for_links)

 character(64) :: subroutine_name = 'subnetworks_links'
 real(dp) :: endpoint1, endpoint2
 real(dp), intent(in) :: nodes_container(:,:)
 real(dp), intent(in out) :: subnetwork_container_links(:, :, :)
 real(dp), intent(in) :: linkMatrix(:,:)
 integer, allocatable :: potential_endpoints(:)
 integer, intent(in out) :: accounted_for_links(:)
 integer, intent(in) :: proc
 integer :: ii, jj, linkCounter,mp
 real(dp) :: accountingLink
 logical :: accountedLink = .false.
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name
 
 allocate (potential_endpoints(size(nodeMatrix,1)))
 potential_endpoints(:) = nodes_container(:,ni_idx)
 
 do ii=1, size(linkMatrix,1)
    accountedLink = .false.
    endpoint1 = linkMatrix(ii, li_Mnode_u)
    endpoint2 = linkMatrix(ii, li_Mnode_d)
    do mp=1,proc
        linkCounter=1
        do jj=1,size(subnetwork_container_links(mp, :, li_idx))
            accountingLink = subnetwork_container_links(mp,jj,li_idx)
            if (accountingLink /= -998877) then
                accounted_for_links(linkCounter) = accountingLink
            endif
            linkCounter = linkCounter + 1
        enddo
    enddo
    do jj=1, size(accounted_for_links,1)
        if (accounted_for_links(jj) == int(linkMatrix(ii, li_idx))) then
            accountedLink = .true.
        endif
    enddo
    
    if (any(potential_endpoints(:) == endpoint1) .and. &
        any(potential_endpoints(:) == endpoint2) .and. &
        (accountedLink .eqv. .false.)) then
        subnetwork_container_links(proc, ii,:) = linkMatrix(ii,:)
    endif
 enddo
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',subroutine_name
 end subroutine subnetworks_links
!
!============================================================================ 
!============================================================================ 
! 
 function ideal_partition_check &
    (ideal_exists, max_weight, partition_threshold, nodeMatrix) result (effective_root)

 character(64) :: subroutine_name = 'ideal_partition_check'
 real(dp), intent(in) :: max_weight, partition_threshold
 logical, intent(in out) :: ideal_exists
 integer :: effective_root
 real(dp) :: nearest_overestimate
 real(dp), intent(in) :: nodeMatrix(:,:)
 integer :: ii
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name

 nearest_overestimate = max_weight

 do ii=1, size(nodeMatrix,1)
    if (nodeMatrix(ii, nr_totalweight_u) == partition_threshold) then
        effective_root = nodeMatrix(ii, ni_idx)
        ideal_exists = .true.
        exit
    endif
    if (&
        (nodeMatrix(ii, nr_totalweight_u) > partition_threshold) .and. &
        (nodeMatrix(ii, nr_totalweight_u) <= nearest_overestimate) &
       ) then
       nearest_overestimate = nodeMatrix(ii, nr_totalweight_u)
       effective_root = nodeMatrix(ii, ni_idx)
    endif
 enddo
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',subroutine_name
 end function ideal_partition_check
!
!============================================================================ 
!============================================================================ 
! 
 subroutine spanning_check &
    (spanning_link, weight_range, linkMatrix, nodeMatrix, lr_target, &
     partition_threshold, partition_boolean)
!
!
!
 character(64) :: subroutine_name = 'spanning_check'
 
 integer, intent(in out) :: spanning_link
 real(dp), allocatable, intent(in out) :: weight_range(:,:)
 real(dp), intent(in) :: linkMatrix(:,:), nodeMatrix(:,:)
 real(dp), intent(in) :: lr_target, partition_threshold
 logical, intent(in out) :: partition_boolean(:)
 integer :: upstream_node
 integer :: ii, jj
 
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name
 
 do jj=1, size(linkMatrix,1)
    upstream_node = linkMatrix(jj, li_Mnode_u)
    do ii=1, size(nodeMatrix,1)
        if(nodeMatrix(ii, ni_idx) == upstream_node) then
            weight_range(jj,1) = nodeMatrix(ii, nr_totalweight_u)
        endif
    enddo
    weight_range (jj, 2) = weight_range (jj, 1) + &
        weighting_function(lr_target, linkMatrix(jj, lr_Length))
 enddo
 do jj=1, size(weight_range,1)
    if(&
        (weight_range(jj,1) < partition_threshold) .and. &
        (partition_threshold < weight_range(jj,2)) .and. &
        (partition_boolean(jj) .eqv. .false.) &
      ) then
        spanning_link = linkMatrix(jj,li_idx)
        partition_boolean(jj) = .true.
        GOTO 5568
    endif
 enddo
 
 5568 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',subroutine_name  
 end subroutine spanning_check
!
!========================================================================== 
!==========================================================================
! 
 function linear_interpolator(partition_threshold, spanning_link, linkMatrix, &
    weight_range, lr_target) result(length_from_start)

 character(64)   :: function_name = 'linear_interpolator'
 
 real(dp), intent(in) :: linkMatrix(:,:), weight_range(:,:)
 real(dp) , intent(in) :: partition_threshold, lr_target
 integer, intent(in) :: spanning_link
 real(dp) :: length_from_start, total_length, start, weight_ratio
 integer :: ii
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',function_name
 do ii= 1,size(linkMatrix,1)
    if (int(linkMatrix(ii, li_idx)) == spanning_link) then
        total_length = linkMatrix(ii, lr_Length)
        start = weight_range(ii,1)
    endif
 enddo
 weight_ratio = (partition_threshold - start)&
    /weighting_function(lr_target, total_length)
 length_from_start = weight_ratio*total_length
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',function_name
 end function linear_interpolator
!
!========================================================================== 
!==========================================================================
! 
 function phantom_naming_convention(nodeMatrix, linkMatrix) result(phantom_idx)

 character(64)   :: function_name = 'phantom_naming_convention'
 
 real(dp), intent(in) :: linkMatrix(:,:), nodeMatrix(:,:)
 integer :: max_node_idx, max_link_idx
 integer, allocatable :: node_indices(:), link_indices(:)
 real(dp) :: dig, phantom_idx
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',function_name
 
 allocate(node_indices(size(nodeMatrix,1)))
 allocate(link_indices(size(linkMatrix,1)))
 
 node_indices(:) = int(nodeMatrix(:, ni_idx))
 max_node_idx = maxval(node_indices(:))
 
 link_indices(:) = int(linkMatrix(:, ni_idx))
 max_link_idx = maxval(link_indices(:))
 
 dig = floor(log10(real(max(max_node_idx, max_link_idx)))) + 1
 
 phantom_idx = 10**dig
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',function_name
 end function phantom_naming_convention
!
!========================================================================== 
!==========================================================================
! 
 subroutine phantom_node_generator(spanning_link, start_point, mp, &
    partition_threshold, linkMatrix, nodeMatrix, subnetwork_container_nodes, &
    subnetwork_container_links, n_rows_excluding_header_node, &
    n_rows_excluding_header_link, phantom_array_location, phantom_index, lr_target)
!
!
 character(64) :: subroutine_name = 'phantom_node_generator'
 
 real(dp), intent(in) :: start_point
 integer, intent(in) :: spanning_link
 integer, intent(in) :: mp 
 real(dp), intent(in) :: partition_threshold
 real(dp), intent (in) :: phantom_index
 real(dp), intent(in)  :: lr_target
 real(dp), intent(in out) :: linkMatrix(:,:), nodeMatrix(:,:)
 real(dp), intent (in out) :: subnetwork_container_nodes (:,:,:)
 real(dp), intent (in out) :: subnetwork_container_links (:,:,:)
 integer, intent(in) :: n_rows_excluding_header_node
 integer, intent(in) :: n_rows_excluding_header_link
 integer, intent(in out) :: phantom_array_location
 integer :: phantom_counter = 1
 integer :: phantom_name, phantom_array_location_link, downstream_node
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name
 
 phantom_name = int(phantom_index) + phantom_counter
 
 phantom_array_location = n_rows_excluding_header_node + mp
 
 phantom_array_location_link = n_rows_excluding_header_link + mp
 
 nodeMatrix(phantom_array_location, node_id) = phantom_name
 
 nodeMatrix(phantom_array_location, ni_idx) = phantom_name
 
 nodeMatrix(phantom_array_location, ni_node_type) = int(0)
 
 nodeMatrix(phantom_array_location, ni_N_link_u) = int(1)
 
 nodeMatrix(phantom_array_location, ni_Mlink_u2:ni_Mlink_d3) = -998877
 
 nodeMatrix(phantom_array_location, ni_Mlink_u1) = spanning_link
 
 nodeMatrix(phantom_array_location, ni_Mlink_d1) = phantom_name
 
 nodeMatrix(phantom_array_location, nr_directweight_u) = 0.0
 
 nodeMatrix(phantom_array_location, nr_totalweight_u) = partition_threshold
 
 do jj=1, size(linkMatrix,1)
    if(linkMatrix(jj,li_idx) == spanning_link) then
        linkMatrix(phantom_array_location_link,:) = linkMatrix(jj,:)
        
        linkMatrix(phantom_array_location_link,lr_Length) &
            = linkMatrix(jj,lr_Length) - start_point
            
        downstream_node = linkMatrix(jj,li_Mnode_d)
        do ii=1, size(nodeMatrix,1)
            if (nodeMatrix(ii,ni_idx) == downstream_node) then
                nodeMatrix(ii,nr_directweight_u) = &
                    nodeMatrix(ii,nr_directweight_u) - &
                    weighting_function(lr_target, start_point)
            endif
        enddo
        
        linkMatrix(jj, li_Mnode_d) = phantom_name
        
        linkMatrix(jj,lr_Length) = start_point
        exit
    endif
 enddo
 
 linkMatrix(phantom_array_location_link, link_id) = phantom_name
 
 linkMatrix(phantom_array_location_link, li_idx) = phantom_name
 
 linkMatrix(phantom_array_location_link, li_Mnode_u) = phantom_name
 
 phantom_counter = phantom_counter + 1 
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',subroutine_name  
 end subroutine phantom_node_generator
!
!============================================================================ 
!============================================================================ 
!
 function number_of_lines_in_file(iunit) result(n_lines)
 
 integer,intent(in)  :: iunit   ! the file unit number
 integer             :: n_lines ! the number of lines in the file

 character(len=1)    :: tmp
 integer             :: istat
 character(64) :: function_name = 'number_of_lines_in_file'
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',function_name
 rewind(iunit)
 n_lines = 0
 do
     read(iunit,fmt='(A1)',iostat=istat) tmp
     if (is_iostat_end(istat)) exit
     n_lines = n_lines + 1
 end do
 rewind(iunit)
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',function_name
 end function number_of_lines_in_file
!
!============================================================================ 
!============================================================================ 
! 
 subroutine reorganize_arrays(nodeMatrix, linkMatrix, multiprocessors, &
            subnetwork_container_nodes, subnetwork_container_links)
!
! this function is used to convert the null values that are defaulted in the 
! nr_directweight_u and nr_totalweight_u columns of the nodes array into float 
! zeros.
 character(64) :: subroutine_name = 'reorganize_arrays'
 real(dp), intent (in) :: subnetwork_container_nodes (:,:,:)
 real(dp), intent (in) :: subnetwork_container_links (:,:,:)
 real(dp), intent(in out) :: nodeMatrix(:,:), linkMatrix(:,:)
 integer, intent(in) :: multiprocessors
 
 real(dp) , allocatable :: reorganizedNodes(:,:)
 real(dp) , allocatable :: reorganizedLinks(:,:)
 
 integer :: nodesRowCounter = 1, linksRowCounter = 1
 integer :: ii, jj, mp
 
!-------------------------------------------------------------------------- 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** enter ',subroutine_name
 
 allocate(reorganizedNodes(size(nodeMatrix,1),size(nodeMatrix,2)))
 reorganizedNodes = -998877
 
 do mp=1, multiprocessors
    do ii=1, size(subnetwork_container_nodes,2)
        do jj=1, size(reorganizedNodes,1)
            if (subnetwork_container_nodes(mp,ii,ni_idx) == reorganizedNodes(jj,ni_idx)) then
                GOTO 5566
            endif
        enddo
        if (subnetwork_container_nodes(mp,ii,ni_idx) == -998877) then
            GOTO 5566
        endif
        
        reorganizedNodes(nodesRowCounter,:) = subnetwork_container_nodes(mp,ii,:)
        nodesRowCounter = nodesRowCounter + 1
 5566   continue
    enddo
 enddo
 
 nodeMatrix(:,:) = reorganizedNodes(:,:)
 
 allocate(reorganizedLinks(size(linkMatrix,1),size(linkMatrix,2)))
 reorganizedLinks = -998877
 
 do mp=1, multiprocessors
    do ii=1, size(subnetwork_container_links,2)
        do jj=1, size(reorganizedLinks,1)
            if (subnetwork_container_links(mp,ii,ni_idx) == reorganizedLinks(jj,ni_idx)) then
                GOTO 5567
            endif
        enddo
        if (subnetwork_container_links(mp,ii,ni_idx) == -998877) then
            GOTO 5567
        endif
        
        reorganizedLinks(linksRowCounter,:) = subnetwork_container_links(mp,ii,:)
        linksRowCounter = linksRowCounter + 1
 5567   continue
    enddo
 enddo
 
 linkMatrix(:,:) = reorganizedLinks(:,:)
 
 if ((debuglevel > 0) .or. (debuglevelall > 0)) print *, '*** leave ',subroutine_name
 end subroutine reorganize_arrays
!
!========================================================================== 
!==========================================================================
!
 end program main
!==========================================================================
