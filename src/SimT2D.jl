module SimT2D

using Distributions, DataFrames, Dates, Random

export simulate_cgm_t2d, cgm_delay_kernel, circadian_delay, generate_T2D_data

"""Generate synthetic CGM data for multiple subjects.
This function simulates CGM data for `N` subjects by calling `simulate_cgm_t2d`

Inputs:
- `N::Int=30`: Number of subjects to simulate (default 30).

Outputs:
- `DataFrame`: Combined glucose time series for all subjects.
- `DataFrame`: Combined event log for all subjects.
"""
function generate_T2D_data(N::Int=30)
    all_data = DataFrame()
    all_events = DataFrame()

    for i in 1:N
        df, events = simulate_cgm_t2d()
        df.subject = fill(i, nrow(df))       # Add subject ID to glucose data
        events.subject = fill(i, nrow(events))  # Add subject ID to events
        append!(all_data, df)
        append!(all_events, events)
    end

    return all_data, all_events
end

"""
Kernel function modeling delayed CGM glucose response.

This function returns the glucose impact at time `t` due to an input stimulus 
(e.g., carbohydrate intake or exercise) after a specified physiological delay.
The response follows a gamma-like rise and exponential decay pattern.

# Arguments
- `t::Int`: Time (in minutes) since the event was triggered.
- `delay::Real`: Onset delay before response begins (in minutes).
- `tau::Real`: Time constant governing the width of the response.
- `peak::Real`: Maximum effect size (scales total magnitude).
- `gain::Real=1.0`: Optional additional scaling factor (default 1.0).

# Returns
- `Float64`: Glucose impact at time `t`. Zero if `t < delay`.

# Notes
- The kernel is of the form: `gain × peak × ((t-delay)/τ)^γ × exp(-α(t-delay)/τ)`
- Global constants `gamma` and `alpha` define the response shape.
"""
function cgm_delay_kernel(t::Int, delay::Real, tau::Real, peak::Real, gain::Real=1.0)
    if t < delay
        return 0.0
    else
        shifted = max(t - delay, 0.0)
        shape = (shifted / tau)^gamma
        decay = exp(-alpha * shifted / tau)
        return gain * peak * shape * decay
    end
end

# Global constants for the CGM response kernel
gamma = 2.0
alpha = 0.72
const GLUCOSE_EFFECTIVENESS = 0.002

"""
Circadian delay function to model daily glucose variability.

Simulates the circadian rhythm’s effect on glucose response delay, modeled by a
cosine-modulated baseline with Gaussian noise. Delay is longer or shorter depending 
on time of day, peaking in early morning and reaching minimum in late afternoon.

# Arguments
- `t::Int`: Time in minutes since midnight (range: 0 to 1439).

# Returns
- `Int`: Circadian delay in minutes, clamped between 8 and 30.
"""
function circadian_delay(t::Int)
    base = 18.0 # Base delay in minutes
    amplitude = 4.0 # Amplitude of circadian modulation
    shift = 900 # Shift to center around 15:00 (3 PM)
    circadian = base + amplitude * cos(2π * (t - shift) / 1440) # 1440 minutes in a day
    delay = rand(Normal(circadian, 2.0)) # Add Gaussian noise
    return clamp(round(Int, delay), 8, 30) # Clamp between 8 and 30 minutes
end

"""
Simulate continuous glucose monitoring (CGM) data for a synthetic T2D subject.

# Arguments
- `days::Int=90`: Number of days to simulate (default 90).
- `baseline::Float64=135.0`: Baseline glucose level in mg/dL (default 135).
- `noise_std::Float64=10.0`: Standard deviation of sensor noise (default 10).
- `rng::AbstractRNG=Random.GLOBAL_RNG`: Random number generator (default global RNG).

# Returns 
- `DataFrame`: 5-minute sampled glucose time series with timestamps.
- `DataFrame`: Event log with timestamps and event types (meals, snacks, exercise, etc.).

# Notes
- The simulation includes meal responses, exercise effects, nocturnal hypoglycemia, 
  and random glucose anomalies.
- Glucose values are adjusted for physiological drift and sensor noise.
"""
function simulate_cgm_t2d(; days=90, baseline=135.0, noise_std=10.0, rng=Random.GLOBAL_RNG)
    # Initialize glucose time series and event log
    minutes_per_day = 1440
    total_minutes = days * minutes_per_day
    glucose = fill(baseline, total_minutes)
    time = 0:total_minutes-1
    base_meal_times = [(8 * 60, 60), (13 * 60, 70), (19 * 60, 80)]
    event_log = DataFrame(time_min=Int[], type=String[], value=Float64[], timestamp=DateTime[])

    # Simulate daily glucose dynamics
    for day in 0:days-1
        exercised_today = rand() < 0.4
        insulin_sensitivity = clamp(1.0 + 0.25 * sin(2π * day / 7) + rand(Normal(0.0, 0.15)), 0.5, 1.7)
        day_offset = rand(Normal(0, 14.0))
        day_start = day * minutes_per_day + 1
        day_end = (day + 1) * minutes_per_day
        glucose[day_start:day_end] .+= day_offset

        # Simulate meal events
        for (meal_minute, base_carbs) in base_meal_times
            if rand() < 0.07 # 7% chance of skipping breakfast
                continue
            end
            jitter = rand(-30:30) # Random jitter around meal time
            if rand() < 0.4
                base_carbs += rand(Uniform(25.0, 50.0))
            end

            # Simulate meal response
            carbs = base_carbs + rand(Normal(0, 25))
            multiplier = rand(truncated(Normal(1.1, 0.3), 0.6, 1.6)) # Insulin sensitivity multiplier
            peak = insulin_sensitivity * multiplier * carbs # Peak glucose increase
            start_idx = day * minutes_per_day + meal_minute + jitter # Adjusted meal time with jitter
            delay = circadian_delay(meal_minute) # Circadian delay for meal response
            decay_tau = rand(Uniform(15, 30)) # Decay time constant for meal response
            gain = rand(Uniform(0.9, 1.1)) # Gain factor for meal response

            # Log meal event
            push!(event_log, (start_idx, "meal", carbs, DateTime(2025, 1, 1) + Minute(start_idx)))
            for t in 0:180
                idx = start_idx + t
                if idx <= total_minutes
                    glucose[idx] += cgm_delay_kernel(t, delay, decay_tau, peak, gain)
                end
            end
        end

        # Simulate snacks, exercise, nocturnal hypoglycemia, and random anomalies
        for _ in 1:rand(2:8) # Random number of snacks per day
            snack_minute = rand(480:1320) # Snack time between 8 AM and 10 PM
            delay = circadian_delay(snack_minute) # Circadian delay for snack response
            carbs = rand(truncated(Normal(25, 10), 10, 35)) # Random snack carbs
            multiplier = rand(truncated(Normal(0.45, 0.08), 0.3, 0.7)) # Insulin sensitivity multiplier for snacks
            peak = insulin_sensitivity * multiplier * carbs # Peak glucose increase
            decay_tau = rand(Uniform(8, 20)) # Decay time constant for snack response
            idx = day * minutes_per_day + snack_minute # Snack index in total minutes

            # Log snack event
            push!(event_log, (idx, "snack", carbs, DateTime(2025, 1, 1) + Minute(idx)))
            for t in 0:100
                i = idx + t
                if i <= total_minutes
                    glucose[i] += cgm_delay_kernel(t, delay, decay_tau, peak)
                end
            end
        end

        # Simulate exercise effects
        if exercised_today # 40% chance of exercise
            ex_minute = rand(600:1080) # Exercise time between 10 AM and 6 PM
            idx = day * minutes_per_day + ex_minute # Exercise index in total minutes
            reduction = rand(Uniform(12.0, 26.0)) # Reduction in glucose due to exercise
            delay = circadian_delay(ex_minute) # Circadian delay for exercise response
            tau = rand(Uniform(22.0, 40.0)) # Decay time constant for exercise response

            # Log exercise event
            push!(event_log, (idx, "exercise", reduction, DateTime(2025, 1, 1) + Minute(idx)))
            for t in 0:80
                i = idx + t
                if i <= total_minutes
                    glucose[i] -= cgm_delay_kernel(t, delay, tau, reduction)
                end
            end
        end

        # Simulate nocturnal hypoglycemia
        if rand() < 0.6 # 60% chance of nocturnal hypoglycemia
            nh_minute = rand(120:300) # Random time between 2 AM and 5 AM
            idx = day * minutes_per_day + nh_minute # Nocturnal hypoglycemia index
            dip = rand(Uniform(6.0, 24.0)) # Glucose dip magnitude
            delay = circadian_delay(nh_minute) # Circadian delay for nocturnal hypoglycemia
            tau = rand(Uniform(28.0, 40.0)) # Decay time constant for nocturnal hypoglycemia

            # Log nocturnal hypoglycemia event
            push!(event_log, (idx, "night_hypo_mild", dip, DateTime(2025, 1, 1) + Minute(idx)))
            for t in 0:80
                i = idx + t
                if i <= total_minutes
                    glucose[i] -= cgm_delay_kernel(t, delay, tau, dip)
                end
            end
        end

        # Severe nocturnal hypoglycemia (rare)
        if rand() < 0.07 # 7% chance of severe nocturnal hypoglycemia
            nh_minute = rand(120:300) # Random time between 2 AM and 5 AM
            idx = day * minutes_per_day + nh_minute # Severe nocturnal hypoglycemia index
            dip = rand(Uniform(30.0, 50.0)) # Severe glucose dip magnitude
            delay = circadian_delay(nh_minute) # Circadian delay for severe nocturnal hypoglycemia
            tau = rand(Uniform(30.0, 50.0)) # Decay time constant for severe nocturnal hypoglycemia
            gain = rand(Uniform(1.0, 1.3)) # Gain factor for severe hypoglycemia

            # Log severe nocturnal hypoglycemia event
            push!(event_log, (idx, "night_hypo_severe", dip, DateTime(2025, 1, 1) + Minute(idx)))
            for t in 0:100
                i = idx + t
                if i <= total_minutes
                    glucose[i] -= cgm_delay_kernel(t, delay, tau, dip, gain)
                end
            end
        end

        # Random glucose anomalies (spikes and dips)
        for _ in 1:rand(8:12) # Random number of anomalies per day
            t_spike = rand(300:1320) # Random time between 5 AM and 10 PM
            idx = day * minutes_per_day + t_spike # Spike index in total minutes
            mag = rand(Uniform(20.0, 40.0)) # Spike magnitude
            tau = rand(Uniform(26.0, 38.0)) # Decay time constant for spike response
            delay = rand(Uniform(1.0, 5.0)) # Delay before spike response 

            # Log random spike event
            push!(event_log, (idx, "random_spike", mag, DateTime(2025, 1, 1) + Minute(idx)))
            for t in 0:50
                i = idx + t
                if i <= total_minutes
                    glucose[i] += cgm_delay_kernel(t, delay, tau, mag)
                end
            end
        end

        # Random glucose dips
        for _ in 1:rand(8:12) # Random number of dips per day
            t_dip = rand(300:1320) # Random time between 5 AM and 10 PM
            idx = day * minutes_per_day + t_dip # Dip index in total minutes
            mag = rand(Uniform(35.0, 55.0)) # Dip magnitude
            tau = rand(Uniform(26.0, 38.0)) # Decay time constant for dip response
            delay = rand(Uniform(1.0, 5.0)) # Delay before dip response

            # Log random dip event
            push!(event_log, (idx, "random_dip", mag, DateTime(2025, 1, 1) + Minute(idx)))
            for t in 0:50
                i = idx + t
                if i <= total_minutes
                    glucose[i] -= cgm_delay_kernel(t, delay, tau, mag)
                end
            end
        end
    end

    # Drift and smoothing
    drift = 0.0
    for t in 2:total_minutes
        drift = clamp(drift * 0.997 + rand(Normal(0.0, 0.6)), -18.0, 18.0)
        glucose[t] += drift
        glucose[t] += -GLUCOSE_EFFECTIVENESS * (glucose[t-1] - baseline)
    end

    # Add sensor noise
    sigma = rand(Uniform(0.6, 1.2))
    glucose .+= 0.7 .* rand(Normal(0, sigma), total_minutes)
    glucose .-= rand(Uniform(1.0, 3.0))

    for _ in 1:2
        for t in 2:(total_minutes-1)
            glucose[t] = 0.25 * glucose[t-1] + 0.5 * glucose[t] + 0.25 * glucose[t+1]
        end
    end

    # Create DataFrame for glucose time series
    df = DataFrame(time_min=time, glucose_mg_dL=glucose)
    df_5min = df[1:5:end, :]
    df_5min.timestamp = DateTime(2025, 1, 1) .+ Minute.(df_5min.time_min)
    return df_5min, event_log
end


end
