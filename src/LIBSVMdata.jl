module LIBSVMdata

using Downloads
using LinearAlgebra
using OrderedCollections
using Printf
using SparseArrays

include("datasets.jl")

get_datasets() = DATASETS

"""
    get_datasets()
Return an OrderedDict with all the available datasets and their informations.
"""
function get_dataset_home()
    if "LIBSVMDATA_HOME" in keys(ENV)
        return ENV["LIBSVMDATA_HOME"]
    else
        return mkpath(joinpath(homedir(), "data/libsvm"))
    end
end

"""
    print_datasets()
Print all the datasets available in LIBSVMdata.jl with their type, the number 
of data, the number of features and the number of classes (or Inf for 
classification datasets).
"""
function print_datasets()
    datasets = get_datasets()
    println(repeat("=", 82))
    @printf "%-25s | %-15s | %-10s | %-10s | %-10s\n" "Dataset name" "Type" "Data" "Features" "Classes"
    println(repeat("-", 82))
    for (name, dataset) in datasets
        @printf "%-25s | %-15s | %-10d | %-10d | %-10d\n" name dataset[:type] dataset[:dims][1] dataset[:dims][2] dataset[:ncls]
    end
    println(repeat("=", 82))
end

"""
    load_dataset(
        dataset::String;
        dense::Bool=false,
        replace::Bool=false,
        normalize::Bool=false,
        verbose::Bool=true,
    )
Load a dataset, ie, return a feature matrix A and a response variable y. All 
the datasets are stored in the folder specified by the environnement variable
`LIBSVMDATA_HOME` if it exists. Otherwise, they are stored under 
`\$HOME/data/libsvm`. If a dataset is not found in the dataset directory, it is 
first downloaded and unzipped. 

# Arguments

* `dataset::String`: Name of the dataset. All the available datasets can be  
found using the `print_datasets()` function.
* `dense::Bool=false`: If `true`, the feature matrix A returned is dense. 
Otherwise, it is sparse.
* `replace::Bool=false`: If `true`, the dataset is re-downloaded even if it is 
found in the dataset directory.
* `normalize::Bool=false`: If `true`, the columns of the matrix A are normalized
to one. If the dataset is a regression one, the response y is also normalized to
one.
* `verbose::Bool=true`: If `true`, toogle verbosity.

# Example

Load a dataset :
```julia
using LIBSVMdata
using LIBSVM
using Printf
using Statistics

# Load a training and a testing dataset
Atrain, ytrain = load_dataset("a1a")
Atest, ytest = load_dataset("a1a.t")

# Use LIBSVM to fit a model (the feature matrix must be transposed with LIBSVM)
model = svmtrain(Atrain', ytrain)
ypred, xpred = svmpredict(model, Atest');
@printf "Accuracy: %.2f%%\n" 100 * mean(ypred .== ytest)
```
"""
function load_dataset(
    dataset::String;
    dense::Bool=false,
    replace::Bool=false,
    normalize::Bool=false,
    verbose::Bool=true,
    )

    # Test if the dataset is supported
    if !(dataset in keys(DATASETS))
        error(
            "The dataset '$dataset' is not yet supported. You can list the " *
            "available datasets using the 'print_datasets()' function. " *
            "Please report this error if you want the dataset '$dataset' to " *
            "be supported."
        )
    end

    # Extract dataset informations
    file = DATASETS[dataset][:file]
    type = DATASETS[dataset][:type]
    m, n = DATASETS[dataset][:dims]

    # Set useful path variables
    dataset_home = get_dataset_home()  
    dataset_path = joinpath(dataset_home, file)
    dataset_url  = joinpath(BASE_URL, type, file)

    # Check if the dataset exists and download it otherwise (or if replace=true)
    if !isfile(dataset_path)
        verbose && println("Downloading the dataset $dataset...")
        Downloads.download(dataset_url, dataset_path, verbose=verbose)
    elseif replace 
        verbose && println("Replacing the dataset $dataset...")
        Downloads.download(dataset_url, dataset_path, verbose=verbose)
    else
        verbose && println("The dataset $dataset is already downloaded")
    end

    # Unzip the dataset if needed
    if endswith(dataset_path, ".bz2")
        unzipped_dataset_path = string(join(split(dataset_path, ".")[begin:end-1]))
        !isfile(unzipped_dataset_path) && run(`bzip2 -d -k $dataset_path`)
        dataset_path = unzipped_dataset_path
    elseif endswith(dataset_path, ".tar.xz")
        unzipped_dataset_path = string(join(split(dataset_path, ".")[begin:end-2]))
        !isfile(unzipped_dataset_path) && run(`xz -d -k $dataset_path`)
        dataset_path = unzipped_dataset_path
    elseif endswith(dataset_path, ".xz")
        unzipped_dataset_path = string(join(split(dataset_path, ".")[begin:end-1]))
        !isfile(unzipped_dataset_path) && run(`xz -d -k $dataset_path`)
        dataset_path = unzipped_dataset_path
    end

    # Extract the dataset data
    verbose && println("Loading the dataset file...")
    multilabel = (type == "multilabel")
    A = dense ? zeros(m, n) : spzeros(m, n)
    V = multilabel ? Vector{Vector{Float64}} : Vector{Float64}
    y = V(undef, m)
    open(dataset_path, "r+") do file
        for (j, line) in enumerate(readlines(file))
            elements = split(line, " ")
            y[j] = multilabel ? parse.(Float64, string.(split(elements[1], ","))) : parse(Float64, elements[1])
            for element in elements[2:end]
                isempty(element) && continue
                s = split(element, ":")
                i = parse(Int, s[1])
                v = parse(Float64, s[2])
                A[j, i] = v
            end
        end
    end

    # Normalize data if needed
    if normalize
        for ai in eachcol(A)
            any(ai .!= 0.) && normalize!(ai)
        end
        (type == "regression") && normalize!(y)
    end

    return A, y
end

export get_datasets, print_datasets, load_dataset

end
