lib.locale()

Config = {}

Config.Debug = false

Config.DefaultShopPrice = 250000

Config.WarehouseRefreshTime = 24 * 60 * 60 * 1000 -- 24 hours in milliseconds

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
