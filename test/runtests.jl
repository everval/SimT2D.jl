using SimT2D
using Test

@testset "SimT2D.jl" begin
    # Write your tests here.
    @test size(generate_T2D_data(2),1) == 2
    @test size(generate_T2D_data(23),1) == 2
end
