using SimT2D
using Documenter

DocMeta.setdocmeta!(SimT2D, :DocTestSetup, :(using SimT2D); recursive=true)

makedocs(;
    modules=[SimT2D],
    authors="everval <eduardo.vera@gmail.com> and contributors",
    sitename="SimT2D.jl",
    format=Documenter.HTML(;
        canonical="https://everval.github.io/SimT2D.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/everval/SimT2D.jl",
    devbranch="main",
)
