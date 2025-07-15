# Advanced Vehicle Shop

A comprehensive, modular vehicle shop system for FiveM using QBCore framework with ox_lib integration.

## Features

### Core Systems
- **Modular Architecture**: Clean separation of concerns with 14 specialized modules
- **Real-time Sync**: GlobalState synchronization for instant updates across all clients
- **Secure Callbacks**: Server-side validation for all sensitive operations
- **Performance Optimized**: Uses ox_lib zones, points, and efficient caching
- **Shop-specific Transport**: Each shop has its own garage, unload, and stock points

### Shop Management
- **Dynamic Shop Creation**: Admin command to create shops with customizable zones
- **Multiple Zone Types**: Entry, management, vehicle spawn, and camera positions
- **Shop Ownership**: Players can purchase and own vehicle shops
- **Employee Hierarchy**: 4-tier rank system (Sales Associate, Senior Sales, Manager, Owner)
- **Permission-based Access**: Different features available based on employee rank

### Inventory & Sales
- **Warehouse System**: Central warehouse with dynamic stock and price variations
- **Stock Management**: Purchase vehicles from warehouse to shop inventory
- **Transport System**: Dual transport modes - automatic delivery or manual trailer transport
- **Display Vehicles**: Place vehicles on display with interactive placement mode
- **Sales Tracking**: Comprehensive sales statistics and commission system
- **Multiple Payment Options**: Cash purchases and financing with down payments

### Customer Experience
- **Interactive Catalog**: Browse vehicles by category with detailed information
- **Test Drive System**: Timed test drives with automatic vehicle return
- **Finance Calculator**: Multiple financing plans with interest calculations
- **Vehicle Delivery**: Automatic vehicle spawn upon purchase

### Financial Management
- **Shop Funds**: Deposit/withdraw system for shop finances
- **Commission System**: Automatic commission calculation based on employee rank
- **Transaction History**: Track all financial movements
- **Sales Reports**: Generate detailed reports by date range
- **Vehicle Financing**: Complete loan system with monthly payments
- **Automatic Collections**: Automated payment processing for financed vehicles
- **Repossession System**: Vehicles repossessed after 3 missed payments

## Dependencies

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- [qb-core](https://github.com/qbcore-framework/qb-core)

## Installation

1. Download the resource
2. Place in your resources folder
3. Add `ensure advanced-vehicleshop` to your server.cfg
4. Run the server to create database tables automatically

## Commands

- `/createshop` - Create a new vehicle shop (Admin only)

## Shop Creation Process

1. Use `/createshop` command
2. Enter shop name and price
3. Set entry location
4. Set management location
5. Set vehicle spawn location
6. Set camera location for previews
7. Confirm creation

## Module Structure

```
advanced-vehicleshop/
├── client/
│   └── init.lua
├── server/
│   └── init.lua
├── shared/
│   └── init.lua
├── modules/
│   ├── database/
│   ├── shops/
│   ├── warehouse/
│   ├── employees/
│   ├── vehicles/
│   ├── funds/
│   ├── sales/
│   ├── finance/
│   ├── prices/
│   ├── testdrive/
│   ├── management/
│   ├── creator/
│   ├── transport/
│   ├── garage/
│   └── ui/
├── locales/
│   └── en.json
└── fxmanifest.lua
```

## Employee Ranks & Permissions

### Rank 1 - Sales Associate
- View shop stock
- Sell vehicles to customers
- Earn 5% commission on sales

### Rank 2 - Senior Sales
- All Rank 1 permissions
- Add/remove display vehicles
- View sales statistics
- Earn 7% commission on sales

### Rank 3 - Manager
- All Rank 2 permissions
- Hire/fire employees
- Manage employee ranks
- Deposit shop funds
- View detailed sales reports
- Earn 10% commission on sales

### Rank 4 - Owner
- All permissions
- Withdraw shop funds
- Transfer ownership
- Full shop control
- Earn 15% commission on sales

## Transport System

The transport system offers two methods for moving vehicles from warehouse to shop:

### Automatic Delivery
- **Standard Delivery**: Configurable delivery time (default: 2 hours)
- **Express Delivery**: Faster delivery with additional cost (default: 30 minutes)
- **Automatic Processing**: Vehicles added to shop stock automatically

### Manual Trailer Transport
- **Car Trailer**: Spawn truck and trailer for manual transport
- **Flatbed Transport**: Single vehicle transport with flatbed truck
- **Vehicle Loading**: Interactive system to load vehicles onto trailer
- **Trailer Controls**: Lower/raise trailer, freeze vehicles during transport
- **Manual Unloading**: Players must manually unload vehicles at shop
- **Stock Management**: Vehicles must be manually moved to stock point
- **Disconnect Protection**: Trailer protected when owner disconnects
- **Capacity**: Configurable maximum vehicles per trailer (default: 4)

### Transport Garage System
- **Shop-specific Garage**: Each shop has its own garage point for transport vehicles
- **Garage Access**: Only shop employees can access garage
- **Vehicle Spawn**: Spawn trailer or flatbed trucks at designated points
- **Unload Zone**: Designated area for unloading vehicles from transport
- **Stock Point**: Separate point for storing vehicles in shop inventory
- **Interactive Points**: ox_lib points for seamless interaction

## Configuration

Edit `shared/init.lua` to configure:
- Default shop price
- Warehouse refresh time
- Price variation range
- Test drive duration
- Finance options
- Vehicle categories
- Plate format
- Transport delivery times
- Trailer models and capacity
- Express delivery cost multiplier

## Display Vehicle Placement System

### Overview
The display vehicle placement system allows employees (Rank 2+) to position vehicles around the shop for display. This system provides an intuitive, real-time preview with distance and rotation controls.

### Placement Controls
- **Mouse Movement**: Aim camera to position vehicle
- **Mouse Wheel Up/Down**: Adjust distance (5-50 meters)
- **Left/Right Arrow Keys**: Rotate vehicle
- **E Key**: Confirm placement
- **X Key**: Cancel placement

### Placement Features
- **Real-time Preview**: Semi-transparent vehicle preview
- **Distance Control**: Adjustable placement distance from 5 to 50 meters
- **Ground Detection**: Automatic ground positioning with raycast
- **Collision Detection**: Prevents placement near other vehicles
- **Validity Indicators**: Visual feedback for valid/invalid placement
- **Shop Boundary Check**: Ensures vehicles stay within shop area

### Placement Validation
The system checks several conditions before allowing placement:
- Distance from shop center (max 100 meters)
- Proximity to other vehicles (min 5 meters)
- Valid ground surface
- No obstacles in placement area

### Visual Feedback
- **Green Marker**: Valid placement location
- **Red Marker**: Invalid placement location
- **Text Display**: Shows placement status and any issues
- **Vehicle Transparency**: Changes based on placement validity

## Usage Guide

### For Shop Owners
1. Purchase an available shop at the entry point
2. Access management menu at the management zone
3. Purchase vehicles from warehouse to build inventory
4. Hire employees to help with sales
5. Monitor sales and manage funds

### For Employees
1. Get hired by a shop owner/manager
2. Help customers browse and purchase vehicles
3. Manage display vehicles (Rank 2+)
   - Add vehicles from inventory to display
   - Use placement mode to position vehicles
   - Remove or update display vehicles
4. Track your sales performance
5. Earn commission on each sale

### For Customers
1. Visit any vehicle shop
2. Browse available vehicles by category
3. Test drive vehicles before purchase
4. Choose between cash or finance options
5. Receive your vehicle at the spawn point
