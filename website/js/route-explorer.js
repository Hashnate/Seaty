document.addEventListener('DOMContentLoaded', () => {
  const routeCards = document.querySelectorAll('.route-ui-card');
  const mapContainer = document.getElementById('seaty-network-map');

  if (!mapContainer) return;

  // 1. Initialize Leaflet Map
  // Center roughly on Sri Lanka, zoom level to fit the island
  const map = L.map('seaty-network-map', {
    center: [7.8731, 80.7718],
    zoom: 7,
    scrollWheelZoom: false, // Disable scroll zoom as requested
    zoomControl: false,     // Hide default zoom controls for a cleaner look
    attributionControl: false
  });

  // 2. Add Premium Map Tiles (CartoDB Positron for light theme)
  L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OSM</a> contributors',
    subdomains: 'abcd',
    maxZoom: 19
  }).addTo(map);

  // 3. Define City Coordinates
  const cities = {
    colombo: [6.9271, 79.8612],
    kandy: [7.2906, 80.6337],
    galle: [6.0535, 80.2210],
    ella: [6.8667, 81.0466]
  };

  // Custom HTML Markers to match existing UI
  const createMarker = (name, isActive) => {
    return L.divIcon({
      className: 'custom-leaflet-marker',
      html: `
        <div class="map-node ${isActive ? 'active-node' : ''}">
          <div class="marker-circle"></div>
          <div class="marker-label">${name}</div>
        </div>
      `,
      iconSize: [20, 20],
      iconAnchor: [10, 10]
    });
  };

  // Add Markers to Map
  const markers = {
    colombo: L.marker(cities.colombo, { icon: createMarker('Colombo', false) }).addTo(map),
    kandy: L.marker(cities.kandy, { icon: createMarker('Kandy', false) }).addTo(map),
    galle: L.marker(cities.galle, { icon: createMarker('Galle', false) }).addTo(map),
    ella: L.marker(cities.ella, { icon: createMarker('Ella', false) }).addTo(map)
  };

  // 4. Define Realistic Routes (Waypoints following highways)
  const routes = {
    'col-kan': [
      cities.colombo,
      [7.0271, 80.0212], // Kadawatha
      [7.2500, 80.3500], // Kegalle
      cities.kandy
    ],
    'col-gal': [
      cities.colombo,
      [6.8333, 79.9833], // Makumbura
      [6.5833, 80.0833], // Mathugama exit
      [6.2333, 80.1333], // Kurundugahahetekma
      cities.galle
    ],
    'col-ell': [
      cities.colombo,
      [6.6833, 80.3833], // Ratnapura
      [6.7167, 80.7833], // Belihuloya
      [6.8167, 80.9500], // Haputale
      cities.ella
    ]
  };

  // Draw Polylines
  const defaultPathStyle = { color: '#cbd5e1', weight: 4, dashArray: '6, 6', opacity: 0.8 };
  const activePathStyle = { color: '#f97316', weight: 4, dashArray: null, opacity: 1, className: 'active-leaflet-path' };

  const polylines = {
    'col-kan': L.polyline(routes['col-kan'], defaultPathStyle).addTo(map),
    'col-gal': L.polyline(routes['col-gal'], defaultPathStyle).addTo(map),
    'col-ell': L.polyline(routes['col-ell'], defaultPathStyle).addTo(map)
  };

  // Helper to remove active classes
  function resetMap() {
    // Reset polylines
    Object.values(polylines).forEach(p => p.setStyle(defaultPathStyle));
    
    // Reset markers
    Object.entries(markers).forEach(([key, marker]) => {
      // Capitalize first letter for label
      const name = key.charAt(0).toUpperCase() + key.slice(1);
      marker.setIcon(createMarker(name, false));
    });
  }

  const routeNodeMapping = {
    'col-kan': ['colombo', 'kandy'],
    'col-gal': ['colombo', 'galle'],
    'col-ell': ['colombo', 'ella']
  };

  routeCards.forEach(card => {
    const activateCard = () => {
      routeCards.forEach(c => c.classList.remove('active-route'));
      card.classList.add('active-route');

      const routeId = card.getAttribute('data-route');

      resetMap();

      // Highlight specific polyline
      if (polylines[routeId]) {
        polylines[routeId].setStyle(activePathStyle);
        // Bring to front so it overlays inactive routes
        polylines[routeId].bringToFront();
      }

      // Highlight specific nodes
      const nodesToHighlight = routeNodeMapping[routeId];
      if (nodesToHighlight) {
        nodesToHighlight.forEach(nodeId => {
          if (markers[nodeId]) {
            const name = nodeId.charAt(0).toUpperCase() + nodeId.slice(1);
            markers[nodeId].setIcon(createMarker(name, true));
            markers[nodeId].setZIndexOffset(1000); // Bring active markers to front
          }
        });
      }
    };

    card.addEventListener('mouseenter', activateCard);
    card.addEventListener('click', activateCard);
  });

  // Activate first route by default
  const firstCard = document.querySelector('.route-ui-card[data-route="col-kan"]');
  if (firstCard) {
    // trigger a fake click to initialize state
    firstCard.dispatchEvent(new Event('mouseenter'));
  }
});
