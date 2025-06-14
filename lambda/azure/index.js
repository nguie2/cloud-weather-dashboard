const { CosmosClient } = require('@azure/cosmos');
const { DefaultAzureCredential } = require('@azure/identity');
const { SecretClient } = require('@azure/keyvault-secrets');
const axios = require('axios');

// Azure Function main handler
module.exports = async function (context, req) {
  context.log('Azure Weather Function started');
  
  const startTime = Date.now();
  const timestamp = new Date().toISOString();
  
  try {
    // Initialize Azure services
    const credential = new DefaultAzureCredential();
    const secretClient = new SecretClient(
      `https://${process.env.KEY_VAULT_NAME}.vault.azure.net/`,
      credential
    );
    
    // Get API keys from Key Vault
    const secrets = await getSecrets(secretClient);
    
    // Initialize Cosmos DB
    const cosmosClient = new CosmosClient(process.env.COSMOS_CONNECTION_STRING);
    const database = cosmosClient.database(process.env.COSMOS_DATABASE);
    const container = database.container(process.env.COSMOS_CONTAINER);
    
    // Parse request parameters
    const location = req.query.location;
    const locations = location ? [location] : getDefaultLocations();
    
    if (typeof location === 'string') {
      // Handle single location request
      const result = await fetchWeatherForLocation(location, secrets, timestamp, container);
      context.res = {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: result
      };
      return;
    }
    
    // Fetch weather data for all locations in parallel
    const weatherPromises = locations.map(loc => 
      fetchWeatherForLocation(loc, secrets, timestamp, container)
    );
    
    const results = await Promise.allSettled(weatherPromises);
    
    // Process results
    const successful = [];
    const failed = [];
    
    results.forEach((result, index) => {
      if (result.status === 'fulfilled') {
        successful.push(result.value);
      } else {
        failed.push({
          location: locations[index],
          error: result.reason.message
        });
        context.log.error(`Failed to fetch weather for ${locations[index].name || locations[index]}:`, result.reason);
      }
    });
    
    const executionTime = Date.now() - startTime;
    
    const response = {
      success: true,
      timestamp,
      cloudProvider: 'azure',
      executionTimeMs: executionTime,
      summary: {
        total: locations.length,
        successful: successful.length,
        failed: failed.length
      },
      data: successful,
      errors: failed.length > 0 ? failed : undefined
    };
    
    context.log(`Azure function completed in ${executionTime}ms`);
    
    context.res = {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
      body: response
    };
    
  } catch (error) {
    context.log.error('Function execution failed:', error);
    
    context.res = {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
      body: {
        success: false,
        error: error.message,
        cloudProvider: 'azure',
        timestamp,
        executionTimeMs: Date.now() - startTime
      }
    };
  }
};

/**
 * Get default locations
 */
function getDefaultLocations() {
  return [
    { id: 'new-york', name: 'New York', lat: 40.7128, lon: -74.0060 },
    { id: 'london', name: 'London', lat: 51.5074, lon: -0.1278 },
    { id: 'tokyo', name: 'Tokyo', lat: 35.6762, lon: 139.6503 },
    { id: 'sydney', name: 'Sydney', lat: -33.8688, lon: 151.2093 },
    { id: 'paris', name: 'Paris', lat: 48.8566, lon: 2.3522 },
    { id: 'moscow', name: 'Moscow', lat: 55.7558, lon: 37.6176 },
    { id: 'beijing', name: 'Beijing', lat: 39.9042, lon: 116.4074 },
    { id: 'mumbai', name: 'Mumbai', lat: 19.0760, lon: 72.8777 }
  ];
}

/**
 * Fetch weather data for a specific location
 */
async function fetchWeatherForLocation(location, secrets, timestamp, container) {
  console.log(`Fetching weather for ${location.name || location}`);
  
  let lat, lon, locationId, locationName;
  
  if (typeof location === 'string') {
    // Geocode the location
    const geoData = await geocodeLocation(location, secrets.openweatherApiKey);
    lat = geoData.lat;
    lon = geoData.lon;
    locationId = geoData.id;
    locationName = geoData.name;
  } else {
    lat = location.lat;
    lon = location.lon;
    locationId = location.id;
    locationName = location.name;
  }
  
  // Fetch weather data from multiple sources in parallel
  const weatherPromises = [
    fetchOpenWeatherData(lat, lon, secrets.openweatherApiKey),
    fetchWeatherAPIData(lat, lon, secrets.weatherApiKey),
    fetchAccuWeatherData(lat, lon, secrets.accuweatherApiKey)
  ];
  
  const weatherResults = await Promise.allSettled(weatherPromises);
  
  // Aggregate weather data
  const aggregatedData = {
    locationId,
    locationName,
    latitude: lat,
    longitude: lon,
    timestamp,
    cloudProvider: 'azure',
    sources: {},
    aggregated: {}
  };
  
  // Process weather results
  if (weatherResults[0].status === 'fulfilled') {
    aggregatedData.sources.openweather = weatherResults[0].value;
  } else {
    console.warn('OpenWeather API failed:', weatherResults[0].reason?.message);
  }
  
  if (weatherResults[1].status === 'fulfilled') {
    aggregatedData.sources.weatherapi = weatherResults[1].value;
  } else {
    console.warn('WeatherAPI failed:', weatherResults[1].reason?.message);
  }
  
  if (weatherResults[2].status === 'fulfilled') {
    aggregatedData.sources.accuweather = weatherResults[2].value;
  } else {
    console.warn('AccuWeather API failed:', weatherResults[2].reason?.message);
  }
  
  // Create aggregated weather summary
  aggregatedData.aggregated = createAggregatedWeather(aggregatedData.sources);
  
  // Store in Cosmos DB
  await storeWeatherData(aggregatedData, container);
  
  return aggregatedData;
}

/**
 * Get API keys from Azure Key Vault
 */
async function getSecrets(secretClient) {
  try {
    const [openweatherSecret, weatherApiSecret, accuweatherSecret] = await Promise.all([
      secretClient.getSecret('openweather-api-key'),
      secretClient.getSecret('weather-api-key'),
      secretClient.getSecret('accuweather-api-key')
    ]);
    
    return {
      openweatherApiKey: openweatherSecret.value,
      weatherApiKey: weatherApiSecret.value,
      accuweatherApiKey: accuweatherSecret.value
    };
  } catch (error) {
    console.error('Failed to retrieve secrets from Key Vault:', error);
    throw new Error('Unable to retrieve API keys from Key Vault');
  }
}

/**
 * Geocode a location string using OpenWeather Geocoding API
 */
async function geocodeLocation(location, apiKey) {
  const url = `http://api.openweathermap.org/geo/1.0/direct?q=${encodeURIComponent(location)}&limit=1&appid=${apiKey}`;
  
  const response = await axios.get(url, { timeout: 10000 });
  
  if (!response.data || response.data.length === 0) {
    throw new Error(`Location not found: ${location}`);
  }
  
  const data = response.data[0];
  return {
    id: `${data.name.toLowerCase().replace(/\s+/g, '-')}-${data.country.toLowerCase()}`,
    name: `${data.name}, ${data.country}`,
    lat: data.lat,
    lon: data.lon
  };
}

/**
 * Fetch data from OpenWeather API
 */
async function fetchOpenWeatherData(lat, lon, apiKey) {
  const url = `http://api.openweathermap.org/data/2.5/weather?lat=${lat}&lon=${lon}&appid=${apiKey}&units=metric`;
  
  const response = await axios.get(url, { timeout: 10000 });
  
  return {
    source: 'openweather',
    temperature: response.data.main.temp,
    humidity: response.data.main.humidity,
    pressure: response.data.main.pressure,
    description: response.data.weather[0].description,
    windSpeed: response.data.wind.speed,
    windDirection: response.data.wind.deg,
    visibility: response.data.visibility,
    cloudiness: response.data.clouds.all,
    timestamp: new Date(response.data.dt * 1000).toISOString(),
    raw: response.data
  };
}

/**
 * Fetch data from WeatherAPI
 */
async function fetchWeatherAPIData(lat, lon, apiKey) {
  const url = `http://api.weatherapi.com/v1/current.json?key=${apiKey}&q=${lat},${lon}&aqi=yes`;
  
  const response = await axios.get(url, { timeout: 10000 });
  
  return {
    source: 'weatherapi',
    temperature: response.data.current.temp_c,
    humidity: response.data.current.humidity,
    pressure: response.data.current.pressure_mb,
    description: response.data.current.condition.text,
    windSpeed: response.data.current.wind_kph / 3.6, // Convert to m/s
    windDirection: response.data.current.wind_degree,
    visibility: response.data.current.vis_km,
    cloudiness: response.data.current.cloud,
    uvIndex: response.data.current.uv,
    airQuality: response.data.current.air_quality,
    timestamp: response.data.current.last_updated,
    raw: response.data
  };
}

/**
 * Fetch data from AccuWeather API
 */
async function fetchAccuWeatherData(lat, lon, apiKey) {
  // First, get location key
  const locationUrl = `http://dataservice.accuweather.com/locations/v1/cities/geoposition/search?apikey=${apiKey}&q=${lat},${lon}`;
  
  const locationResponse = await axios.get(locationUrl, { timeout: 10000 });
  const locationKey = locationResponse.data.Key;
  
  // Then get current conditions
  const weatherUrl = `http://dataservice.accuweather.com/currentconditions/v1/${locationKey}?apikey=${apiKey}&details=true`;
  
  const weatherResponse = await axios.get(weatherUrl, { timeout: 10000 });
  const data = weatherResponse.data[0];
  
  return {
    source: 'accuweather',
    temperature: data.Temperature.Metric.Value,
    humidity: data.RelativeHumidity,
    pressure: data.Pressure.Metric.Value,
    description: data.WeatherText,
    windSpeed: data.Wind.Speed.Metric.Value / 3.6, // Convert to m/s
    windDirection: data.Wind.Direction.Degrees,
    visibility: data.Visibility.Metric.Value,
    cloudiness: data.CloudCover,
    uvIndex: data.UVIndex,
    timestamp: data.LocalObservationDateTime,
    raw: data
  };
}

/**
 * Create aggregated weather data from multiple sources
 */
function createAggregatedWeather(sources) {
  const sourceCount = Object.keys(sources).length;
  
  if (sourceCount === 0) {
    throw new Error('No weather data available from any source');
  }
  
  const aggregated = {
    temperature: 0,
    humidity: 0,
    pressure: 0,
    windSpeed: 0,
    windDirection: 0,
    visibility: 0,
    cloudiness: 0,
    descriptions: [],
    confidence: 0
  };
  
  let tempSum = 0, humiditySum = 0, pressureSum = 0;
  let windSpeedSum = 0, windDirSum = 0, visibilitySum = 0, cloudinessSum = 0;
  let validSources = 0;
  
  Object.values(sources).forEach(source => {
    if (source.temperature !== undefined) {
      tempSum += source.temperature;
      validSources++;
    }
    if (source.humidity !== undefined) humiditySum += source.humidity;
    if (source.pressure !== undefined) pressureSum += source.pressure;
    if (source.windSpeed !== undefined) windSpeedSum += source.windSpeed;
    if (source.windDirection !== undefined) windDirSum += source.windDirection;
    if (source.visibility !== undefined) visibilitySum += source.visibility;
    if (source.cloudiness !== undefined) cloudinessSum += source.cloudiness;
    if (source.description) aggregated.descriptions.push(source.description);
  });
  
  // Calculate averages
  aggregated.temperature = Math.round((tempSum / validSources) * 10) / 10;
  aggregated.humidity = Math.round(humiditySum / validSources);
  aggregated.pressure = Math.round(pressureSum / validSources);
  aggregated.windSpeed = Math.round((windSpeedSum / validSources) * 10) / 10;
  aggregated.windDirection = Math.round(windDirSum / validSources);
  aggregated.visibility = Math.round(visibilitySum / validSources);
  aggregated.cloudiness = Math.round(cloudinessSum / validSources);
  aggregated.confidence = Math.round((validSources / sourceCount) * 100);
  
  return aggregated;
}

/**
 * Store weather data in Cosmos DB
 */
async function storeWeatherData(weatherData, container) {
  try {
    const item = {
      id: `${weatherData.locationId}-${Date.now()}`,
      location_id: weatherData.locationId,
      timestamp: weatherData.timestamp,
      cloud_provider: 'azure',
      location_name: weatherData.locationName,
      latitude: weatherData.latitude,
      longitude: weatherData.longitude,
      weather_data: weatherData,
      _ts: Math.floor(Date.now() / 1000),
      ttl: 30 * 24 * 60 * 60 // 30 days in seconds
    };
    
    await container.items.create(item);
    console.log(`Stored weather data for ${weatherData.locationName} in Cosmos DB`);
  } catch (error) {
    console.error('Cosmos DB storage failed:', error);
    throw error;
  }
} 