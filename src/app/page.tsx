'use client';

import { useState } from 'react';
import { Search, RefreshCw, Settings } from 'lucide-react';
import { useWeatherData } from '@/hooks/useWeatherData';
import { CloudProvider } from '@/types/weather';

export default function WeatherDashboard() {
  const [searchLocation, setSearchLocation] = useState('New York');
  const { weatherData, providers, loading, error, lastUpdated, dataSource, refreshData } = useWeatherData(searchLocation);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    // The hook will automatically refetch when searchLocation changes
  };



  const getStatusColor = (status: string) => {
    switch (status) {
      case 'healthy':
        return 'bg-green-500';
      case 'degraded':
        return 'bg-yellow-500';
      case 'offline':
        return 'bg-red-500';
      default:
        return 'bg-gray-500';
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-600 via-blue-700 to-blue-800">
      {/* Header */}
      <header className="flex items-center justify-between p-6 text-white">
        <div className="flex items-center space-x-3">
          <div className="w-10 h-10 bg-white/20 rounded-lg flex items-center justify-center">
            ☀️
          </div>
          <div>
            <h1 className="text-xl font-semibold">Multi-Cloud Weather</h1>
            <p className="text-blue-100 text-sm">Real-time data from leading cloud providers</p>
          </div>
        </div>

        <div className="flex items-center space-x-4">
          {/* Search */}
          <form onSubmit={handleSearch} className="relative">
            <input
              type="text"
              placeholder="Search location..."
              value={searchLocation}
              onChange={(e) => setSearchLocation(e.target.value)}
              className="bg-white/20 border border-white/30 rounded-lg px-4 py-2 pl-10 text-white placeholder-white/70 focus:outline-none focus:ring-2 focus:ring-white/50 w-64"
            />
            <Search className="absolute left-3 top-2.5 h-4 w-4 text-white/70" />
          </form>

          {/* Refresh Button */}
          <button
            onClick={refreshData}
            disabled={loading}
            className="bg-white/20 border border-white/30 rounded-lg p-2 text-white hover:bg-white/30 transition-colors disabled:opacity-50"
          >
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </button>

          {/* Settings Button */}
          <button className="bg-white/20 border border-white/30 rounded-lg p-2 text-white hover:bg-white/30 transition-colors">
            <Settings className="h-4 w-4" />
          </button>
        </div>
      </header>

      <div className="px-6 pb-6">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Left Column - Provider Status */}
          <div className="space-y-6">
            {/* Cloud Providers */}
            <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20">
              <div className="space-y-4">
                {providers.map((provider: CloudProvider) => (
                  <div
                    key={provider.id}
                    className="flex items-center space-x-3 p-3 bg-white/5 rounded-xl provider-card"
                  >
                    <div className="flex items-center space-x-3 flex-1">
                      <div className="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-semibold text-sm">
                        {provider.id === 'aws' && 'AWS'}
                        {provider.id === 'azure' && 'AZ'}
                        {provider.id === 'gcp' && 'GCP'}
                      </div>
                      <div className="flex-1">
                        <div className="text-white font-medium">{provider.name}</div>
                        <div className="text-white/70 text-sm">{provider.description}</div>
                      </div>
                    </div>
                    <div className={`w-3 h-3 rounded-full ${getStatusColor(provider.status)}`}></div>
                  </div>
                ))}
              </div>

              <div className="mt-6 pt-4 border-t border-white/20">
                <div className="text-white/70 text-sm">Last updated</div>
                <div className="text-white/70 text-sm">Data source</div>
                <div className="text-white text-sm mt-1">{lastUpdated || 'Loading...'}</div>
              </div>
            </div>
          </div>

          {/* Center Column - Current Weather */}
          <div className="lg:col-span-2">
            <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 border border-white/20">
              <div className="flex items-start justify-between mb-8">
                <div>
                  <h2 className="text-white text-lg font-medium mb-2">Current conditions</h2>
                  {weatherData && (
                    <div className="text-white/90">
                      <div className="text-4xl font-light mb-2">{weatherData.temperature}°</div>
                      <div className="text-white/70">{weatherData.location}</div>
                    </div>
                  )}
                </div>
                <div className="text-right">
                  <div className="text-6xl mb-2">🌤️</div>
                  <div className="text-white font-medium">
                    {weatherData?.description || 'Partly Cloudy'}
                  </div>
                </div>
              </div>

              {/* Weather Metrics Grid */}
              {weatherData && (
                <div className="grid grid-cols-2 md:grid-cols-3 gap-6">
                  <div className="text-center">
                    <div className="text-white/70 text-sm mb-1">Temperature</div>
                    <div className="text-white text-2xl font-light">{weatherData.temperature}°</div>
                  </div>
                  
                  <div className="text-center">
                    <div className="text-white/70 text-sm mb-1">Humidity</div>
                    <div className="text-white text-2xl font-light">{weatherData.humidity}%</div>
                  </div>
                  
                  <div className="text-center">
                    <div className="text-white/70 text-sm mb-1">Wind Speed</div>
                    <div className="text-white text-2xl font-light">{weatherData.windSpeed} mph</div>
                  </div>
                  
                  <div className="text-center">
                    <div className="text-white/70 text-sm mb-1">Pressure</div>
                    <div className="text-white text-2xl font-light">{weatherData.pressure} in</div>
                  </div>
                  
                  <div className="text-center">
                    <div className="text-white/70 text-sm mb-1">Visibility</div>
                    <div className="text-white text-2xl font-light">{weatherData.visibility} mi</div>
                  </div>
                  
                  <div className="text-center">
                    <div className="text-white/70 text-sm mb-1">UV Index</div>
                    <div className="text-white text-2xl font-light">{weatherData.uvIndex}</div>
                  </div>
                </div>
              )}

              {loading && (
                <div className="flex items-center justify-center py-12">
                  <div className="text-white/70">Loading weather data...</div>
                </div>
              )}

              {error && (
                <div className="bg-red-500/20 border border-red-500/30 rounded-lg p-4 mt-4">
                  <div className="text-red-200 text-sm">{error}</div>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Bottom Section - Additional Info */}
        <div className="mt-6">
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20">
            <div className="text-center">
              <div className="text-white/70 text-sm">
                Weather data provided by <span className="text-orange-400 font-medium">{dataSource}</span>
              </div>
              <div className="text-white/60 text-xs mt-1">
                Multi-cloud architecture ensures 99.9% uptime and global coverage
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
} 