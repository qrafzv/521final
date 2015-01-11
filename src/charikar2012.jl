###############################################################
## Needed packages
###############################################################

using Clp
using JuMP

# point data structure used for all facilities and clients
type DataPoint
    coordinates
end

type Match
    j
    jp
    d
end

function charikar2012{T<:Real}(d::DenseMatrix{T}, k::Integer)
    charikar2012Variable(d, k, 1.5, d);
end

# K-medoids algorithm based on Charikar's 2012 LP rounding scheme
function charikar2012{T<:Real}(d::DenseMatrix{T}, k::Integer, dc::DenseMatrix{T})
    charikar2012Variable(d, k, 1.5, dc);
end


function charikar2012Variable{T<:Real}(d::DenseMatrix{T}, k::Integer, RMax::Float64, dC::DenseMatrix{T})
    # check arguments
    nf, nc = size(d);
    k <= nf || error("Number of medoids should be less than the number of faciliites.");
    
    ###############################################################
    ## Initialization of problem variables
    ###############################################################
    DEBUG = false;
    F = Dict{Int32, DataPoint}();
    C = Dict{Int32, DataPoint}();
    for i=1:nf
	fi = DataPoint(i);
	get!(F, i, fi);
    end
    
    for i=1:nc
        ci = DataPoint(i);
        get!(C, i, ci);
    end

    # Print the LP variables
    if (false)
	println("\n#################################################");
	print("Initialized Variables");
	println("\n#################################################\n");
	println("F: \n");
	for key in sort(collect(keys(F)))
	    println("$key $(F[key])\n");
	end
	println("C: \n");
	for key in sort(collect(keys(C)))
	    println("$key $(C[key])\n");
	end
	for x=1:size(d,1)
	    if (x == 1)
		print("d:\t");
		for y=1:size(d, 2)
		    @printf "%d\t\t" y;
		end		
		println();
	    end
	    print("$x\t");
	    for y=1:size(d,2)
		@printf "%6f\t" d[x, y];
	    end
	    println();
	end
    end
    
    ###############################################################
    ## Solving the LP
    ###############################################################
    
    m = Model()
    
    # define variables x and y, must all be between 0 and 1
    # x_ij is the fractional amount of client j that used facility i
    @defVar(m, 0 <= x[1:length(F), 1:length(C)] <= 1)
    # y_i is the fractional amount of facility at location y_i
    @defVar(m, 0 <= y[1:length(F)] <= 1)				
    
    # add in the constraints
    # for every client in C, the sum of the fractional facility use over F must equal 1
    for j in 1:length(C)
	@addConstraint(m, sum{x[i, j], i=1:length(F)} == 1)
    end
    
    # for each facility, the fractional use by any client cannot exceed the fractional availability of the facility
    for i in 1:length(F)
	for j in 1:length(C)
	    @addConstraint(m, x[i, j] <= y[i])
	end
    end
    
    # the fractional sum of all facility availability cannot exceed k
    @addConstraint(m, sum{y[i], i=1:length(F)} <= k)
    
    # set the objective as minimizing the total cost for each client over the facilities they fractionally use
    @setObjective(m, Min, sum{d[i, j] * x[i, j], i=1:length(F), j=1:length(C)})
    solve(m);
    # amount of time to solve LP
    
    x = getValue(x);
    y = getValue(y);

    println("LP Optimal Value: ", getObjectiveValue(m));

    if (false)
	println("\n#################################################");
	print("LP Solution");
	println("\n#################################################\n");
	for i=1:size(x,1)
	    if (i == 1)
		print("x:\t");
		for j=1:size(d, 2)
		    @printf "%d\t\t" j;
		end		
		println();
	    end
	    print("$i\t");
	    for j=1:size(x,2)
		@printf "%6f\t" x[i, j];
	    end
	    println("\n");
	end
	for i=1:size(y, 1)
	    println("y[$i] = $(y[i])");
	end
    end
    
    ###############################################################
    ## Preliminary variables for rounding scheme
    ###############################################################

    keepF = Array(Bool, length(F));
    for i in keys(F)
        if (y[i] == 0.0)
            keepF[i] = false;
        else
            keepF[i] = true;
        end
    end
    
    # define a new set of F set variables denoted as F_j
    # the elements in F_j are determined by all of the possible facilities i such that
    # x_ij > 0 - interpret this as the set of facilities that j has a non zero probability of belonging to
    F_ = Dict{Int32, Dict{Int32, DataPoint}}();
    for j in keys(C)
	Fj = Dict{Int32, DataPoint}();
	for i in keys(F)
            if (!keepF[i]) continue; end;
	    if (x[i, j] > 0.0) 
		Fj[i] = F[i];
            end
	end
        F_[j] = Fj
    end
    
    # F_ is just a temporary variable, reassign F to another variable name
    xF = deepcopy(F);
    F = deepcopy(F_);
    
    # define a volumne function for any variable F' in F that is the sum of y_i in F'
    function vol(Fp::Dict{Int32, DataPoint})
	sum = 0;
	for i in keys(Fp)
	    sum = sum + y[i];
	end
	return sum;
    end
    
    # this is the average distance from j to F'
    function dist(j::Int32, Fp::Dict{Int32, DataPoint}) 
	sum = 0;
	for i in keys(Fp)
	    sum += y[i] * d[i, j];
	end
	return sum / vol(Fp);
    end
    
    # the connection cost of j in the fractional solution
    function dav(j::Int32)
	sum = 0;
	for i in keys(F[j])
	    sum += y[i] * d[i, j];
	end
	return sum;
    end
    
    # the set of facilities that have a distance strictly smaller than r to j
    function B(j::Int32, r::Float64)
	Bjr = Dict{Int32, DataPoint}();
	for i in keys(xF)
	    if (!keepF[i]) continue; end;
            if (d[i, j] < r)
		Bjr[i] = xF[i];
            end
	end
	return Bjr;
    end
    
    if (DEBUG)
	println("\n#################################################");
	print("Preliminary variables for rounding scheme");
	println("\n#################################################\n");
	println("C: \n");
	for key in sort(collect(keys(C)))
	    println("$key $(C[key])\n");
	end
	println("F: \n");
	for key in sort(collect(keys(F)))
	    println("F[$key]:");
	    for keyp in sort(collect(keys(F[key])))
		println("$keyp $((F[key])[keyp])\n");
	    end
	end
        
	println("All these volumes should >= 1.0");
	for key in sort(collect(keys(F)))
	    println("vol(F[$key]): $(vol(F[key]))");
	    if (vol(F[key]) < 1.0)
		println("Error");
		return;
	    end
	end
        
	println("\nConnection cost of j in the fractional solution");
	for key in sort(collect(keys(F)))
	    println("dav($key) = $(dav(key))");
	end
	println("\nThe set of facilities whose distance to j is less than 10.0");
	for j in sort(collect(keys(C)))
	    Bj = B(j, 10.0);
            println("$j:");
	    for i in sort(collect(keys(Bj)))
		@printf "%d %6f\n" i (d[i, j]);
		if (d[i, j] > 10.0) 
		    println("Error");
		    return;
                end
	    end
            println();
	end
    end
    
    ###############################################################
    ## Filtering Phase
    ###############################################################
    
    Cp = Dict{Int32, DataPoint}();
    Cpp = deepcopy(C);
    
    # get all of the average dictionary elements
    DAV = Dict{Int32, Float64}();
    for i in keys(C)
	davVal = dav(i);
        DAV[i] = davVal;
    end
    
    # really ugly, but no way to get sorted value key pairs
    hack_array = Array(Bool, length(xF));
    for i=1:length(hack_array)
        hack_array[i] = false;
    end
    for val in sort(collect(values(DAV)))
        j = 0;
        for hack in sort(collect(keys(DAV)))
            if (DAV[hack] == val && !hack_array[hack]) hack_array[hack] = true; j = hack; break; end;
        end        
        if (j == 0) println("Error with hack around line 277\n"); return; end;
        # only consider j still in C''
	if (get(Cpp, j, 0) != 0)
	    # add j to C'
	    Cp[j] = Cpp[j];
            for jp in keys(Cpp)
		if (dC[j, jp] <= 4 * dav(jp))
		    delete!(Cpp, jp);
		end
	    end
	end
	# delete j from C''
	delete!(Cpp, j);
    end
    
    if (DEBUG)
	println("\n#################################################");
	print("Filtering Phase");
	println("\n#################################################\n");
	println("C': \n");
	for key in sort(collect(keys(Cp)))
	    println("$key $(Cp[key])\n");
	end
	println("\nC'' should be null");
	println("C'': \n");
	for key in sort(collect(keys(Cpp)))
	    println("$key $(Cpp[key])\n");
	end
	if (length(Cpp) != 0)
	    println("Error\n");
	    return;
	end
    end
    
    ###############################################################
    ## Bundling Phase
    ###############################################################
    
    # each client j in C' should be assigned a set of facilities in large volume
    U = Dict{Int32, Dict{Int32, DataPoint}}();
    for j in keys(Cp)
	U[j] = Dict{Int32, DataPoint}();
    end
    
    # R is half the distance of j to its nearest neighbor in C'
    R = Dict{Int32, Float64}();
    for j in keys(Cp)
	min = typemax(Float64);
	for jp in keys(Cp)
	    if (j == jp) continue; end;
	    if (dC[j, jp] < min)
		min = dC[j, jp];
	    end
	end
        R[j] = 0.5 * min;
    end
    
    # get Fj' for each j in Cp
    Fp = Dict{Int32, Dict{Int32, DataPoint}}();
    FAll = Dict{Int32, DataPoint}();
    for j in keys(Cp)
	Fj = get(F, j, 0);
	if (Fj == 0) println("Error, F[$j] does not exist\n"); return; end
	Bj = B(j, RMax * get(R, j, 0));
	# find the intersection between these two sets Fj and Bj
	Fpj = Dict{Int32, DataPoint}();
	for i in keys(Fj)
	    if (get(Bj, i, 0) != 0)
		Fpj[i] = Bj[i];
                FAll[i] = Bj[i];
            end
	end
	# add this intersection to F'
        Fp[j] = Fpj;
    end
    
    # go through all facilities to see if they belong to a F'
    FAllDist = Array(Float64, length(xF));
    FAllClosest = Array(Array{Int32}, length(xF));
    for i=1:length(xF)
	FAllDist[i] = typemax(Float64);
	FAllClosest[i] = Array(Int32, 0);
	if (get(FAll, i, 0) == 0) continue; end
	# go through all clients in Cp
	for j in keys(Cp)
	    Fpj = Fp[j];
	    if (get(Fpj, i, 0) == 0) continue; end;
	    if (d[i, j] > FAllDist[i]) continue; end;
	    FAllDist[i] = d[i, j];
	    FAllClosest[i] = vcat(FAllClosest[i], j);
	end
    end
    
    # add the FAllClosest
    for i=1:length(xF)
	if (length(FAllClosest[i]) == 0) continue; end;
	closest = FAllClosest[i][rand(1:length(FAllClosest[i]))];
	Uj = get(U, closest, 0);
	if (Uj == 0) println("Error, j not in C'\n"); return; end;
	get!(Uj, i, xF[i]);
    end
    
    if (DEBUG)
	println("\n#################################################");
	print("Bundling Phase");
	println("\n#################################################\n");
	println("R': \n");
	for key in sort(collect(keys(R)))
	    @printf "%d %6f\n" key R[key];
	end
	println("\nF': \n")
	for key in sort(collect(keys(Fp)))
	    println("F'[$key]:");
	    Fpj = Fp[key];
	    for keyp in sort(collect(keys(Fpj)))
		println("$keyp $(Fpj[keyp])\n");
	    end
	end
	println("\nThis list should include all of the facilities in F'");
	for key in sort(collect(keys(FAll)))
	    println("$key $(FAll[key])")
	end
	println("\nList of closest facilities to those in F'");
	for i=1:length(FAllDist)
	    @printf "%d\t%6f:" i FAllDist[i];
	    for j=1:length(FAllClosest[i])
		print("\t$(FAllClosest[i][j]),")
	    end
	    println();
	end
	println("\nU: \n");
	for j in sort(collect(keys(U)))
	    println("U[$j]: ");
	    Uj = get(U, j, 0);
	    for key in sort(collect(keys(Uj)))
		println("$key $(Uj[key])");
	    end
	end
	## make sure that all of the volumes of Uj are between 0.5 and 1.0
	println("\nConfirming volumes of Uj ...");
	for j in sort(collect(keys(U)))
	    if (vol(U[j]) < 0.5 || vol(U[j]) > 1.0) println("Error: vol(U[$j]) violates assumption"); return; end;
	end
	println("Confirmed.\n");
    end
    
    ###############################################################
    ## Matching Phase
    ###############################################################
    
    pairs = (length(Cp) * (length(Cp) - 1)) / 2;
    Mp = Array(Match, iround(pairs));
    count = 1;
    
    for j in keys(Cp)
	for jp in keys(Cp)
	    if (j <= jp) continue; end;
	    Mjjp = Match(j, jp, dC[j, jp]);
	    Mp[count] = Mjjp;
	    count += 1;
	end
    end
    
    # custom sort function for Matches
    function MSort(a::Match, b::Match)
	if (a.d < b.d) return true;
	else return false; end;
    end
    
    sort!(Mp, lt=MSort, alg=QuickSort);
    
    # make sure everything is only in one match
    matched = Array(Bool, nc);
    for i=1:length(matched)
	if (get(Cp, i, 0) == 0) matched[i] = true;
	else matched[i] = false; end;
    end
    
    M = Dict{Int32, Match}();
    count = 1;
    for i=1:length(Mp)
	j = Mp[i].j;
	jp = Mp[i].jp;
	if (matched[j] || matched[jp]) continue; end;
	matched[j] = true;
	matched[jp] = true;
	M[count] = Mp[i];
        count += 1;
    end
    
    # see if there is anything left out of M
    for i=1:length(matched)
	if (!matched[i])
	    M1 = Match(i, 0, 0);
            M[count+1] = M1;
	end
    end
    
    if (DEBUG)
	println("\n#################################################");
	print("Matching Phase");
	println("\n#################################################\n");
	println("M:\n");
	for key in sort(collect(keys(M)))
	    Mp = M[key];
	    if (Mp.jp == 0)
		@printf "%d" Mp.j;
	    else
		@printf "%d\t%d\t%6f\n" Mp.j Mp.jp Mp.d;
	    end
	end
    end
    
    ###############################################################
    ## Sampling Phase
    ###############################################################
    
    function randSet(Uj)
        rnd = rand(1:length(Uj))
        i = 1;
        for fj in sort(collect(keys(Uj)))
            if (i == rnd)
                return fj;
            end
            i += 1
        end
    end

    # Create list of empty facilities
    kOpen = Array(Bool, length(xF));
    while (true) 
	num_open = 0;
	for i=1:length(xF)
	    kOpen[i] = false;
	end	   
        
	for key in sort(collect(keys(M)))
	    Mp = M[key];
	    j = Mp.j;
	    jp = Mp.jp;
	    if (Mp.jp != 0) 
		if (get(U, j, 0) == 0) println("Error, $j not in U"); return; end;
		if (get(U, jp, 0) == 0) println("Error, $jp not in U"); return; end;

		volUj = vol(U[j]);
		volUjp = vol(U[jp]);

		rnd = rand();
		if (rnd < 1 - volUjp) 
                    num_open += 1;
                    kOpen[randSet(U[j])] = true;
		elseif (rnd < (1 - volUjp) + (1 - volUj)) 
                    num_open += 1; 
                    kOpen[randSet(U[jp])] = true;
		else
                    num_open += 2;
                    kOpen[randSet(U[j])] = true;
		    kOpen[randSet(U[jp])] = true;
		end
	    else
		rnd = rand();
		if (get(U, j, 0) == 0) println("Error, $j not in U"); return; end;
		if (rnd < vol(U[j]))
                    num_open += 1;                    
                    kOpen[randSet(U[j])] = true;
		end
	    end
	end
        
	# for each facility not in bundle, open independently with probability yi
	for i=1:length(xF)
	    if (length(FAllClosest[i]) != 0) continue; end;
	    rnd = rand();
	    if (rnd < y[i])
		kOpen[i] = true;
		num_open += 1;
	    end
	end
        #println(num_open);
	if (num_open == k) break; end;
    end
    
    if (DEBUG)
	println("\n#################################################");
	print("Sampling Phase");
	println("\n#################################################\n");
	println("k open facilities:");
	for i=1:length(kOpen)
	    if (kOpen[i])
		println("$i $(xF[i])");
	    end
	end
    end
    
    medoidsOutput = Dict{Int64, Int64}();
    for i=1:length(kOpen)
	if (kOpen[i]) get!(medoidsOutput, i, i); end
    end
    medoids = sort(collect(keys(medoidsOutput)));
end