const AWS = require('aws-sdk');
const axios = require('axios');

// Initialize AWS services
const dynamodb = new AWS.DynamoDB.DocumentClient();
const lambda = new AWS.Lambda();

/**
 * Cross-Cloud Weather Data Aggregation Lambda
 * Fetches weather data from AWS, Azure, and GCP in parallel
 */
exports.handler = async (event, context) => {
  console.log('Cross-Cloud Aggregation Lambda started');
  console.log('Event:', JSON.stringify(event, null, 2));

  const startTime = Date.now();
  const timestamp = new Date().toISOString();
  
  try {
    // Parse query parameters
    const location = event.queryStringParameters?.location;
    const includeRaw = event.queryStringParameters?.includeRaw === 'true';
    const cloudProviders = event.queryStringParameters?.providers?.split(',') || ['aws', 'azure', 'gcp'];
    
    // Fetch data from all cloud providers in parallel
    const cloudPromises = [];
    
    if (cloudProviders.includes('aws')) {
      cloudPromises.push(fetchAWSWeatherData(location));
    }
    
    if (cloudProviders.includes('azure')) {
      cloudPromises.push(fetchAzureWeatherData(location));
    }
    
    if (cloudProviders.includes('gcp')) {
      cloudPromises.push(fetchGCPWeatherData(location));
    }
    
    console.log(`Fetching data from ${cloudPromises.length} cloud providers`);
    
    const results = await Promise.allSettled(cloudPromises);
    
    // Process results
    const cloudData = {};
    const errors = {};
    
    results.forEach((result, index) => {
      const provider = cloudProviders[index];
      
      if (result.status === 'fulfilled') {
        cloudData[provider] = result.value;
      } else {
        errors[provider] = result.reason.message;
        console.error(`${provider} failed:`, result.reason);
      }
    });
    
    // Create cross-cloud aggregation
    const aggregatedData = await createCrossCloudAggregation(cloudData, timestamp, includeRaw);
    
    // Store aggregated data in DynamoDB
    if (location) {
      await storeAggregatedData(aggregatedData, location, timestamp);
    }
    
    const executionTime = Date.now() - startTime;
    
    const response = {
      success: true,
      timestamp,
      executionTimeMs: executionTime,
      cloudProviders: Object.keys(cloudData),
      failedProviders: Object.keys(errors),
      location: location || 'multiple',
      aggregatedData,
      errors: Object.keys(errors).length > 0 ? errors : undefined
    };
    
    console.log(`Cross-cloud aggregation completed in ${executionTime}ms`);
    return createResponse(200, response);
    
  } catch (error) {
    console.error('Aggregation failed:', error);
    
    return createResponse(500, {
      success: false,
      error: error.message,
      timestamp,
      executionTimeMs: Date.now() - startTime
    });
  }
};

/**
 * Fetch weather data from AWS (local DynamoDB or Lambda invocation)
 */
async function fetchAWSWeatherData(location) {
  console.log('Fetching AWS weather data');
  
  if (location) {
    // Query DynamoDB for specific location
    const params = {
      TableName: process.env.DYNAMODB_TABLE,
      KeyConditionExpression: 'location_id = :locationId',
      ExpressionAttributeValues: {
        ':locationId': location
      },
      ScanIndexForward: false, // Get latest first
      Limit: 1
    };
    
    const result = await dynamodb.query(params).promise();
    
    if (result.Items && result.Items.length > 0) {
      return {
        source: 'aws-dynamodb',
        data: result.Items[0].weather_data,
        timestamp: result.Items[0].timestamp
      };
    }
  }
  
  // Fallback: Invoke AWS weather Lambda directly
  const functionName = process.env.AWS_LAMBDA_FUNCTION || 'cloud-weather-dashboard-weather-fetcher';
  
  const params = {
    FunctionName: functionName,
    InvocationType: 'RequestResponse',
    Payload: JSON.stringify({
      queryStringParameters: location ? { location } : undefined
    })
  };
  
  const result = await lambda.invoke(params).promise();
  const response = JSON.parse(result.Payload);
  
  if (response.statusCode === 200) {
    const body = JSON.parse(response.body);
    return {
      source: 'aws-lambda',
      data: body.data || body,
      timestamp: body.timestamp
    };
  }
  
  throw new Error(`AWS Lambda failed: ${response.body}`);
}

/**
 * Fetch weather data from Azure Function
 */
async function fetchAzureWeatherData(location) {
  console.log('Fetching Azure weather data');
  
  const azureUrl = process.env.AZURE_FUNCTION_URL;
  if (!azureUrl) {
    throw new Error('Azure Function URL not configured');
  }
  
  const url = location ? `${azureUrl}/api/weather?location=${encodeURIComponent(location)}` : `${azureUrl}/api/weather`;
  
  const response = await axios.get(url, {
    timeout: 30000,
    headers: {
      'Accept': 'application/json'
    }
  });
  
  return {
    source: 'azure-function',
    data: response.data.data || response.data,
    timestamp: response.data.timestamp || new Date().toISOString()
  };
}

/**
 * Fetch weather data from GCP Cloud Run
 */
async function fetchGCPWeatherData(location) {
  console.log('Fetching GCP weather data');
  
  const gcpUrl = process.env.GCP_FUNCTION_URL;
  if (!gcpUrl) {
    throw new Error('GCP Function URL not configured');
  }
  
  const url = location ? `${gcpUrl}/weather?location=${encodeURIComponent(location)}` : `${gcpUrl}/weather`;
  
  const response = await axios.get(url, {
    timeout: 30000,
    headers: {
      'Accept': 'application/json'
    }
  });
  
  return {
    source: 'gcp-cloudrun',
    data: response.data.data || response.data,
    timestamp: response.data.timestamp || new Date().toISOString()
  };
}

/**
 * Create cross-cloud aggregated weather data
 */
async function createCrossCloudAggregation(cloudData, timestamp, includeRaw = false) {
  const providers = Object.keys(cloudData);
  
  if (providers.length === 0) {
    throw new Error('No cloud provider data available');
  }
  
  const aggregation = {
    timestamp,
    cloudProviders: providers,
    dataPoints: providers.length,
    consensus: {},
    variations: {},
    reliability: {},
    summary: {}
  };
  
  // Collect all weather data points
  const allData = [];
  const locationData = {};
  
  providers.forEach(provider => {
    const data = cloudData[provider].data;
    
    if (Array.isArray(data)) {
      // Multiple locations
      data.forEach(item => {
        if (item.aggregated) {
          allData.push({ ...item.aggregated, provider, source: cloudData[provider].source });
          
          if (!locationData[item.locationId]) {
            locationData[item.locationId] = {
              locationId: item.locationId,
              locationName: item.locationName,
              latitude: item.latitude,
              longitude: item.longitude,
              providers: []
            };
          }
          locationData[item.locationId].providers.push({
            provider,
            data: item.aggregated,
            timestamp: item.timestamp
          });
        }
      });
    } else if (data.aggregated) {
      // Single location
      allData.push({ ...data.aggregated, provider, source: cloudData[provider].source });
      
      const locationId = data.locationId || 'unknown';
      if (!locationData[locationId]) {
        locationData[locationId] = {
          locationId: data.locationId,
          locationName: data.locationName,
          latitude: data.latitude,
          longitude: data.longitude,
          providers: []
        };
      }
      locationData[locationId].providers.push({
        provider,
        data: data.aggregated,
        timestamp: data.timestamp
      });
    }
  });
  
  // Calculate consensus values across cloud providers
  if (allData.length > 0) {
    aggregation.consensus = calculateConsensus(allData);
    aggregation.variations = calculateVariations(allData);
    aggregation.reliability = calculateReliability(allData, providers.length);
  }
  
  // Create location-based aggregations
  aggregation.locations = Object.values(locationData).map(location => {
    if (location.providers.length > 1) {
      const locationConsensus = calculateConsensus(location.providers.map(p => p.data));
      const locationVariations = calculateVariations(location.providers.map(p => p.data));
      
      return {
        ...location,
        consensus: locationConsensus,
        variations: locationVariations,
        agreement: calculateAgreement(location.providers.map(p => p.data))
      };
    }
    
    return {
      ...location,
      consensus: location.providers[0].data,
      variations: {},
      agreement: 100
    };
  });
  
  // Add summary statistics
  aggregation.summary = {
    totalLocations: Object.keys(locationData).length,
    averageTemperature: aggregation.consensus.temperature,
    temperatureRange: aggregation.variations.temperature,
    overallReliability: aggregation.reliability.overall,
    dataFreshness: calculateDataFreshness(cloudData)
  };
  
  // Include raw data if requested
  if (includeRaw) {
    aggregation.rawData = cloudData;
  }
  
  return aggregation;
}

/**
 * Calculate consensus values across providers
 */
function calculateConsensus(dataPoints) {
  if (dataPoints.length === 0) return {};
  
  const metrics = ['temperature', 'humidity', 'pressure', 'windSpeed', 'cloudiness'];
  const consensus = {};
  
  metrics.forEach(metric => {
    const values = dataPoints
      .map(point => point[metric])
      .filter(val => val !== undefined && val !== null);
    
    if (values.length > 0) {
      consensus[metric] = Math.round((values.reduce((sum, val) => sum + val, 0) / values.length) * 100) / 100;
    }
  });
  
  return consensus;
}

/**
 * Calculate variations (standard deviation) across providers
 */
function calculateVariations(dataPoints) {
  if (dataPoints.length <= 1) return {};
  
  const metrics = ['temperature', 'humidity', 'pressure', 'windSpeed', 'cloudiness'];
  const variations = {};
  
  metrics.forEach(metric => {
    const values = dataPoints
      .map(point => point[metric])
      .filter(val => val !== undefined && val !== null);
    
    if (values.length > 1) {
      const mean = values.reduce((sum, val) => sum + val, 0) / values.length;
      const variance = values.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / values.length;
      variations[metric] = Math.round(Math.sqrt(variance) * 100) / 100;
    }
  });
  
  return variations;
}

/**
 * Calculate reliability scores
 */
function calculateReliability(dataPoints, totalProviders) {
  const reliability = {
    dataAvailability: (dataPoints.length / totalProviders) * 100,
    overall: 0
  };
  
  // Calculate confidence based on agreement between providers
  if (dataPoints.length > 1) {
    const tempValues = dataPoints
      .map(point => point.temperature)
      .filter(val => val !== undefined);
    
    if (tempValues.length > 1) {
      const maxTemp = Math.max(...tempValues);
      const minTemp = Math.min(...tempValues);
      const tempRange = maxTemp - minTemp;
      
      // High reliability if temperature readings are within 2°C
      reliability.temperatureAgreement = Math.max(0, 100 - (tempRange * 25));
    }
  }
  
  reliability.overall = Math.round(
    (reliability.dataAvailability + (reliability.temperatureAgreement || 100)) / 2
  );
  
  return reliability;
}

/**
 * Calculate agreement percentage between providers
 */
function calculateAgreement(dataPoints) {
  if (dataPoints.length <= 1) return 100;
  
  const tempValues = dataPoints
    .map(point => point.temperature)
    .filter(val => val !== undefined);
  
  if (tempValues.length <= 1) return 100;
  
  const maxTemp = Math.max(...tempValues);
  const minTemp = Math.min(...tempValues);
  const tempRange = maxTemp - minTemp;
  
  // Agreement based on temperature variance (within 2°C = 100% agreement)
  return Math.max(0, Math.round(100 - (tempRange * 25)));
}

/**
 * Calculate data freshness across cloud providers
 */
function calculateDataFreshness(cloudData) {
  const now = new Date();
  const timestamps = Object.values(cloudData)
    .map(provider => new Date(provider.timestamp))
    .filter(date => !isNaN(date.getTime()));
  
  if (timestamps.length === 0) return 'unknown';
  
  const averageAge = timestamps.reduce((sum, timestamp) => {
    return sum + (now - timestamp);
  }, 0) / timestamps.length;
  
  const minutes = Math.round(averageAge / (1000 * 60));
  
  if (minutes < 5) return 'very-fresh';
  if (minutes < 15) return 'fresh';
  if (minutes < 60) return 'moderate';
  return 'stale';
}

/**
 * Store aggregated data in DynamoDB
 */
async function storeAggregatedData(aggregatedData, location, timestamp) {
  const tableName = process.env.DYNAMODB_TABLE;
  
  const params = {
    TableName: tableName,
    Item: {
      location_id: `aggregated-${location}`,
      timestamp: timestamp,
      cloud_provider: 'aggregated',
      aggregated_data: aggregatedData,
      ttl: Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60) // 7 days TTL
    }
  };
  
  try {
    await dynamodb.put(params).promise();
    console.log(`Stored aggregated data for ${location}`);
  } catch (error) {
    console.error('Failed to store aggregated data:', error);
    // Don't throw - this is not critical
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