import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

// Global runtime error overlay for debugging
window.addEventListener('error', (event) => {
  const container = document.getElementById('runtime-error-banner') || document.createElement('div');
  container.id = 'runtime-error-banner';
  container.style.position = 'fixed';
  container.style.top = '0';
  container.style.left = '0';
  container.style.width = '100%';
  container.style.backgroundColor = '#ef4444';
  container.style.color = 'white';
  container.style.padding = '12px 24px';
  container.style.zIndex = '999999';
  container.style.fontSize = '14px';
  container.style.fontFamily = 'monospace';
  container.style.boxShadow = '0 4px 20px rgba(239, 68, 68, 0.3)';
  container.innerHTML = `<strong>Runtime Error:</strong> ${event.message} <br/><span style="font-size:11px;opacity:0.8;">at ${event.filename}:${event.lineno}:${event.colno}</span>`;
  document.body.appendChild(container);
});

window.addEventListener('unhandledrejection', (event) => {
  const container = document.getElementById('runtime-error-banner') || document.createElement('div');
  container.id = 'runtime-error-banner';
  container.style.position = 'fixed';
  container.style.top = '0';
  container.style.left = '0';
  container.style.width = '100%';
  container.style.backgroundColor = '#f59e0b';
  container.style.color = 'white';
  container.style.padding = '12px 24px';
  container.style.zIndex = '999999';
  container.style.fontSize = '14px';
  container.style.fontFamily = 'monospace';
  container.style.boxShadow = '0 4px 20px rgba(245, 158, 11, 0.3)';
  container.innerHTML = `<strong>Promise Rejection:</strong> ${event.reason?.message || event.reason} <br/><span style="font-size:11px;opacity:0.8;">${event.reason?.stack || ''}</span>`;
  document.body.appendChild(container);
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
