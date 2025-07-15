lib.locale()

Config = {}

Config.Debug = false

Config.DefaultShopPrice = 250000

Config.WarehouseRefreshTime = 24 * 60 * 60 * 1000 -- 24 hours in milliseconds

Config.Transport = {
    deliveryTime = 2 * 60 * 60 * 1000, -- 2 hours in milliseconds (configurable)
    expressDeliveryTime = 30 * 60 * 1000, -- 30 minutes in milliseconds
    expressCostMultiplier = 1.15, -- 15% extra cost for express delivery
    trailerModel = "tr4", -- Car trailer model
    truckModel = "phantom", -- Truck model
    maxVehiclesPerTrailer = 4, -- Maximum vehicles per trailer load
    minVehiclesForTrailer = 4, -- Minimum vehicles to require trailer transport
    trailerSpawn = vec4(1220.0, -3280.0, 6.0, 90.0), -- Trailer spawn location
    unloadZone = vec4(1190.0, -3260.0, 6.0, 90.0), -- Unload zone at warehouse
    freezeVehicles = true, -- Freeze vehicles when loaded on trailer
    protectDisconnect = true -- Protect trailer from other players when owner disconnects
}

Config.PriceVariation = {
    min = -10, -- -10% minimum price variation
    max = 20   -- +20% maximum price variation
}

Config.MaxTestDriveTime = 5 * 60 -- 5 minutes in seconds

Config.PlateFormat = "XXXXXXXX" -- X = random letter/number

Config.Warehouse = {
    entry = vec4(1200.0, -3250.0, 6.0, 90.0),
    exit = vec4(1175.0, -3250.0, 5.7, 270.0),
    camera = {
        start = vec3(1208.0, -3250.0, 10.0),
        rotation = vec3(-20.0, 0.0, 90.0)
    }
}

Config.VehicleCategories = {
    compacts = "Compacts",
    sedans = "Sedans",
    suvs = "SUVs",
    coupes = "Coupes",
    muscle = "Muscle",
    sportsclassics = "Sports Classics",
    sports = "Sports",
    super = "Super",
    motorcycles = "Motorcycles",
    offroad = "Off-road",
    industrial = "Industrial",
    utility = "Utility",
    vans = "Vans",
    cycles = "Cycles",
    boats = "Boats",
    helicopters = "Helicopters",
    planes = "Planes",
    service = "Service",
    emergency = "Emergency",
    military = "Military",
    commercial = "Commercial",
}

Config.FinanceOptions = {
    {
        label = "10% Down Payment",
        downPayment = 0.10,
        interest = 0.05,
        months = 12
    },
    {
        label = "20% Down Payment", 
        downPayment = 0.20,
        interest = 0.03,
        months = 6
    },
    {
        label = "30% Down Payment",
        downPayment = 0.30,
        interest = 0.02,
        months = 3
    }
}
