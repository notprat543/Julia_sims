using Pkg
Pkg.add(["StableRNGs","Distributions","DataStructures","Printf","Dates"])
using StableRNGs, Distributions, DataStructures, Printf, Dates

abstract type Event end     
struct Arrive <: Event    
    id::Int64         # a unique event id
    time::Float64     #the time of the event 
end 

struct Departure <: Event
    id::Int64 
    time::Float64   #[1896985]
end  

struct Brkdwn <: Event 
    id::Int64 
    time::Float64 
end 

struct Repair <: Event 
    id::Int64 
    time::Float64 
end

mutable struct Entity
    id::Int64               
    arrival_time::Float64  
    start_service::Float64   
    end_service::Float64    
    interrupted::Bool       # to track which metal sheet is interrupted
end 

mutable struct State
    time::Float64                                   # Simulation time
    event_queue::PriorityQueue{Event, Float64}      # to keep track of future events
    waiting::Queue{Entity}                          #keep track of the queue
    in_service::PriorityQueue{Entity,Float64}       #keep track of the metal in service
    n_entities::Int64                               #number of entities to have been served
    num_events::Int64                               #to track the number of events that occured and queued
    breakdown_status::Bool                          # True if laser cutter breaks down, false if it is operational
end 


State()=State(0.0,PriorityQueue{Event, Float64}(),Queue{Entity}(),PriorityQueue{Entity,Float64}() ,0,0,false)
sheet_metal_unit(id,arrival_time) = Entity(id,arrival_time,0.0,0.0,false)

#paramters
struct Params
    seed::Int
    av_interarrival::Float64    # lambda1
    av_cutting_time::Float64    # lambda2
    av_breakdown_time::Float64  # lambda3
    av_fixing_time::Float64     # lambda4
end


#Random number generator
struct RandNGs
    rng::StableRNGs.LehmerRNG
    interarrival_t::Function
    cutting_t::Function
    breakdown_t::Function
    fixing_t::Function
end

# Constructor function to generate rnums
function RandNGs(Ps::Params)
    rng = StableRNG(Ps.seed)
    interarrival_t() = rand(rng, Exponential(Ps.av_interarrival))
    cutting_t() = Ps.av_cutting_time
    breakdown_t() = rand(rng, Exponential(Ps.av_breakdown_time))
    fixing_t() = rand(rng, Exponential(Ps.av_fixing_time))    
    return RandNGs(rng, interarrival_t, cutting_t, breakdown_t, fixing_t)
end

# initialise function
function initialise(Ps::Params)
    Rnums = RandNGs(Ps)
    system = State()

    t0  =   0.0
    system.num_events += 1
    enqueue!(system.event_queue,Arrive(1,t0),t0)

    t1  =  113
    system.num_events+=1
    enqueue!(system.event_queue,Brkdwn(system.num_events,t1),t1)
    
    return  (system,Rnums)
end

# To check if a laser cutter is in process of cutting a sheet  metal unit
servers_full(system) = length(system.in_service)>=1

# When the laser cutter is free, this moves a sheet metal unit into the cutter 
function move_metal_sheet_in_service!(S::State,R::RandNGs)
    sheet = dequeue!(S.waiting)
    sheet.start_service = S.time
    sheet.end_service = sheet.start_service + R.cutting_t()
    enqueue!(S.in_service,sheet,sheet.end_service)
    S.num_events+=1
    departure_event = Departure(S.num_events, sheet.end_service)
    enqueue!(S.event_queue, departure_event, sheet.end_service)
end

# Generic updater function for wrong inputs
function updater!(S::State,R::RandNGs,E::Event)
    throw(DomainError("invalid input"))
end

# when Event is an arrival
function updater!(S::State,R::RandNGs,E::Arrive)
    S.time = E.time
    S.n_entities +=1

    #new metal sheet
    new_sheet = sheet_metal_unit(S.n_entities,E.time)
    enqueue!(S.waiting,new_sheet)

    #next arrival
    S.num_events +=1
    future_arrival=Arrive(S.num_events, S.time + R.interarrival_t())
    enqueue!(S.event_queue, future_arrival, future_arrival.time)

    # to check if laser cutter is free
    if !servers_full(S) && !S.breakdown_status
        move_metal_sheet_in_service!(S,R)
    end

    return new_sheet
end

# When Event is a departure
function updater!(S::State,R::RandNGs,E::Departure)
    if !S.breakdown_status
        S.time=E.time
        departing_sheet = dequeue!(S.in_service)
        departing_sheet.end_service = S.time

        # to check if laser cutter is free and operational
        if !isempty(S.waiting) && !S.breakdown_status
            move_metal_sheet_in_service!(S,R)
        end
    return departing_sheet
    
    end
end

# When event is 
function updater!(S::State,R::RandNGs,E::Brkdwn)
    S.time=E.time
    S.breakdown_status = true
    fixing_time=R.fixing_t()

    if servers_full(S)
        entity, _ = first(S.in_service)
        updated_time = entity.end_service + fixing_time

        # updating the event queue        
        for (event, t) in S.event_queue
            if event isa Departure && event.time == entity.end_service
                dequeue!(S.event_queue, event)
                new_departure_event=Departure(event.id,updated_time)
                enqueue!(S.event_queue, new_departure_event, updated_time)
            end
        end
        # updating the service time for metal sheet in service
        dequeue!(S.in_service)
        entity.end_service = updated_time
        entity.interrupted = true
        enqueue!(S.in_service,entity,entity.end_service)

        # Adding a new repair event
        S.num_events+=1
        repair_event = Repair(S.num_events, S.time + fixing_time)
        enqueue!(S.event_queue,repair_event,repair_event.time)

    else
        # Adding a new repair event
        S.num_events+=1
        repair_event = Repair(S.num_events, S.time + fixing_time)
        enqueue!(S.event_queue,repair_event,repair_event.time)

    end

end

function updater!(S::State, R::RandNGs,E::Repair)
    S.time = E.time
    S.breakdown_status = false

    # moving a new sheet metal unit to the cutter, if free and operational
    if !servers_full(S) && !isempty(S.waiting)
        move_metal_sheet_in_service!(S,R)
    end

    # Adding a new breakdown event
    S.num_events+=1
    breakdown_event = Brkdwn(S.num_events,  S.time + R.breakdown_t())
    enqueue!(S.event_queue, breakdown_event, breakdown_event.time)

end


# Helper function to write entities
function write_entity(fid::IO,entity::Entity,E::Event)
    interruption = entity.interrupted ? 1 : 0
    println(fid,"$(entity.id),$(interruption),$(round(entity.arrival_time,digits=3)),$(round(entity.start_service,digits=3)),$(round(entity.end_service,digits=3))")
end

# Helper function to write states
function write_state(fid::IO,S::State,E::Event)
    cutting_status = servers_full(S) && !S.breakdown_status ? 1 : 0
    println(fid,"$(round(S.time;digits=3)),$(E.id),$(typeof(E)),$(cutting_status),$(S.num_events),$(S.n_entities),$(length(S.waiting))")
end

# Helper function to make directories and output files
function output_files(Ps::Params)
    dir = pwd() * "/data/seed$(Ps.seed)" 
    file_entities = dir * "/entities$(Ps.seed).csv"
    file_state = dir * "/state$(Ps.seed).csv" 
    return file_entities, file_state, dir
end

# runsim! function
function runsim!(S::State, Rnums::RandNGs, allT::Float64,fileID_state::IO,fileID_entities::IO)
    while S.time < allT 
        event,_=peek(S.event_queue)
        S.time=event.time
        
        # write states
        write_state(fileID_state,S,event)

        event = dequeue!(S.event_queue)

        # to check the type of event
        if event isa Arrive
             updater!(S,Rnums,event)

        elseif event isa Departure
            if !S.breakdown_status
                entity=updater!(S,Rnums,event)
                write_entity(fileID_entities,entity,event)  
                
            end 

        elseif event isa Brkdwn
            updater!(S,Rnums,event)

        elseif event isa Repair
            updater!(S,Rnums,event)

        end
    end 
    return S
end

# runing the simulation
function run_kithome_sim(Ps::Params,allT::Float64,)
    # metadata
    (system, Rnums) = initialise(Ps)

    file_entities, file_state, dir = output_files(Ps)


    mkpath(dir)
    fileID_state=open(file_state,"w")
    fileID_entities=open(file_entities,"w")
    #state
    println(fileID_state, "# file created by code in kitsim_fns_1896985.jl")
    println(fileID_state, "# file created on $(Dates.format(now(),"yyyy-mm-dd")) at $(Dates.format(now(),"HH:MM:SS"))")
    println(fileID_state,"# parameter: seed = $(Ps.seed)")
    println(fileID_state,"# parameter: av_interarrival =$(Ps.av_interarrival)")
    println(fileID_state,"# parameter: av_cutting_time =$(Ps.av_cutting_time)")
    println(fileID_state,"# parameter: av_breakdown_time =$(Ps.av_breakdown_time)")
    println(fileID_state,"# parameter: av_repair_time =$(Ps.av_fixing_time)")
    println(fileID_state,"# T=$(allT)")
    println(fileID_state,"# units = minutes")
    println(fileID_state,"t,EV_id,EV_type,cutting_status,num_events,num_service,num_queue")

    #entities
    println(fileID_entities, "# file created by code in kitsim_fns_1896985.jl")
    println(fileID_entities, "# file created on $(Dates.format(now(),"yyyy-mm-dd")) at $(Dates.format(now(),"HH:MM:SS"))")
    println(fileID_entities,"# parameter: seed = $(Ps.seed)")
    println(fileID_entities,"# parameter: av_interarrival =$(Ps.av_interarrival)")
    println(fileID_entities,"# parameter: av_cutting_time =$(Ps.av_cutting_time)")
    println(fileID_entities,"# parameter: av_breakdown_time =$(Ps.av_breakdown_time)")
    println(fileID_entities,"# parameter: av_repair_time =$(Ps.av_fixing_time)")
    println(fileID_entities,"# T=$(allT)")
    println(fileID_entities,"# units = minutes")
    println(fileID_entities,"# Id,interrupted,arrive_time,cutting_status,cutting_end_time ")

    system = runsim!(system,Rnums, allT,fileID_state, fileID_entities)

    close(fileID_state)
    close(fileID_entities)

end

