export interface WeatherData {
  temperature: number;
  humidity: number;
  windSpeed: number;
  pressure: number;
  visibility: number;
  uvIndex: number;
  description: string;
  condition: string;
  location: string;
  lastUpdated: string;
}

export interface CloudProvider {
  id: 'aws' | 'azure' | 'gcp';
  name: string;
  status: 'healthy' | 'degraded' | 'offline';
  description: string;
  responseTime?: number;
  lastUpdated?: string;
}

export interface WeatherResponse {
  success: boolean;
  data?: WeatherData;
  error?: string;
  provider?: string;
  timestamp: string;
}

export interface AggregatedWeatherResponse {
  aggregatedData: {
    locations: Array<{
      locationId: string;
      locationName: string;
      lat: number;
      lon: number;
      agreement: number;
      consensus: WeatherData;
      providers: Array<{
        name: string;
        status: string;
        responseTime: number;
      }>;
    }>;
  };
  cloudProviders: string[];
  executionTimeMs: number;
  timestamp: string;
} 