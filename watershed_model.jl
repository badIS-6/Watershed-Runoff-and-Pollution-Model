# Watershed Runoff and Pollution Assessment

# Model: SCS Curve Number runoff estimation
# Outputs: runoff volume, TSS load, total nitrogen load


struct LandUse
    name::String
    area_ha::Float64
    curve_number::Float64
    tss_emc::Float64      
    nitrogen_emc::Float64  
    retention::Float64    
end

struct RainEvent
    name::String
    rainfall_mm::Float64
end

function validate_data(landuses, events)
    isempty(landuses) && error("Land-use data is empty.")
    isempty(events) && error("Rainfall data is empty.")

    for land in landuses
        land.area_ha > 0 || error("Area must be positive.")
        0 < land.curve_number <= 100 ||
            error("Curve number must be in (0, 100].")
        land.tss_emc >= 0 || error("TSS EMC cannot be negative.")
        land.nitrogen_emc >= 0 ||
            error("Nitrogen EMC cannot be negative.")
        0 <= land.retention <= 1 ||
            error("Retention must be between 0 and 1.")
    end

    for event in events
        event.rainfall_mm >= 0 ||
            error("Rainfall cannot be negative.")
    end
end

# SCS-CN runoff equation
function runoff_depth(rainfall_mm, cn)
    storage = 25400 / cn - 254
    initial_abstraction = 0.2 * storage

    if rainfall_mm <= initial_abstraction
        return 0.0
    end

    return (rainfall_mm - initial_abstraction)^2 /
           (rainfall_mm + 0.8 * storage)
end

function simulate(landuses, events; retention_enabled=false)
    results = NamedTuple[]

    for event in events, land in landuses
        q_mm = runoff_depth(event.rainfall_mm, land.curve_number)

        # 1 mm over 1 hectare = 10 m³
        gross_volume = q_mm * land.area_ha * 10

        capture = retention_enabled ? land.retention : 0.0
        captured_volume = gross_volume * capture
        final_volume = gross_volume - captured_volume

        # EMC approximation: 1 mg/L = 0.001 kg/m³
        tss_kg = final_volume * land.tss_emc / 1000
        nitrogen_kg = final_volume * land.nitrogen_emc / 1000

        push!(results, (
            event = event.name,
            landuse = land.name,
            rainfall_mm = event.rainfall_mm,
            runoff_mm = q_mm,
            gross_m3 = gross_volume,
            captured_m3 = captured_volume,
            runoff_m3 = final_volume,
            tss_kg = tss_kg,
            nitrogen_kg = nitrogen_kg
        ))
    end

    return results
end

function summarize(results)
    return (
        runoff_m3 = sum(r.runoff_m3 for r in results),
        captured_m3 = sum(r.captured_m3 for r in results),
        tss_kg = sum(r.tss_kg for r in results),
        nitrogen_kg = sum(r.nitrogen_kg for r in results)
    )
end

function print_report(title, results)
    totals = summarize(results)

    println("\n", "="^54)
    println(title)
    println("="^54)
    println("Runoff volume:     ",
            round(totals.runoff_m3, digits=1), " m³")
    println("Captured runoff:   ",
            round(totals.captured_m3, digits=1), " m³")
    println("TSS load:          ",
            round(totals.tss_kg, digits=2), " kg")
    println("Total nitrogen:    ",
            round(totals.nitrogen_kg, digits=2), " kg")

    println("\nEvent and land-use breakdown:")
    println("Event | Land use | Runoff (m³) | TSS (kg) | N (kg)")

    for r in results
        println(
            "$(r.event) | $(r.landuse) | ",
            "$(round(r.runoff_m3, digits=1)) | ",
            "$(round(r.tss_kg, digits=2)) | ",
            "$(round(r.nitrogen_kg, digits=2))"
        )
    end

    return totals
end

# hypothetical land-use inventory:

landuses = [
    LandUse("Urban",      25.0, 90.0, 120.0, 2.0, 0.25),
    LandUse("Agriculture",40.0, 78.0,  80.0, 5.0, 0.15),
    LandUse("Forest",     35.0, 55.0,  15.0, 0.8, 0.05)
]

events = [
    RainEvent("Storm A", 15.0),
    RainEvent("Storm B", 35.0),
    RainEvent("Storm C", 60.0)
]

validate_data(landuses, events)

baseline = simulate(landuses, events)
mitigation = simulate(landuses, events; retention_enabled=true)

base_totals = print_report("BASELINE SCENARIO", baseline)
mit_totals = print_report("RETENTION SCENARIO", mitigation)

println("\nRETENTION IMPACT")
for (label, before, after) in [
    ("Runoff", base_totals.runoff_m3, mit_totals.runoff_m3),
    ("TSS", base_totals.tss_kg, mit_totals.tss_kg),
    ("Nitrogen", base_totals.nitrogen_kg, mit_totals.nitrogen_kg)
]
    reduction = before > 0 ? 100 * (before - after) / before : 0.0
    println("$label reduction: ", round(reduction, digits=2), "%")
end
