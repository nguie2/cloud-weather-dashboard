const AWS = require('aws-sdk');
const axios = require('axios');

// Initialize AWS services
const dynamodb = new AWS.DynamoDB.DocumentClient();
const secretsManager = new AWS.SecretsManager();

// Default locations to fetch weather data for
const DEFAULT_LOCATIONS = [
  { id: 'new-york', name: 'New York', lat: 40.7128, lon: -74.0060 },
  { id: 'london', name: 'London', lat: 51.5074, lon: -0.1278 },
  { id: 'tokyo', name: 'Tokyo', lat: 35.6762, lon: 139.6503 },
  { id: 'sydney', name: 'Sydney', lat: -33.8688, lon: 151.2093 },
  { id: 'paris', name: 'Paris', lat: 48.8566, lon: 2.3522 },
  { id: 'moscow', name: 'Moscow', lat: 55.7558, lon: 37.6176 },
  { id: 'beijing', name: 'Beijing', lat: 39.9042, lon: 116.4074 },
  { id: 'mumbai', name: 'Mumbai', lat: 19.0760, lon: 72.8777 }
];

/**
 * Main Lambda handler
 */
exports.handler = async (event, context) => {
  console.log('AWS Weather Fetcher Lambda started');
  console.log('Event:', JSON.stringify(event, null, 2));

  const startTime = Date.now();
  const timestamp = new Date().toISOString();
  
  try {
    // Get API keys from Secrets Manager
    const secrets = await getSecrets();
    
    // Get locations from event or use defaults
    const locations = event.locations || DEFAULT_LOCATIONS;
    const specificLocation = event.queryStringParameters?.location;
    
    if (specificLocation) {
      // Handle single location request
      const result = await fetchWeatherForLocation(specificLocation, secrets, timestamp);
      return createResponse(200, result);
    }
    
    // Fetch weather data for all locations in parallel
    const weatherPromises = locations.map(location => 
      fetchWeatherForLocation(location, secrets, timestamp)
    );
    
    const results = await Promise.allSettled(weatherPromises);
    
    // Process results and separate successful from failed
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
      }
    });
    
    const executionTime = Date.now() - startTime;
    
    const response = {
      success: true,
      timestamp,
      cloudProvider: 'aws',
      executionTimeMs: executionTime,
      summary: {
        total: locations.length,
        successful: successful.length,
        failed: failed.length
      },
      data: successful,
      errors: failed.length > 0 ? failed : undefined
    };
    
    console.log(`AWS Lambda completed in ${executionTime}ms`);
    return createResponse(200, response);
    
  } catch (error) {
    console.error('Lambda execution failed:', error);
    
    return createResponse(500, {
      success: false,
      error: error.message,
      cloudProvider: 'aws',
      timestamp
    });
  }
};

/**
 * Fetch weather data for a specific location
 */
async function fetchWeatherForLocation(location, secrets, timestamp) {
  console.log(`Fetching weather for ${location.name || location}`);
  
  let lat, lon, locationId, locationName;
  
  if (typeof location === 'string') {
    // If location is a string, treat it as a city name and geocode
    const geoData = await geocodeLocation(location, secrets.openweather_api_key);
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
    fetchOpenWeatherData(lat, lon, secrets.openweather_api_key),
    fetchWeatherAPIData(lat, lon, secrets.weather_api_key),
    fetchAccuWeatherData(lat, lon, secrets.accuweather_api_key)
  ];
  
  const weatherResults = await Promise.allSettled(weatherPromises);
  
  // Aggregate weather data
  const aggregatedData = {
    locationId,
    locationName,
    latitude: lat,
    longitude: lon,
    timestamp,
    cloudProvider: 'aws',
    sources: {},
    aggregated: {}
  };
  
  // Process OpenWeather data
  if (weatherResults[0].status === 'fulfilled') {
    const openWeatherData = weatherResults[0].value;
    aggregatedData.sources.openweather = openWeatherData;
  } else {
    console.warn('OpenWeather API failed:', weatherResults[0].reason.message);
  }
  
  // Process WeatherAPI data
  if (weatherResults[1].status === 'fulfilled') {
    const weatherAPIData = weatherResults[1].value;
    aggregatedData.sources.weatherapi = weatherAPIData;
  } else {
    console.warn('WeatherAPI failed:', weatherResults[1].reason.message);
  }
  
  // Process AccuWeather data
  if (weatherResults[2].status === 'fulfilled') {
    const accuWeatherData = weatherResults[2].value;
    aggregatedData.sources.accuweather = accuWeatherData;
  } else {
    console.warn('AccuWeather API failed:', weatherResults[2].reason.message);
  }
  
  // Create aggregated weather summary
  aggregatedData.aggregated = createAggregatedWeather(aggregatedData.sources);
  
  // Store in DynamoDB
  await storeWeatherData(aggregatedData);
  
  return aggregatedData;
}

/**
 * Get API keys from AWS Secrets Manager
 */
async function getSecrets() {
  const secretArn = process.env.SECRET_ARN;
  
  try {
    const secretValue = await secretsManager.getSecretValue({ SecretId: secretArn }).promise();
    return JSON.parse(secretValue.SecretString);
  } catch (error) {
    console.error('Failed to retrieve secrets:', error);
    throw new Error('Unable to retrieve API keys from Secrets Manager');
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
 * Store weather data in DynamoDB
 */
async function storeWeatherData(weatherData) {
  const tableName = process.env.DYNAMODB_TABLE;
  
  const params = {
    TableName: tableName,
    Item: {
      location_id: weatherData.locationId,
      timestamp: weatherData.timestamp,
      cloud_provider: 'aws',
      location_name: weatherData.locationName,
      latitude: weatherData.latitude,
      longitude: weatherData.longitude,
      weather_data: weatherData,
      ttl: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60) // 30 days TTL
    }
  };
  
  try {
    await dynamodb.put(params).promise();
    console.log(`Stored weather data for ${weatherData.locationName}`);
  } catch (error) {
    console.error('DynamoDB storage failed:', error);
    throw error;
  }
}

/**
 * Create HTTP response
 */
function createResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
    },
    body: JSON.stringify(body)
  };
} 