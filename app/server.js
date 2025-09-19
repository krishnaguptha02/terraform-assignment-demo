const express = require('express');
const cors = require('cors');
const helmet = require('helmet');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Store for demonstration
let requestCount = 0;
let startTime = Date.now();

// Routes
app.get('/', (req, res) => {
  requestCount++;
  const uptime = Math.floor((Date.now() - startTime) / 1000);
  
  res.json({
    message: 'Welcome to GKE Sample Application!',
    version: process.env.APP_VERSION || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    podName: process.env.HOSTNAME || 'unknown',
    requestCount: requestCount,
    uptime: `${uptime} seconds`,
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    podName: process.env.HOSTNAME || 'unknown'
  });
});

app.get('/load', (req, res) => {
  // Simulate CPU intensive task for auto-scaling demo
  const iterations = 1000000;
  let result = 0;
  
  for (let i = 0; i < iterations; i++) {
    result += Math.sqrt(i);
  }
  
  res.json({
    message: 'Load test completed',
    result: result,
    iterations: iterations,
    podName: process.env.HOSTNAME || 'unknown',
    timestamp: new Date().toISOString()
  });
});

app.get('/version', (req, res) => {
  res.json({
    version: process.env.APP_VERSION || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    podName: process.env.HOSTNAME || 'unknown'
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    error: 'Something went wrong!',
    message: err.message
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    message: 'The requested resource was not found'
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server is running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`Version: ${process.env.APP_VERSION || '1.0.0'}`);
});
