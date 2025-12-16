# Geopy Integration for Ormoc Barangay Distance Calculation

This system now uses the **Geopy API** for accurate geographic distance calculations between Cabintan (reference point) and all other Ormoc barangays.

## 🗺️ **Overview**

- **Reference Point**: Barangay Cabintan, Ormoc City
- **Distance Calculation**: Uses geodesic distance (most accurate for geographic coordinates)
- **Data Source**: OpenStreetMap via Nominatim geocoder
- **Separation**: Cabintan is treated as the reference endpoint, separate from delivery areas

## 🚀 **Setup Instructions**

### 1. Install Python Dependencies
```bash
pip install -r requirements.txt
```

### 2. Run Distance Calculation
```bash
# Windows
calculate-distances.bat

# Or manually
python geopy-distance-calculator.py
```

### 3. Generated Files
After running the calculation, you'll get:
- `ormoc_barangays_with_distances.json` - JSON data with coordinates and distances
- `ormoc-barangays-geopy.js` - JavaScript file for web integration

## 📊 **Zone Classification**

Based on geodesic distance from Cabintan:

| Zone | Distance Range | Suggested Fee | Description |
|------|---------------|---------------|-------------|
| **Core** | 0-2 km | ₱30 | Core urban area around Cabintan |
| **Urban** | 2-5 km | ₱40 | Urban barangays |
| **Near Urban** | 5-10 km | ₱60 | Suburban areas |
| **Rural** | 10-15 km | ₱80 | Rural barangays |
| **Remote** | 15+ km | ₱100 | Remote areas |
| **Reference** | 0 km | ₱0 | Cabintan (no delivery fee) |

## 🔧 **Integration with Staff Dashboard**

### Updated Features:
1. **Reference Point Display**: Shows Cabintan coordinates and information
2. **Accurate Distances**: All distances calculated using geographic coordinates
3. **Zone-based Filtering**: Filter barangays by distance zones
4. **Separated Management**: Cabintan treated as reference, not delivery area

### Key Methods:
- `GeopyBarangayUtils.getDeliveryAreas()` - Get all delivery areas (excluding Cabintan)
- `GeopyBarangayUtils.getReferencePoint()` - Get Cabintan reference data
- `GeopyBarangayUtils.getSuggestedFee(distance)` - Get fee based on distance

## 🌐 **API Endpoints**

The customer app can now access:

### Delivery Fees
```javascript
// Get all delivery fees
GET /delivery-fees

// Get fee for specific barangay
GET /delivery-fee/{barangay}

// Calculate total delivery cost
GET /calculate-delivery/{barangay}/{orderValue}
```

### Barangay Data
```javascript
// Get all barangay data with coordinates
GET /barangay-data

// Get reference point (Cabintan)
GET /reference-point
```

## 📍 **Geographic Accuracy**

### Advantages of Geopy:
- **Precise Coordinates**: Uses OpenStreetMap data
- **Real Distance**: Geodesic calculations account for Earth's curvature
- **Automatic Updates**: Can recalculate when needed
- **Fallback Support**: Includes fallback coordinates if geocoding fails

### Coordinate Format:
```javascript
{
  "name": "Cabintan",
  "distance": 0,
  "coordinates": [10.9997, 124.6289], // [latitude, longitude]
  "zone": "reference",
  "isReference": true
}
```

## 🔄 **Updating Distances**

To recalculate distances with updated data:

1. Run the Python script again:
   ```bash
   python geopy-distance-calculator.py
   ```

2. Initialize in Firebase:
   - Go to Staff Dashboard → Delivery Settings
   - Click "Initialize All Barangays"
   - This updates Firebase with new Geopy-calculated data

## 🛠️ **Troubleshooting**

### Common Issues:

1. **Geocoding Fails**: The script includes fallback coordinates for Cabintan
2. **Rate Limiting**: Built-in 1-second delays between API calls
3. **Network Issues**: Script will log errors and continue with available data

### Logs:
Check the console output for:
- Successfully geocoded locations
- Failed geocoding attempts
- Fallback coordinate usage

## 📱 **Customer App Integration**

The customer app now has access to:

```javascript
// Example usage in customer app
const deliveryFee = await api.getDeliveryFeeForBarangay('Cabintan');
const pickupArea = await api.getPickupArea();
const totalCost = await api.calculateDeliveryFee('Cabintan', 500);
```

## 🎯 **Benefits**

1. **Accuracy**: Real geographic distances instead of estimates
2. **Flexibility**: Easy to update when new data is available
3. **Separation**: Clear distinction between reference point and delivery areas
4. **Automation**: One-click initialization of all barangay data
5. **Transparency**: Shows coordinates and calculation methods

## 📋 **Data Structure**

```javascript
{
  "barangayName": {
    "name": "Barangay Name",
    "distance": 5.2, // km from Cabintan
    "coordinates": [10.9997, 124.6289],
    "zone": "urban",
    "suggestedFee": 40,
    "isReference": false,
    "calculatedAt": 1704067200
  }
}
```

This system provides accurate, maintainable, and transparent distance calculations for the AgriCart delivery system! 🚚📍
