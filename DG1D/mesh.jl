
using SparseArrays # for connectivity matrix

"""
unimesh1D(xmin, xmax, K)

# Description

    Generates a uniform 1D mesh

# Arguments

    xmin: smallest value of array

    xmax: largest values of array

    K: number of elements in an array

# Return Values: VX, EtoV

    VX: vertex values | an Array of size K+1

    EtoV: element to node connectivity | a Matrix of size Kx2

# Example
xmin = -1
xmax =  1
K    =  4
VX, EtoV = unimesh1D(xmin, xmax, K)

"""
function unimesh1D(xmin, xmax, K)
    VX = @. collect(0:K) / K * (xmax - xmin) + xmin
    EtoV = Int.(ones(K, 2))
    for i = 1:K
        EtoV[i,1] = Int(i)
        EtoV[i,2] = Int(i+1)
    end
    return VX, EtoV
end

"""
gridvalues1D(xmin, xmax, K)

# Description

    Generates physical gridpoints with each element

# Arguments

    VX: vertex values | an Array of size K+1

    EtoV: element to node connectivity | a Matrix of size Kx2

    r: LGL nodes in reference element | an array

# Return Values: x

    x: physical coordinates of solution

# Example (uses dg_utils.jl as well)

xmin = 0
xmax = 2π
K = 4
# call functions
VX, EtoV = unimesh1D(xmin, xmax, K)
r = jacobiGL(0, 0, 4)
x = gridvalues1D(VX, EtoV, r)
# x[:,1] is the physical coordinates within the first element
# for plotting
f(x) = sin(x)
plot(x, f.(x))
# scatter(x,f.(x)) tends to work better
"""
function gridvalues1D(VX, EtoV, r)
    # get low and high edges
    va = view(EtoV, :, 1)
    vb = view(EtoV, :, 2)

    # compute physical coordinates of the grid points
    x = ones(length(r),1) * (VX[va]') .+ 0.5 .* (r .+ 1 ) * ((VX[vb] - VX[va])')
    return x
end

"""
facemask1D(r)

# Description

    creates face mask

# Arguments

    r: GL points

# Return Values: x

    fmask1: standard facemask
    fmask2: alternate form

# Example | dg_utils.jl

r = jacobiGL(0, 0, 4)
fmask = fmask1D(r)

"""
function fmask1D(r)
    # check if index is left or right edge
    fm1 = @. abs(r+1) < eps(1.0);
    fm2 = @. abs(r-1) < eps(1.0);
    fmask1 = (fm1,fm2)

    # alternate form
    tmp = collect(1:length(r))
    fmask2  = [tmp[fm1]; tmp[fm2]]

    fmask = (fmask1, fmask2)
    return fmask
end

"""
edgevalues1D(fmask, x)

# Description

    calculates edge values

# Arguments

    fmask: face mask for GL edges

    x:  physical coordinates of solution on each element

# Return Values: x

    fx: face values of x

# Example | dg_utils.jl

r = jacobiGL(0, 0, 4)
x = gridvalues1D(VX, EtoV, r)
fmask = fmask1D(r)[1]
fx = edgevalues1D(fmask,x)

# the locations of the edges in element 1 is fx[:, 1]


"""
function edgevalues1D(fmask, x)
    # compute x values at selected indices
    fx1 = x[fmask[1],:]
    fx2 = x[fmask[2],:]

    # return list of physical edge positions
    fx = [fx1; fx2]
    return fx
end

"""
normals1D(K)

# Description

    calculates face normals

# Arguments

    K: number of elements

# Return Values: normals

    normals: face normals along each grid

# Example

"""
function normals1D(K)
    normals  = ones(2,K)
    @. normals[1,:] *= -1
    return normals
end

"""
geometric_factors(x, Dr)

# Description

    computes the geometric factors for local mappings of 1D elements

# Arguments

    x: physical coordinates of solution for each element

    Dr:

# Return Values: rx, J

    rx: inverse jacobian

    J: jacobian (in 1D a scalar)

# Example

"""
function geometric_factors(x, Dr)
    J = Dr * x
    rx = 1 ./ J # for 1D
    return rx, J
end

"""
connect1D(EtoV)

# Description

    builds global connectivity arrays for 1D

# Arguments

    EtoV: element to node connectivity | a Matrix of size Kx2

# Return Values: EtoE, EtoF

    EtoE: element to element connectivity
    EtoF: element to face connectivity

# Example

"""
function connect1D(EtoV)
    nfaces = 2 # for 1d elements

    # Find number of elements and vertices
    K = size(EtoV,1)
    total_faces = nfaces * K
    Nv = K+1

    # list of local face to local vertex connections
    vn = [1, 2]

    # build global face to vertex array
    FtoV = Int.(spzeros(total_faces, Nv))
    let sk = 1
        for k = 1:K
            for faces = 1:nfaces
                FtoV[sk, EtoV[k, vn[faces]]] = 1;
                sk += 1
            end
        end
    end

    # build global face to face array
    FtoF = FtoV * (FtoV') - sparse(I, total_faces, total_faces)

    # find all face to face connections
    (faces1, faces2) = findnz(FtoF)

    # convert global face number to element and face numbers
    element1 = @. floor(Int, (faces1 - 1) / nfaces) + 1
    face1    = @. Int( mod( (faces1 - 1),  nfaces) + 1)
    element2 = @. floor(Int, (faces2 - 1) / nfaces) + 1
    face2    = @. Int( mod( (faces2 - 1),  nfaces) + 1)

    # Rearrange into Nelement x Nfaces sized arrays
    ind = diag( LinearIndices(ones(K, nfaces))[element1,face1] ) # this line is a terrible idea.
    EtoE = collect(1:K) * ones(1, nfaces)
    EtoF = ones(K, 1) * (collect(1:nfaces)')
    EtoE[ind] = copy(element2);
    EtoF[ind] = face2;
    return EtoE, EtoF
end

"""
buildmaps1D(K, np, nfp, nfaces, fmask, EtoE, EtoF, x)
# Description

    connectivity matrices for element to elements and elements to face

# Arguments

-   `K`: number of elements
-   `np`: number of points within an element (polynomial degree + 1)
-   `nfp`: 1
-   `nfaces`: 2
-   `fmask`: an element by element mask to extract edge values
-   `EtoE`: element to element connectivity
-   `EtoF`: element to face connectivity
-   `x`: Guass lobatto points

# Return Values: vmapM, vmapP, vmapB, mapB, mapI, mapO, vmapI, vmapO

-   `vmapM`: vertex indices, (used for interior u values)
-   `vmapP`: vertex indices, (used for exterior u values)
-   `vmapB`: vertex indices, corresponding to boundaries
-   `mapB`: use to extract vmapB from vmapM
-   `mapI`: Index of left boundary condition
-   `mapO`: Index of right boundary condition

# Example | uses dg_utils.jl

K = 3
n = 3; α = 0; β = 0; xmin = 0; xmax = 2π;
np = n + 1
nfp = 1
nfaces = 2

r = jacobiGL(α, β, n)

VX, EtoV = unimesh1D(xmin, xmax, K)
EtoE, EtoF = connect1D(EtoV)
x = gridvalues1D(VX, EtoV, r)
fx = edgevalues1D(r,x)

vmapM, vmapP, vmapB, mapB, mapI, mapO, vmapI, vmapO = buildmaps1D(K, np, nfp, nfaces, fmask, EtoE, EtoF, x)
"""
function buildmaps1D(K, np, nfp, nfaces, fmask, EtoE, EtoF, x)
    # number volume nodes consecutively
    nodeids = reshape(collect(1:(K*np)), np, K)
    vmapM = zeros(nfp, nfaces, K)
    vmapP = zeros(nfp, nfaces, K)
    # find index of face nodes wrt volume node ordering
    for k1 in 1:K
        for f1 in 1:nfaces
            vmapM[:, f1, k1] = nodeids[fmask[f1], k1]
        end
    end

    for k1 = 1:K
        for f1 = 1:nfaces
            # find neighbor
            k2 = Int.( EtoE[k1, f1])
            f2 = Int.( EtoF[k1, f1])

            # find volume node numbers of left and right nodes
            vidM = Int.( vmapM[:, f1, k1])
            vidP = Int.( vmapM[:, f2, k2])

            x1 = x[vidM]
            x2 = x[vidP]

            # compute distance matrix
            D = @. (x1 - x2)^2
            if D[1] < eps(1.0)*10^5
                vmapP[:, f1, k1] = vidP
            end
        end
    end

    # reshape arrays
    vmapP = Int.( reshape(vmapP, length(vmapP)) )
    vmapM = Int.( reshape(vmapM, length(vmapM)) )

    # Create list of boundary nodes
    mapB = Int.( collect(1:length(vmapP))[vmapP .== vmapM] )
    vmapB = Int.( vmapM[mapB] )

    # inflow and outflow maps
    mapI = 1
    mapO = K * nfaces
    vmapI = 1
    vmapO = K*np
    return vmapM, vmapP, vmapB, mapB, mapI, mapO, vmapI, vmapO
end

"""
make_periodic1D!(vmapP, u)

# Description

    makes the grid periodic by modifying vmapP

# Arguments

    vmapP: exterior vertex map
    u: vertex vector

# Return Values: none

# Example

"""
function make_periodic1D!(vmapP, u)
    vmapP[1] = length(u)
    vmapP[end] = 1

    return nothing
end
